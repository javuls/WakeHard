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
                Image(systemName: iconName(for: context.state.mode))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(accentColor(for: context.state.mode))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: context.state.mode))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(context.attributes.alarmLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    timeView(for: context.state)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(detail(for: context.state))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(accentColor(for: context.state.mode))
            .widgetURL(widgetURL(for: context.state.mode))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(title(for: context.state.mode), systemImage: iconName(for: context.state.mode))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor(for: context.state.mode))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    timeView(for: context.state)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.alarmLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(detail(for: context.state))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: iconName(for: context.state.mode))
                    .foregroundStyle(accentColor(for: context.state.mode))
            } compactTrailing: {
                compactTimeView(for: context.state)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: iconName(for: context.state.mode))
                    .foregroundStyle(accentColor(for: context.state.mode))
            }
            .widgetURL(widgetURL(for: context.state.mode))
            .keylineTint(accentColor(for: context.state.mode))
        }
    }

    @ViewBuilder
    private func timeView(for state: WakeHardSnoozeAttributes.ContentState) -> some View {
        if state.mode == .ringing {
            Text("Now")
        } else if let fireDate = state.fireDate {
            Text(fireDate, style: .timer)
        } else {
            Text("--")
        }
    }

    @ViewBuilder
    private func compactTimeView(for state: WakeHardSnoozeAttributes.ContentState) -> some View {
        if state.mode == .ringing {
            Text("Now")
        } else if let fireDate = state.fireDate {
            Text(fireDate, style: .timer)
        } else {
            Text("--")
        }
    }

    private func iconName(for mode: WakeHardLiveActivityMode) -> String {
        switch mode {
        case .ringing: return "alarm.waves.left.and.right.fill"
        case .snoozed: return "zzz"
        case .skippedOnce: return "arrow.uturn.forward.circle.fill"
        case .nextAlarm: return "alarm.fill"
        }
    }

    private func title(for mode: WakeHardLiveActivityMode) -> String {
        switch mode {
        case .ringing: return "Ringing"
        case .snoozed: return "Snoozed"
        case .skippedOnce: return "Skipped once"
        case .nextAlarm: return "Next alarm"
        }
    }

    private func detail(for state: WakeHardSnoozeAttributes.ContentState) -> String {
        switch state.mode {
        case .ringing:
            return "Tap to dismiss or snooze"
        case .snoozed:
            return snoozeText(state.remainingSnoozes)
        case .skippedOnce:
            return "Back on after this ring"
        case .nextAlarm:
            return "Armed and ready"
        }
    }

    private func accentColor(for mode: WakeHardLiveActivityMode) -> Color {
        switch mode {
        case .ringing: return .green
        case .snoozed: return .cyan
        case .skippedOnce: return .orange
        case .nextAlarm: return .green
        }
    }

    private func widgetURL(for mode: WakeHardLiveActivityMode) -> URL? {
        switch mode {
        case .ringing: return URL(string: "wakehard://ringing")
        case .snoozed: return URL(string: "wakehard://snooze")
        case .skippedOnce, .nextAlarm: return URL(string: "wakehard://alarms")
        }
    }

    private func snoozeText(_ remaining: Int?) -> String {
        guard let remaining else { return "Unlimited snoozes" }
        return "\(remaining) left"
    }
}
