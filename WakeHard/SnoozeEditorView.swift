import SwiftUI

struct SnoozeEditorView: View {
    @Binding var alarm: Alarm

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Snooze Toggle
                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Enable Snooze")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppTheme.primary)
                                        Text("Automatically snooze when you dismiss the alarm")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundStyle(AppTheme.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $alarm.snoozeEnabled)
                                        .labelsHidden()
                                        .tint(AppTheme.accent)
                                }
                                .padding(16)
                                .background(AppTheme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            // Snooze Interval (only if enabled)
                            if alarm.snoozeEnabled {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Snooze Interval")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)

                                    VStack(spacing: 8) {
                                        ForEach(SnoozeInterval.allCases, id: \.self) { interval in
                                            IntervalButton(
                                                title: interval.title,
                                                isSelected: alarm.snoozeInterval == interval,
                                                action: { alarm.snoozeInterval = interval }
                                            )
                                        }
                                    }
                                    .padding(12)
                                    .background(AppTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            // Snooze Count (only if enabled)
                            if alarm.snoozeEnabled {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Maximum Snoozes")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)

                                    VStack(spacing: 8) {
                                        // Unlimited option
                                        CountButton(
                                            title: "Unlimited",
                                            isSelected: alarm.snoozeCount == .unlimited,
                                            action: { alarm.snoozeCount = .unlimited }
                                        )

                                        // 1-10 times options
                                        ForEach(1...10, id: \.self) { count in
                                            CountButton(
                                                title: "\(count) time\(count == 1 ? "" : "s")",
                                                isSelected: {
                                                    if case .times(let selectedCount) = alarm.snoozeCount {
                                                        return selectedCount == count
                                                    }
                                                    return false
                                                }(),
                                                action: { alarm.snoozeCount = .times(count) }
                                            )
                                        }
                                    }
                                    .padding(12)
                                    .background(AppTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            // Info section
                            if alarm.snoozeEnabled {
                                VStack(spacing: 8) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppTheme.accent)
                                            .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("How Snooze Works")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(AppTheme.primary)
                                            Text("When the alarm rings and you dismiss it, it will automatically ring again after the selected interval. This repeats until you've snoozed the maximum number of times.")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundStyle(AppTheme.secondary)
                                                .lineLimit(10)
                                        }
                                    }
                                    .padding(12)
                                    .background(AppTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            Spacer()
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Snooze Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Helper Components

private struct IntervalButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CountButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SnoozeEditorPreviewHost: View {
    @State private var alarm = Alarm()

    var body: some View {
        SnoozeEditorView(alarm: $alarm)
    }
}

#Preview {
    SnoozeEditorPreviewHost()
}
