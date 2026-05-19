import AudioToolbox
import CoreHaptics
import Foundation
import UIKit

@MainActor
final class VibrationManager {
    static let shared = VibrationManager()

    private var hapticEngine: CHHapticEngine?
    private var vibrationToken = UUID()
    private var isRunning = false

    private init() {
        prepareHaptics()
    }

    func start(alarm: Alarm) {
        stop()
        guard alarm.vibrateEnabled else { return }

        vibrationToken = UUID()
        isRunning = true
        prepareHaptics()
        scheduleNextPulse(
            token: vibrationToken,
            pattern: alarm.vibrationPattern,
            strength: alarm.vibrationStrength,
            index: 0,
            delay: 0,
            systemFallback: true
        )
    }

    func preview(pattern: VibrationPattern, strength: Double) {
        stop()
        vibrationToken = UUID()
        isRunning = true
        prepareHaptics()
        scheduleNextPulse(
            token: vibrationToken,
            pattern: pattern,
            strength: strength,
            index: 0,
            delay: 0,
            systemFallback: false
        )
        let token = vibrationToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.vibrationToken == token else { return }
            self.stop()
        }
    }

    func stop() {
        isRunning = false
        vibrationToken = UUID()
        // CHHapticEngine.stop() (no completion handler) is non-throwing,
        // so no `try?` is needed.
        hapticEngine?.stop()
    }

    private func scheduleNextPulse(
        token: UUID,
        pattern: VibrationPattern,
        strength: Double,
        index: Int,
        delay: Double,
        systemFallback: Bool
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning, self.vibrationToken == token else { return }
            self.playPulse(pattern: pattern, strength: strength, index: index, systemFallback: systemFallback)

            let delays = pattern.pulseDelays
            let nextIndex = (index + 1) % delays.count
            self.scheduleNextPulse(
                token: token,
                pattern: pattern,
                strength: strength,
                index: nextIndex,
                delay: delays[index],
                systemFallback: systemFallback
            )
        }
    }

    private func playPulse(pattern: VibrationPattern, strength: Double, index: Int, systemFallback: Bool) {
        if systemFallback {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        playCoreHaptic(strength: strength, duration: pulseDuration(for: pattern, index: index))
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if hapticEngine != nil { return }

        do {
            let engine = try CHHapticEngine()
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.hapticEngine = nil }
            }
            hapticEngine = engine
            try engine.start()
        } catch {
            hapticEngine = nil
        }
    }

    private func playCoreHaptic(strength: Double, duration: Double) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if hapticEngine == nil { prepareHaptics() }
            try hapticEngine?.start()

            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(max(strength, 0.1), 1))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(0.35 + min(max(strength, 0.1), 1) * 0.55))
                ],
                relativeTime: 0,
                duration: duration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func playPreviewSequence(pattern: VibrationPattern, strength: Double) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if hapticEngine == nil { prepareHaptics() }
            try hapticEngine?.start()

            var relativeTime = 0.0
            var events: [CHHapticEvent] = []
            for index in pattern.pulseDelays.indices {
                let duration = pulseDuration(for: pattern, index: index)
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(max(strength, 0.1), 1))),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(0.35 + min(max(strength, 0.1), 1) * 0.55))
                        ],
                        relativeTime: relativeTime,
                        duration: duration
                    )
                )
                relativeTime += pattern.pulseDelays[index]
            }

            let hapticPattern = try CHHapticPattern(events: events, parameters: [])
            let player = try hapticEngine?.makePlayer(with: hapticPattern)
            try player?.start(atTime: 0)
        } catch {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func pulseDuration(for pattern: VibrationPattern, index: Int) -> Double {
        switch pattern {
        case .alert:
            return 0.42
        case .heartbeat:
            return index.isMultiple(of: 2) ? 0.11 : 0.18
        case .quick:
            return 0.13
        case .rapid:
            return 0.08
        case .sos:
            return index >= 3 ? 0.34 : 0.11
        case .staccato:
            return 0.06
        case .symphony:
            return [0.12, 0.28, 0.16, 0.38][index % 4]
        }
    }
}
