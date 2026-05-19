import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var soundManager: SoundManager
    @ObservedObject private var backgroundEngine = BackgroundAlarmEngine.shared
    @State private var editingAlarm: Alarm?
    @State private var isAddingAlarm = false
    @State private var ringingAlarm: Alarm?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    HeaderView(nextAlarm: nextAlarm) {
                        guard let nextAlarm else { return }
                        editingAlarm = nextAlarm
                    }
                    List {
                        ForEach(alarmStore.alarms) { alarm in
                            AlarmRow(alarm: alarm)
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { editingAlarm = alarm }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let index = alarmStore.alarms.firstIndex(where: { $0.id == alarm.id }) {
                                            alarmStore.delete(at: IndexSet(integer: index))
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("WakeHard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Add alarm")
                }
            }
            .sheet(isPresented: $isAddingAlarm) {
                AlarmEditorView(alarm: Alarm()) { alarmStore.add($0) }
            }
            .sheet(item: $editingAlarm) { alarm in
                AlarmEditorView(alarm: alarm) { alarmStore.update($0) }
            }
            .fullScreenCover(item: $ringingAlarm) { alarm in
                AlarmRingingView(alarm: alarm) {
                    ringingAlarm = nil
                    soundManager.stop()
                    VibrationManager.shared.stop()
                    if alarm.weekdays.isEmpty {
                        alarmStore.toggle(alarm, isEnabled: false)
                    }
                    backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .alarmNotificationOpened)) { _ in
                ringingAlarm = nextAlarm ?? alarmStore.alarms.first
            }
            .onReceive(NotificationCenter.default.publisher(for: .backgroundAlarmFired)) { notification in
                ringingAlarm = notification.object as? Alarm
            }
        }
        .preferredColorScheme(.dark)
    }

    private var nextAlarm: Alarm? {
        alarmStore.alarms
            .filter(\.isEnabled)
            .sorted { ($0.nextFireDate ?? .distantFuture) < ($1.nextFireDate ?? .distantFuture) }
            .first
    }
}

private struct HeaderView: View {
    let nextAlarm: Alarm?
    let editNextAlarm: () -> Void

    var body: some View {
        Button {
            editNextAlarm()
        } label: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 12) {
                    Text(countdownText(at: context.date))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(nextAlarm == nil ? AppTheme.secondary : AppTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    if nextAlarm != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(nextAlarm == nil)
        .padding(18)
        .background(AppTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func countdownText(at date: Date) -> String {
        guard let fireDate = nextAlarm?.nextFireDate else {
            return "No active alarms"
        }

        let totalMinutes = max(0, Int(ceil(fireDate.timeIntervalSince(date) / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "Ring in \(hours)hr \(minutes)min"
        }
        return "Ring in \(minutes)min"
    }
}

private struct AlarmRow: View {
    @EnvironmentObject private var alarmStore: AlarmStore
    let alarm: Alarm

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(alarm.formattedTime)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(alarm.isEnabled ? AppTheme.primary : AppTheme.disabled)
                    Text(alarm.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    Label(alarm.repeatSummary, systemImage: "repeat")
                    Label(alarm.soundTitle, systemImage: "speaker.wave.2")
                    Label("\(Int(alarm.volume * 100))%", systemImage: "slider.horizontal.3")
                    if alarm.vibrateEnabled {
                        Label(alarm.vibrationPattern.title, systemImage: "iphone.radiowaves.left.and.right")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { alarmStore.toggle(alarm, isEnabled: $0) }
            ))
            .labelsHidden()
            .tint(AppTheme.accent)
        }
        .padding(15)
        .frame(minHeight: 86)
        .background(AppTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AlarmRingingView: View {
    @EnvironmentObject private var soundManager: SoundManager
    let alarm: Alarm
    let dismiss: () -> Void
    @State private var holdProgress = 0.0
    @State private var tapCount = 0

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                VStack(spacing: 8) {
                    Text(alarm.formattedTime)
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(alarm.label)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                }

                challengeControl
                    .padding(.top, 14)

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            soundManager.play(alarm: alarm, loops: true)
            VibrationManager.shared.start(alarm: alarm)
        }
    }

    @ViewBuilder
    private var challengeControl: some View {
        switch alarm.challenge {
        case .none:
            Button("Dismiss", action: dismiss)
                .buttonStyle(PrimaryButtonStyle())
        case .tapHold:
            Button {
                holdProgress += 0.34
                if holdProgress >= 1 { dismiss() }
            } label: {
                HStack {
                    Image(systemName: "hand.tap.fill")
                    Text(holdProgress >= 0.67 ? "One more tap" : "Tap three times")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        case .focusTaps:
            Button {
                tapCount += 1
                if tapCount >= 12 { dismiss() }
            } label: {
                HStack {
                    Image(systemName: "target")
                    Text("\(max(0, 12 - tapCount)) taps left")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}
