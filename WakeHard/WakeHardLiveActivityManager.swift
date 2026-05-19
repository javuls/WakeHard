import ActivityKit
import Foundation

@MainActor
enum WakeHardLiveActivityManager {
    // Until the WidgetKit extension is signed and embedded, starting an activity
    // creates a blank Dynamic Island shell. Keep the hooks in place, but do not
    // present that half-state in installed builds.
    private static let isDisplayExtensionEmbedded = true

    static func startRinging(alarm: Alarm) {
        guard isDisplayExtensionEmbedded else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            await endSnooze()

            let attributes = WakeHardSnoozeAttributes(
                alarmID: alarm.id.uuidString,
                alarmLabel: alarm.label.isEmpty ? "WakeHard" : alarm.label
            )
            let state = WakeHardSnoozeAttributes.ContentState(
                mode: .ringing,
                fireDate: nil,
                remainingSnoozes: nil
            )

            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                print("Unable to start ringing Live Activity: \(error)")
            }
        }
    }

    static func startSnooze(alarm: Alarm, fireDate: Date, remainingSnoozes: Int?) {
        guard isDisplayExtensionEmbedded else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            await endSnooze()

            let attributes = WakeHardSnoozeAttributes(
                alarmID: alarm.id.uuidString,
                alarmLabel: alarm.label.isEmpty ? "WakeHard" : alarm.label
            )
            let state = WakeHardSnoozeAttributes.ContentState(
                mode: .snoozed,
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
                print("Unable to start snooze Live Activity: \(error)")
            }
        }
    }

    static func endSnooze() async {
        for activity in Activity<WakeHardSnoozeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
