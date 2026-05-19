import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WakeHardLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WakeHardSnoozeLiveActivity()
    }
}

struct WakeHardSnoozeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WakeHardSnoozeAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.mode == .ringing ? "alarm.waves.left.and.right.fill" : "alarm.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.mode == .ringing ? "Ringing" : "Snoozed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(context.attributes.alarmLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if context.state.mode == .ringing {
                        Text("Now")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tap to open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    } else if let fireDate = context.state.fireDate {
                        Text(fireDate, style: .timer)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(snoozeText(context.state.remainingSnoozes))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.green)
            .widgetURL(URL(string: context.state.mode == .ringing ? "wakehard://ringing" : "wakehard://snooze"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.state.mode == .ringing ? "Ringing" : "WakeHard",
                        systemImage: context.state.mode == .ringing ? "alarm.waves.left.and.right.fill" : "alarm.fill"
                    )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.mode == .ringing {
                        Text("Now")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    } else if let fireDate = context.state.fireDate {
                        Text(fireDate, style: .timer)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.alarmLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(context.state.mode == .ringing ? "Tap to dismiss or snooze" : snoozeText(context.state.remainingSnoozes))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.mode == .ringing ? "alarm.waves.left.and.right.fill" : "alarm.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                if context.state.mode == .ringing {
                    Text("Now")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else if let fireDate = context.state.fireDate {
                    Text(fireDate, style: .timer)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } minimal: {
                Image(systemName: context.state.mode == .ringing ? "alarm.waves.left.and.right.fill" : "alarm.fill")
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: context.state.mode == .ringing ? "wakehard://ringing" : "wakehard://snooze"))
            .keylineTint(.green)
        }
    }

    private func snoozeText(_ remaining: Int?) -> String {
        guard let remaining else { return "Unlimited snoozes" }
        return "\(remaining) left"
    }
}
