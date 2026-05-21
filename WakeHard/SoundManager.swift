@preconcurrency import AVFAudio
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class SoundManager: ObservableObject {
    @Published private(set) var isPreviewPlaying = false
    @Published private(set) var isPreviewPaused = false
    @Published private(set) var previewPlaybackTime: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private let musicPlayer = MPMusicPlayerController.applicationMusicPlayer
    private let volumeView = MPVolumeView(frame: .zero)
    private var loopTimer: Timer?
    private var progressTimer: Timer?
    private var volumeRampTask: Task<Void, Never>?
    private var pendingMusicStartTask: DispatchWorkItem?
    private var previewResetTask: DispatchWorkItem?
    private var musicStartToken: UUID?
    private var completedMusicStartToken: UUID?
    private var activePlayback: ActivePlayback?
    private let minimumRampVolume: Float = 0.01

    private enum ActivePlayback {
        case audio
        case music
    }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        attachVolumeViewIfNeeded()
    }

    func play(sound: AlarmSound, volume: Float, loops: Bool) {
        stop()

        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: nil) else { return }
        play(url: url, volume: volume, loops: loops, startTime: 0, loopDuration: 0, gentleWakeDuration: 0)
    }

    func play(alarm: Alarm, loops: Bool) {
        stop()
        let volume = Float(alarm.volume)
        // Always honor the gentle-wake ramp, including for preview (loops == false).
        // The preview is meant to demonstrate exactly what the alarm will do.
        let gentleWakeDuration = alarm.gentleWakeDuration.duration

        if
            let urlString = alarm.songAssetURLString,
            let url = URL(string: urlString)
        {
            // Real-alarm playback path: replace any stale Now Playing info so
            // the Dynamic Island shows our alarm icon, not whatever the system
            // may have published from a previous playback session.
            if loops {
                AlarmNowPlayingInfo.startForAlarm(label: alarm.label)
            }
            play(
                url: url,
                volume: volume,
                loops: loops,
                startTime: alarm.effectivePlaybackStartTime,
                loopDuration: alarm.effectivePlaybackLoopDuration,
                gentleWakeDuration: gentleWakeDuration
            )
            return
        }

        if playMediaLibrarySong(for: alarm, loops: loops) {
            return
        }

        guard let url = Bundle.main.url(forResource: alarm.sound.fileName, withExtension: nil) else { return }
        play(url: url, volume: volume, loops: loops, startTime: 0, loopDuration: 0, gentleWakeDuration: gentleWakeDuration)
    }

    private func play(
        url: URL,
        volume: Float,
        loops: Bool,
        startTime: Double,
        loopDuration: Double,
        gentleWakeDuration: TimeInterval
    ) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            setSystemVolume(volume)
            player.volume = gentleWakeDuration > 0 ? 0 : volume
            player.currentTime = min(max(0, startTime), max(0, player.duration - 0.5))
            // If the gentle-wake ramp is longer than one natural playthrough,
            // loop the audio so the ramp can actually be heard end-to-end.
            let naturalSegmentDuration: TimeInterval = loopDuration > 0
                ? loopDuration
                : max(0, player.duration - player.currentTime)
            let needsLoopForRamp = gentleWakeDuration > 0
                && naturalSegmentDuration < gentleWakeDuration + 1
            let effectiveLoops = loops || needsLoopForRamp
            player.numberOfLoops = effectiveLoops && loopDuration <= 0 ? -1 : 0
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            activePlayback = .audio
            if gentleWakeDuration > 0 {
                startAudioPlayerVolumeRamp(to: volume, duration: gentleWakeDuration)
            }
            isPreviewPlaying = true
            isPreviewPaused = false
            previewPlaybackTime = player.currentTime
            startProgressMonitor()
            startLoopMonitor(startTime: startTime, loopDuration: loopDuration, loops: effectiveLoops)
            let baseDuration: TimeInterval = loopDuration > 0
                ? loopDuration
                : player.duration - player.currentTime
            // Keep the preview alive long enough for the ramp to finish,
            // plus a short tail at the target volume.
            let previewDuration = gentleWakeDuration > 0
                ? max(baseDuration, gentleWakeDuration + 4)
                : baseDuration
            schedulePreviewReset(after: previewDuration, loops: loops)
        } catch {
            print("Unable to play alarm sound: \(error)")
        }
    }

    func pause() {
        pendingMusicStartTask?.cancel()
        pendingMusicStartTask = nil
        previewResetTask?.cancel()
        previewResetTask = nil
        volumeRampTask?.cancel()
        volumeRampTask = nil
        musicStartToken = nil
        completedMusicStartToken = nil
        switch activePlayback {
        case .audio:
            audioPlayer?.pause()
            previewPlaybackTime = audioPlayer?.currentTime ?? previewPlaybackTime
        case .music:
            musicPlayer.pause()
            previewPlaybackTime = musicPlayer.currentPlaybackTime
        case .none:
            return
        }
        progressTimer?.invalidate()
        progressTimer = nil
        isPreviewPlaying = false
        isPreviewPaused = true
    }

    func resume() {
        switch activePlayback {
        case .audio:
            audioPlayer?.play()
        case .music:
            musicPlayer.play()
        case .none:
            return
        }
        startProgressMonitor()
        isPreviewPlaying = true
        isPreviewPaused = false
    }

    func stop() {
        pendingMusicStartTask?.cancel()
        pendingMusicStartTask = nil
        previewResetTask?.cancel()
        previewResetTask = nil
        musicStartToken = nil
        completedMusicStartToken = nil
        loopTimer?.invalidate()
        loopTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        volumeRampTask?.cancel()
        volumeRampTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        musicPlayer.stop()
        activePlayback = nil
        isPreviewPlaying = false
        isPreviewPaused = false
        previewPlaybackTime = 0
        BackgroundAlarmEngine.shared.stopPreviewOrAlarm()
    }

    private func playMediaLibrarySong(for alarm: Alarm, loops: Bool) -> Bool {
        guard let persistentID = alarm.songPersistentID else { return false }
        let volume = Float(alarm.volume)
        let gentleWakeDuration = alarm.gentleWakeDuration.duration

        let query = MPMediaQuery.songs()
        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaItemPropertyPersistentID
        )
        query.addFilterPredicate(predicate)

        guard let item = query.items?.first else { return false }
        let startTime = alarm.effectivePlaybackStartTime
        let naturalSegmentDuration: TimeInterval = alarm.effectivePlaybackLoopDuration > 0
            ? alarm.effectivePlaybackLoopDuration
            : max(0, item.playbackDuration - startTime)
        let needsLoopForRamp = gentleWakeDuration > 0
            && naturalSegmentDuration < gentleWakeDuration + 1
        let effectiveLoops = loops || needsLoopForRamp
        setSystemVolume(gentleWakeDuration > 0 ? minimumRampVolume : volume)
        musicPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
        musicPlayer.repeatMode = effectiveLoops && !alarm.hasClipLoop ? .one : .none
        activePlayback = .music
        isPreviewPlaying = true
        isPreviewPaused = false
        previewPlaybackTime = startTime
        let token = UUID()
        musicStartToken = token
        completedMusicStartToken = nil
        // The fallback work item handles the case where prepareToPlay's
        // completion never fires. `startMusicPlayback` is idempotent via
        // `completedMusicStartToken`, so the prepareToPlay callback below
        // calls it directly instead of capturing the DispatchWorkItem
        // (which isn't Sendable and would warn in Swift 6 concurrency).
        let startTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startMusicPlayback(
                at: startTime,
                token: token,
                targetVolume: volume,
                gentleWakeDuration: gentleWakeDuration
            )
        }
        pendingMusicStartTask = startTask
        musicPlayer.prepareToPlay { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.musicStartToken == token else { return }
                self.startMusicPlayback(
                    at: startTime,
                    token: token,
                    targetVolume: volume,
                    gentleWakeDuration: gentleWakeDuration
                )
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: startTask)
        startProgressMonitor()
        startLoopMonitor(
            startTime: startTime,
            loopDuration: alarm.effectivePlaybackLoopDuration,
            loops: effectiveLoops
        )
        let baseDuration: TimeInterval = alarm.effectivePlaybackLoopDuration > 0
            ? alarm.effectivePlaybackLoopDuration
            : item.playbackDuration - startTime
        let previewDuration = gentleWakeDuration > 0
            ? max(baseDuration, gentleWakeDuration + 4)
            : baseDuration
        schedulePreviewReset(after: previewDuration, loops: loops)
        // Only the live-alarm path overrides Now Playing — previews are short
        // and leaving the song's metadata alone keeps the editor clean.
        if loops {
            AlarmNowPlayingInfo.startForAlarm(label: alarm.label)
        }
        return true
    }

    private func startMusicPlayback(
        at startTime: Double,
        token: UUID,
        targetVolume: Float,
        gentleWakeDuration: TimeInterval
    ) {
        guard musicStartToken == token, completedMusicStartToken != token else { return }
        completedMusicStartToken = token
        pendingMusicStartTask?.cancel()
        pendingMusicStartTask = nil
        musicPlayer.currentPlaybackTime = startTime
        previewPlaybackTime = startTime
        musicPlayer.play()
        if gentleWakeDuration > 0 {
            startSystemVolumeRamp(to: targetVolume, duration: gentleWakeDuration)
        }

        for delay in [0.12, 0.35, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.musicStartToken == token, self.activePlayback == .music else { return }
                    if abs(self.musicPlayer.currentPlaybackTime - startTime) > 1.25 {
                        self.musicPlayer.currentPlaybackTime = startTime
                        self.previewPlaybackTime = startTime
                        self.musicPlayer.play()
                    }
                }
        }
    }

    private func startLoopMonitor(startTime: Double, loopDuration: Double, loops: Bool) {
        loopTimer?.invalidate()
        guard loopDuration > 0 else { return }

        let endTime = startTime + loopDuration
        loopTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPreviewPlaying else { return }
                switch self.activePlayback {
                case .audio:
                    guard let player = self.audioPlayer, player.currentTime >= endTime else { return }
                    guard loops else {
                        self.previewPlaybackTime = endTime
                        self.stop()
                        return
                    }
                    player.currentTime = startTime
                    self.previewPlaybackTime = startTime
                    player.play()
                case .music:
                    guard self.musicPlayer.currentPlaybackTime >= endTime else { return }
                    guard loops else {
                        self.previewPlaybackTime = endTime
                        self.stop()
                        return
                    }
                    self.musicPlayer.currentPlaybackTime = startTime
                    self.previewPlaybackTime = startTime
                    self.musicPlayer.play()
                case .none:
                    return
                }
            }
        }
    }

    private func startProgressMonitor() {
        progressTimer?.invalidate()
        updatePreviewPlaybackTime()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPreviewPlaying else { return }
                self.updatePreviewPlaybackTime()
            }
        }
    }

    private func updatePreviewPlaybackTime() {
        switch activePlayback {
        case .audio:
            previewPlaybackTime = audioPlayer?.currentTime ?? previewPlaybackTime
        case .music:
            previewPlaybackTime = musicPlayer.currentPlaybackTime
        case .none:
            return
        }
    }

    private func schedulePreviewReset(after duration: TimeInterval, loops: Bool) {
        previewResetTask?.cancel()
        previewResetTask = nil
        guard !loops, duration.isFinite, duration > 0 else { return }

        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isPreviewPlaying else { return }
                self.stop()
            }
        }
        previewResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, duration + 0.25), execute: task)
    }

    private func setSystemVolume(_ volume: Float) {
        attachVolumeViewIfNeeded()
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        let clampedVolume = min(1, max(0, volume))
        slider.value = clampedVolume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            slider.value = clampedVolume
        }
    }

    private func startSystemVolumeRamp(to targetVolume: Float, duration: TimeInterval) {
        volumeRampTask?.cancel()
        volumeRampTask = nil

        guard duration > 0 else {
            setSystemVolume(targetVolume)
            return
        }

        setSystemVolume(minimumRampVolume)
        let startedAt = Date()
        volumeRampTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard self.activePlayback == .music else { return }

                let progress = min(1, Date().timeIntervalSince(startedAt) / duration)
                let rampedVolume = max(self.minimumRampVolume, targetVolume * Float(progress))
                self.setSystemVolume(rampedVolume)

                guard progress < 1 else { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            if !Task.isCancelled {
                self.setSystemVolume(targetVolume)
                self.volumeRampTask = nil
            }
        }
    }

    private func startAudioPlayerVolumeRamp(to targetVolume: Float, duration: TimeInterval) {
        volumeRampTask?.cancel()
        volumeRampTask = nil

        guard let player = audioPlayer else { return }

        guard duration > 0 else {
            player.volume = targetVolume
            return
        }

        player.volume = 0
        let startedAt = Date()
        volumeRampTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard self.activePlayback == .audio else { return }

                let progress = min(1, Date().timeIntervalSince(startedAt) / duration)
                self.audioPlayer?.volume = targetVolume * Float(progress)

                guard progress < 1 else { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            if !Task.isCancelled {
                self.audioPlayer?.volume = targetVolume
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
}
