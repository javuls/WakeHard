@preconcurrency import AVFAudio
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class BackgroundAlarmEngine: ObservableObject {
    static let shared = BackgroundAlarmEngine()

    @Published private(set) var isArmed = false
    @Published private(set) var armedUntil: Date?

    private var silentPlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private let musicPlayer = MPMusicPlayerController.applicationMusicPlayer
    private var timer: DispatchSourceTimer?
    private var alarmLoopTimer: DispatchSourceTimer?
    private var volumeRampTask: Task<Void, Never>?
    private var keepAliveWatchdogTimer: DispatchSourceTimer?
    private var armedAlarm: Alarm?
    // Set when the engine is actively ringing an alarm (between fire() and
    // stopAlarmAndRearm()). Lets fire() be idempotent so AlarmRingingView
    // can call it safely, and lets the background/interruption handlers
    // know whether they should restart playback or just keep the session warm.
    private var currentlyRingingAlarm: Alarm?
    private var activeAlarmPlayback: ActiveAlarmPlayback?
    private var musicStartToken: UUID?
    private let volumeView = MPVolumeView(frame: .zero)

    private enum ActiveAlarmPlayback {
        case audio
        case music
    }

    private init() {
        configureKeepAliveAudioSession()
        attachVolumeViewIfNeeded()
        observeLifecycle()
    }

    func arm(alarms: [Alarm]) {
        timer?.cancel()
        timer = nil

        guard let next = alarms
            .filter(\.isEnabled)
            .compactMap({ alarm -> (Alarm, Date)? in
                guard let date = alarm.nextFireDate else { return nil }
                return (alarm, date)
            })
            .sorted(by: { $0.1 < $1.1 })
            .first
        else {
            keepAliveWatchdogTimer?.cancel()
            keepAliveWatchdogTimer = nil
            stopSilentLoop()
            armedAlarm = nil
            armedUntil = nil
            isArmed = false
            return
        }

        armedAlarm = next.0
        armedUntil = next.1
        isArmed = true
        configureKeepAliveAudioSession()
        startSilentLoop()
        startKeepAliveWatchdog()
        scheduleTimer(for: next.1)
    }

    func fire(alarm: Alarm) {
        // Idempotency: AlarmRingingView.onAppear calls this to ensure the
        // engine is playing, and the interruption/foreground handlers call
        // it to resume. If we're already ringing this same alarm and the
        // player is actively producing audio, there's nothing to do.
        if currentlyRingingAlarm?.id == alarm.id, isAlarmAudioPlaying {
            AlarmNowPlayingInfo.refresh()
            return
        }
        currentlyRingingAlarm = alarm
        // Tear down any half-state from a previous fire so we start clean.
        alarmLoopTimer?.cancel()
        alarmLoopTimer = nil
        volumeRampTask?.cancel()
        volumeRampTask = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
        musicStartToken = nil
        if activeAlarmPlayback == .music {
            musicPlayer.stop()
        }
        activeAlarmPlayback = nil

        stopSilentLoop()
        keepAliveWatchdogTimer?.cancel()
        keepAliveWatchdogTimer = nil
        configureAlarmAudioSession()
        AlarmRuntimeStore.setRingingAlarm(alarm.id)
        WakeHardLiveActivityManager.startRinging(alarm: alarm)
        let targetVolume = Float(alarm.volume)
        let gentleWakeDuration = alarm.gentleWakeDuration.duration

        // Wake the screen and bring app to foreground
        ScreenWakeManager.wakeScreenAndShowAlarm()

        if playSelectedSongIfNeeded(for: alarm, volume: targetVolume) {
            VibrationManager.shared.start(alarm: alarm)
            NotificationCenter.default.post(name: .backgroundAlarmFired, object: alarm)
            return
        }

        if playMediaLibrarySongIfNeeded(for: alarm, fallbackVolume: targetVolume) {
            VibrationManager.shared.start(alarm: alarm)
            NotificationCenter.default.post(name: .backgroundAlarmFired, object: alarm)
            return
        }

        if alarm.hasSelectedSong {
            if AppSettings.failSafeBackupSound {
                playBackupSound(for: alarm, volume: targetVolume)
            }
            VibrationManager.shared.start(alarm: alarm)
            NotificationCenter.default.post(name: .backgroundAlarmFired, object: alarm)
            return
        }

        guard let url = Bundle.main.url(forResource: alarm.sound.fileName, withExtension: nil) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            setSystemVolume(targetVolume)
            player.volume = gentleWakeDuration > 0 ? 0 : targetVolume
            player.numberOfLoops = -1
            player.prepareToPlay()
            alarmPlayer = player
            activeAlarmPlayback = .audio
            player.play()
            if gentleWakeDuration > 0 {
                startAudioPlayerVolumeRamp(to: targetVolume, duration: gentleWakeDuration)
            }
            VibrationManager.shared.start(alarm: alarm)
            NotificationCenter.default.post(name: .backgroundAlarmFired, object: alarm)
        } catch {
            print("Unable to fire background alarm: \(error)")
        }
    }

    func stopAlarmAndRearm(alarms: [Alarm]) {
        alarmLoopTimer?.cancel()
        alarmLoopTimer = nil
        volumeRampTask?.cancel()
        volumeRampTask = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
        musicPlayer.stop()
        musicStartToken = nil
        activeAlarmPlayback = nil
        VibrationManager.shared.stop()
        // Clear ringing flag so background/interruption handlers stop trying
        // to resume the alarm audio.
        currentlyRingingAlarm = nil
        // Tear down the alarm-themed Now Playing override and detach its
        // notification observer so future music playback isn't intercepted.
        AlarmNowPlayingInfo.stop()
        arm(alarms: alarms)
    }

    func stopPreviewOrAlarm() {
        alarmLoopTimer?.cancel()
        alarmLoopTimer = nil
        volumeRampTask?.cancel()
        volumeRampTask = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
        musicPlayer.stop()
        musicStartToken = nil
        activeAlarmPlayback = nil
        VibrationManager.shared.stop()
    }

    private func configureKeepAliveAudioSession() {
        configureAudioSession(options: [.mixWithOthers])
    }

    private func configureAlarmAudioSession() {
        configureAudioSession(options: [])
    }

    private func configureAudioSession(options: AVAudioSession.CategoryOptions) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func startSilentLoop() {
        configureKeepAliveAudioSession()
        if silentPlayer?.isPlaying == true { return }
        guard let url = Bundle.main.url(forResource: "keepalive.wav", withExtension: nil) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.02
            player.numberOfLoops = -1
            player.prepareToPlay()
            player.play()
            silentPlayer = player
        } catch {
            print("Unable to start silent loop: \(error)")
        }
    }

    private func stopSilentLoop() {
        silentPlayer?.stop()
        silentPlayer = nil
    }

    private func startKeepAliveWatchdog() {
        keepAliveWatchdogTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.isArmed, self.currentlyRingingAlarm == nil else { return }
                if
                    let armedUntil = self.armedUntil,
                    armedUntil <= .now,
                    let alarm = self.armedAlarm
                {
                    self.fire(alarm: alarm)
                    return
                }
                self.configureKeepAliveAudioSession()
                if self.silentPlayer?.isPlaying != true {
                    self.startSilentLoop()
                }
            }
        }
        timer.resume()
        keepAliveWatchdogTimer = timer
    }

    private var isAlarmAudioPlaying: Bool {
        switch activeAlarmPlayback {
        case .audio:
            return alarmPlayer?.isPlaying == true
        case .music:
            return musicPlayer.playbackState == .playing
        case .none:
            return false
        }
    }

    private func scheduleTimer(for date: Date) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(0, date.timeIntervalSinceNow))
        timer.setEventHandler { [weak self] in
            guard let self, let alarm = self.armedAlarm else { return }
            Task { @MainActor in
                self.fire(alarm: alarm)
            }
        }
        timer.resume()
        self.timer = timer
    }

    private func playSelectedSongIfNeeded(for alarm: Alarm, volume: Float) -> Bool {
        guard
            let urlString = alarm.songAssetURLString,
            let url = URL(string: urlString)
        else {
            // No direct asset URL; try the media-library player next. Downloaded
            // Apple Music tracks often land there even when `assetURL` is nil.
            return false
        }

        do {
            let gentleWakeDuration = alarm.gentleWakeDuration.duration
            let player = try AVAudioPlayer(contentsOf: url)
            setSystemVolume(volume)
            player.volume = gentleWakeDuration > 0 ? 0 : volume
            player.currentTime = min(alarm.effectivePlaybackStartTime, max(0, player.duration - 0.5))
            player.numberOfLoops = alarm.hasClipLoop ? 0 : -1
            player.prepareToPlay()
            alarmPlayer = player
            activeAlarmPlayback = .audio
            player.play()
            if gentleWakeDuration > 0 {
                startAudioPlayerVolumeRamp(to: volume, duration: gentleWakeDuration)
            }
            scheduleAudioLoopIfNeeded(alarm: alarm)
            // Replace whatever Now Playing info exists with our alarm icon so
            // the Dynamic Island shows the green alarm icon instead of album art.
            AlarmNowPlayingInfo.startForAlarm(label: alarm.label)
            return true
        } catch {
            print("Unable to play selected alarm song: \(error)")
            return false
        }
    }

    private func playMediaLibrarySongIfNeeded(for alarm: Alarm, fallbackVolume: Float) -> Bool {
        guard let persistentID = alarm.songPersistentID else { return false }
        guard alarm.gentleWakeDuration == .off else {
            // MPMusicPlayerController has no per-player volume. The old system
            // volume ramp was unreliable and could jump to full volume, so use
            // the backup AVAudioPlayer tone when gentle wake must be honored.
            return false
        }

        let query = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaItemPropertyPersistentID
        )
        query.addFilterPredicate(predicate)

        guard let item = query.items?.first else { return false }
        let targetVolume = Float(alarm.volume)
        setSystemVolume(targetVolume)
        musicPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
        musicPlayer.repeatMode = alarm.hasClipLoop ? .none : .one
        let startTime = alarm.effectivePlaybackStartTime
        let token = UUID()
        musicStartToken = token
        musicPlayer.prepareToPlay { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.musicStartToken == token else { return }
                self.startAlarmMusicPlayback(at: startTime, token: token)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.musicStartToken == token else { return }
            self.startAlarmMusicPlayback(at: startTime, token: token)
        }
        scheduleMusicLoopIfNeeded(alarm: alarm)
        // Override the system Now Playing info so the Dynamic Island shows
        // our green alarm icon instead of the song's album artwork.
        // The helper re-applies on every nowPlayingItemDidChangeNotification
        // so the music player can't clobber it back.
        AlarmNowPlayingInfo.startForAlarm(label: alarm.label)
        activeAlarmPlayback = .music
        scheduleMediaFallbackIfNeeded(for: alarm, token: token, volume: fallbackVolume)
        return true
    }

    private func scheduleMediaFallbackIfNeeded(for alarm: Alarm, token: UUID, volume: Float) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard
                let self,
                self.musicStartToken == token,
                self.activeAlarmPlayback == .music,
                self.musicPlayer.playbackState != .playing
            else { return }
            guard AppSettings.failSafeBackupSound else { return }

            self.musicPlayer.stop()
            self.musicStartToken = nil
            self.activeAlarmPlayback = nil
            self.playBackupSound(for: alarm, volume: volume)
        }
    }

    private func playBackupSound(for alarm: Alarm, volume: Float) {
        guard let url = Bundle.main.url(forResource: alarm.sound.fileName, withExtension: nil) else { return }
        do {
            let gentleWakeDuration = alarm.gentleWakeDuration.duration
            let player = try AVAudioPlayer(contentsOf: url)
            setSystemVolume(volume)
            player.volume = gentleWakeDuration > 0 ? 0 : volume
            player.numberOfLoops = -1
            player.prepareToPlay()
            alarmPlayer = player
            activeAlarmPlayback = .audio
            player.play()
            if gentleWakeDuration > 0 {
                startAudioPlayerVolumeRamp(to: volume, duration: gentleWakeDuration)
            }
            AlarmNowPlayingInfo.startForAlarm(label: alarm.label)
        } catch {
            print("Unable to play backup alarm sound: \(error)")
        }
    }

    private func startAlarmMusicPlayback(at startTime: Double, token: UUID) {
        guard musicStartToken == token, activeAlarmPlayback == .music else { return }
        musicPlayer.currentPlaybackTime = startTime
        musicPlayer.play()
        AlarmNowPlayingInfo.refresh()

        for delay in [0.12, 0.35, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.musicStartToken == token, self.activeAlarmPlayback == .music else { return }
                if abs(self.musicPlayer.currentPlaybackTime - startTime) > 1.25 {
                    self.musicPlayer.currentPlaybackTime = startTime
                    self.musicPlayer.play()
                }
                AlarmNowPlayingInfo.refresh()
            }
        }
    }

    private func scheduleAudioLoopIfNeeded(alarm: Alarm) {
        alarmLoopTimer?.cancel()
        guard alarm.hasClipLoop else { return }
        let startTime = alarm.effectivePlaybackStartTime
        let endTime = startTime + alarm.effectivePlaybackLoopDuration
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            guard let self, let player = self.alarmPlayer, player.currentTime >= endTime else { return }
            player.currentTime = startTime
            player.play()
        }
        timer.resume()
        alarmLoopTimer = timer
    }

    private func scheduleMusicLoopIfNeeded(alarm: Alarm) {
        alarmLoopTimer?.cancel()
        guard alarm.hasClipLoop else { return }
        let startTime = alarm.effectivePlaybackStartTime
        let endTime = startTime + alarm.effectivePlaybackLoopDuration
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            guard let self, self.musicPlayer.currentPlaybackTime >= endTime else { return }
            self.musicPlayer.currentPlaybackTime = startTime
            self.musicPlayer.play()
        }
        timer.resume()
        alarmLoopTimer = timer
    }

    private func setSystemVolume(_ volume: Float) {
        attachVolumeViewIfNeeded()
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            slider.value = volume
        }
    }

    private func startAudioPlayerVolumeRamp(to targetVolume: Float, duration: TimeInterval) {
        volumeRampTask?.cancel()
        volumeRampTask = nil

        guard let player = alarmPlayer else { return }

        guard duration > 0 else {
            player.volume = targetVolume
            return
        }

        player.volume = 0
        let startedAt = Date()
        volumeRampTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard self.activeAlarmPlayback == .audio else { return }

                let progress = min(1, Date().timeIntervalSince(startedAt) / duration)
                self.alarmPlayer?.volume = targetVolume * Float(progress)

                guard progress < 1 else { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            if !Task.isCancelled {
                self.alarmPlayer?.volume = targetVolume
                self.volumeRampTask = nil
            }
        }
    }

    private func attachVolumeViewIfNeeded() {
        guard volumeView.superview == nil else { return }
        volumeView.frame = CGRect(x: -120, y: -120, width: 80, height: 40)
        volumeView.alpha = 0.01
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .addSubview(volumeView)
    }

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.currentlyRingingAlarm != nil {
                    // An alarm is actively ringing; its player is producing
                    // audio. Don't start the silent keep-alive loop; it would
                    // contend with the alarm player for the audio session.
                    self.configureAlarmAudioSession()
                    AlarmNowPlayingInfo.refresh()
                    return
                }
                self.configureKeepAliveAudioSession()
                if self.isArmed { self.startSilentLoop() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let alarm = self.currentlyRingingAlarm else { return }
                // If we came back to foreground and the player got paused
                // (iOS sometimes pauses background audio across app switches
                // even with the audio background mode), restart it. fire()
                // is idempotent so this is safe.
                self.configureAlarmAudioSession()
                if self.isAlarmAudioPlaying {
                    AlarmNowPlayingInfo.refresh()
                } else {
                    self.fire(alarm: alarm)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard
                let userInfo = notification.userInfo,
                let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            Task { @MainActor in
                guard let self else { return }
                if interruptionType == .began {
                    guard self.currentlyRingingAlarm == nil, self.isArmed else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        Task { @MainActor in
                            guard let self, self.currentlyRingingAlarm == nil, self.isArmed else { return }
                            self.configureKeepAliveAudioSession()
                            if self.silentPlayer?.isPlaying != true {
                                self.startSilentLoop()
                            }
                        }
                    }
                    return
                }

                guard interruptionType == .ended else { return }
                self.configureKeepAliveAudioSession()
                if let alarm = self.currentlyRingingAlarm {
                    self.configureAlarmAudioSession()
                    // Resume the alarm audio that the interruption silenced.
                    if self.isAlarmAudioPlaying {
                        AlarmNowPlayingInfo.refresh()
                    } else {
                        self.fire(alarm: alarm)
                    }
                    return
                }
                if self.isArmed { self.startSilentLoop() }
            }
        }
    }
}

extension Notification.Name {
    static let backgroundAlarmFired = Notification.Name("backgroundAlarmFired")
}
