import ActivityKit
import Foundation

@MainActor
enum WakeHardLiveActivityManager {
    // Until the WidgetKit extension is signed and embedded, starting an activity
    // creates a blank Dynamic Island shell. Keep the hooks in place, but do not
    // present that half-state in installed builds.
    private static let isDisplayExtensionEmbedded = true

    static func startRinging(alarm: Alarm) {
        guard AppSettings.liveActivityRinging else {
            Task { await endSnooze() }
            return
        }
        startActivity(alarm: alarm, mode: .ringing, fireDate: nil, remainingSnoozes: nil)
    }

    static func startSnooze(alarm: Alarm, fireDate: Date, remainingSnoozes: Int?) {
        guard AppSettings.liveActivitySnooze else {
            Task { await endSnooze() }
            return
        }
        startActivity(alarm: alarm, mode: .snoozed, fireDate: fireDate, remainingSnoozes: remainingSnoozes)
    }

    static func startSkippedOnce(alarm: Alarm, fireDate: Date) {
        guard AppSettings.liveActivitySkippedOnce else {
            if AppSettings.liveActivityNextAlarm {
                startNextAlarm(alarm: alarm, fireDate: fireDate)
            } else {
                Task { await endSnooze() }
            }
            return
        }
        startActivity(alarm: alarm, mode: .skippedOnce, fireDate: fireDate, remainingSnoozes: nil)
    }

    static func startNextAlarm(alarm: Alarm, fireDate: Date) {
        guard AppSettings.liveActivityNextAlarm else {
            Task { await endSnooze() }
            return
        }
        startActivity(alarm: alarm, mode: .nextAlarm, fireDate: fireDate, remainingSnoozes: nil)
    }

    static func showUpcomingAlarm(from alarms: [Alarm]) {
        guard
            let next = alarms
                .filter(\.isEnabled)
                .compactMap({ alarm -> (Alarm, Date)? in
                    guard let fireDate = alarm.nextFireDate else { return nil }
                    return (alarm, fireDate)
                })
                .sorted(by: { $0.1 < $1.1 })
                .first
        else {
            Task { await endSnooze() }
            return
        }

        if next.0.skippedFireDate != nil {
            startSkippedOnce(alarm: next.0, fireDate: next.1)
        } else {
            startNextAlarm(alarm: next.0, fireDate: next.1)
        }
    }

    static func endSnooze() async {
        for activity in Activity<WakeHardSnoozeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func startActivity(
        alarm: Alarm,
        mode: WakeHardLiveActivityMode,
        fireDate: Date?,
        remainingSnoozes: Int?
    ) {
        guard isDisplayExtensionEmbedded else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            await endSnooze()

            let attributes = WakeHardSnoozeAttributes(
                alarmID: alarm.id.uuidString,
                alarmLabel: alarm.label.isEmpty ? "WakeHard" : alarm.label
            )
            let state = WakeHardSnoozeAttributes.ContentState(
                mode: mode,
                fireDate: fireDate,
                remainingSnoozes: remainingSnoozes
            )

            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: fireDate),
                    pushType: nil
                )
            } catch {
                print("Unable to start WakeHard Live Activity: \(error)")
            }
        }
    }
}
