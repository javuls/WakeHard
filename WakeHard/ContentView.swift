import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var soundManager: SoundManager
    @ObservedObject private var backgroundEngine = BackgroundAlarmEngine.shared
    @State private var editingAlarm: Alarm?
    @State private var isAddingAlarm = false
    @State private var ringingAlarm: Alarm?
    @State private var snoozeState: SnoozeState?
    @State private var activeSnooze: ActiveSnooze?
    @State private var snoozeTask: Task<Void, Never>?
    @State private var saveToast: AlarmSaveToast?
    @State private var saveToastTask: Task<Void, Never>?
    @State private var dismissGreeting: DismissGreeting?
    @State private var dismissGreetingTask: Task<Void, Never>?

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

                if let saveToast {
                    VStack {
                        Spacer()
                        AlarmSaveToastView(message: saveToast.message)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                }

                if let dismissGreeting {
                    DismissGreetingView(message: dismissGreeting.message)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(3)
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
                AlarmEditorView(alarm: Alarm()) { alarm in
                    alarmStore.add(alarm)
                    showAlarmSavedToast(for: alarm)
                }
            }
            .sheet(item: $editingAlarm) { alarm in
                AlarmEditorView(alarm: alarm) { updatedAlarm in
                    alarmStore.update(updatedAlarm)
                    showAlarmSavedToast(for: updatedAlarm)
                }
            }
            .fullScreenCover(item: $ringingAlarm) { alarm in
                AlarmRingingView(
                    alarm: alarm,
                    onDismiss: {
                        dismissRingingAlarm(alarm)
                    },
                    remainingSnoozes: remainingSnoozes(for: alarm),
                    onSnooze: {
                        startSnooze(for: alarm)
                    }
                )
            }
            .fullScreenCover(item: $snoozeState) { state in
                SnoozeIdleView(state: state) {
                    dismissSnooze(for: state.alarm)
                }
                    .interactiveDismissDisabled(true)
            }
            .onAppear {
                restoreActiveAlarmState()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                restoreActiveAlarmState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .alarmNotificationOpened)) { notification in
                presentAlarmFromNotification(notification.object)
            }
            .onReceive(NotificationCenter.default.publisher(for: .alarmNotificationPresented)) { notification in
                presentAlarmFromNotification(notification.object)
            }
            .onReceive(NotificationCenter.default.publisher(for: .backgroundAlarmFired)) { notification in
                if let alarm = notification.object as? Alarm {
                    cancelSnoozeState(for: alarm)
                    presentRingingAlarm(alarm)
                } else {
                    ringingAlarm = notification.object as? Alarm
                }
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

    private func remainingSnoozes(for alarm: Alarm) -> SnoozeRemaining {
        guard alarm.snoozeEnabled else { return .none }
        guard let maxCount = alarm.snoozeCount.maxCount else { return .unlimited }
        let remaining = activeSnooze?.alarmID == alarm.id ? activeSnooze?.remaining ?? maxCount : maxCount
        return .limited(max(0, remaining))
    }

    private func startSnooze(for alarm: Alarm) {
        let remaining = remainingSnoozes(for: alarm)
        guard remaining.canSnooze else { return }

        let nextRemaining: Int?
        switch remaining {
        case .unlimited:
            nextRemaining = nil
        case .limited(let count):
            nextRemaining = max(0, count - 1)
        case .none:
            return
        }

        soundManager.stop()
        VibrationManager.shared.stop()
        clearRingingAlarm()
        ringingAlarm = nil

        let fireDate = Date().addingTimeInterval(alarm.snoozeInterval.duration)
        let state = SnoozeState(
            alarm: alarm,
            fireDate: fireDate,
            remainingSnoozes: nextRemaining
        )
        activeSnooze = ActiveSnooze(alarmID: alarm.id, remaining: nextRemaining)
        snoozeState = state
        persistSnooze(state)
        WakeHardLiveActivityManager.startSnooze(
            alarm: alarm,
            fireDate: fireDate,
            remainingSnoozes: nextRemaining
        )
        NotificationScheduler.shared.scheduleSnooze(
            alarm: alarm,
            fireDate: fireDate,
            remainingSnoozes: nextRemaining,
            showStatusNotification: true
        )

        scheduleSnoozeTask(for: state)
    }

    private func scheduleSnoozeTask(for state: SnoozeState) {
        snoozeTask?.cancel()
        snoozeTask = Task { @MainActor in
            let nanoseconds = UInt64(max(0, state.fireDate.timeIntervalSinceNow) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            ringAfterSnooze(for: state.alarm, clearNotification: false)
        }
    }

    private func cancelSnoozeState(for alarm: Alarm) {
        guard activeSnooze?.alarmID == alarm.id || snoozeState?.alarm.id == alarm.id else { return }
        snoozeTask?.cancel()
        snoozeTask = nil
        snoozeState = nil
        activeSnooze = nil
        clearPersistedSnooze()
        NotificationScheduler.shared.cancelSnooze(for: alarm)
        Task { await WakeHardLiveActivityManager.endSnooze() }
    }

    private func presentAlarmFromNotification(_ object: Any?) {
        guard let event = object as? AlarmNotificationEvent else {
            ringingAlarm = nextAlarm ?? alarmStore.alarms.first
            return
        }

        guard
            let id = event.alarmID,
            let alarm = alarmStore.alarms.first(where: { $0.id == id })
        else {
            ringingAlarm = nextAlarm ?? alarmStore.alarms.first
            return
        }

        switch event.kind {
        case .snoozeRing:
            ringAfterSnooze(for: alarm, clearNotification: true)
        case .snoozeStatus, .alarm:
            if showPendingSnoozeIfNeeded(for: alarm) {
                return
            }
            presentRingingAlarm(alarm)
        }
    }

    private func ringAfterSnooze(for alarm: Alarm, clearNotification: Bool) {
        snoozeTask?.cancel()
        snoozeTask = nil
        snoozeState = nil
        clearPersistedSnooze()
        if clearNotification {
            NotificationScheduler.shared.cancelSnooze(for: alarm)
        }
        Task { await WakeHardLiveActivityManager.endSnooze() }
        presentRingingAlarm(alarm)
    }

    private func showPendingSnoozeIfNeeded(for alarm: Alarm) -> Bool {
        guard let state = pendingSnoozeState(for: alarm), state.fireDate > .now else { return false }
        activeSnooze = ActiveSnooze(alarmID: alarm.id, remaining: state.remainingSnoozes)
        ringingAlarm = nil
        snoozeState = state
        scheduleSnoozeTask(for: state)
        return true
    }

    private func dismissSnooze(for alarm: Alarm) {
        cancelSnoozeState(for: alarm)
        if alarm.weekdays.isEmpty {
            alarmStore.toggle(alarm, isEnabled: false)
        }
        backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)
        showDismissGreeting(after: 300_000_000)
    }

    private func presentRingingAlarm(_ alarm: Alarm) {
        AlarmRuntimeStore.setRingingAlarm(alarm.id)
        WakeHardLiveActivityManager.startRinging(alarm: alarm)
        ringingAlarm = alarm
    }

    private func clearRingingAlarm() {
        AlarmRuntimeStore.clearRingingAlarm()
    }

    private func persistSnooze(_ state: SnoozeState) {
        let persisted = PersistedSnoozeState(
            alarmID: state.alarm.id,
            fireDate: state.fireDate,
            remainingSnoozes: state.remainingSnoozes
        )
        AlarmRuntimeStore.persistSnooze(persisted)
    }

    private func clearPersistedSnooze() {
        AlarmRuntimeStore.clearSnooze()
    }

    private func pendingSnoozeState(for alarm: Alarm) -> SnoozeState? {
        if let snoozeState, snoozeState.alarm.id == alarm.id {
            return snoozeState
        }

        guard
            let persisted = AlarmRuntimeStore.activeSnooze(),
            persisted.alarmID == alarm.id
        else { return nil }

        return SnoozeState(
            alarm: alarm,
            fireDate: persisted.fireDate,
            remainingSnoozes: persisted.remainingSnoozes
        )
    }

    private func restoreActiveAlarmState() {
        restoreRingingIfNeeded()
        restoreSnoozeIfNeeded()
    }

    private func restoreRingingIfNeeded() {
        guard ringingAlarm == nil else { return }
        guard
            let ringingID = AlarmRuntimeStore.ringingAlarmID(),
            let alarm = alarmStore.alarms.first(where: { $0.id == ringingID })
        else {
            clearRingingAlarm()
            return
        }
        ringingAlarm = alarm
    }

    private func restoreSnoozeIfNeeded() {
        guard snoozeState == nil, ringingAlarm == nil else { return }
        guard
            let persisted = AlarmRuntimeStore.activeSnooze(),
            let alarm = alarmStore.alarms.first(where: { $0.id == persisted.alarmID })
        else {
            clearPersistedSnooze()
            return
        }

        activeSnooze = ActiveSnooze(alarmID: alarm.id, remaining: persisted.remainingSnoozes)

        if persisted.fireDate <= .now {
            ringAfterSnooze(for: alarm, clearNotification: false)
            return
        }

        let state = SnoozeState(
            alarm: alarm,
            fireDate: persisted.fireDate,
            remainingSnoozes: persisted.remainingSnoozes
        )
        snoozeState = state
        WakeHardLiveActivityManager.startSnooze(
            alarm: alarm,
            fireDate: persisted.fireDate,
            remainingSnoozes: persisted.remainingSnoozes
        )
        NotificationScheduler.shared.scheduleSnooze(
            alarm: alarm,
            fireDate: persisted.fireDate,
            remainingSnoozes: persisted.remainingSnoozes
        )
        scheduleSnoozeTask(for: state)
    }

    private func dismissRingingAlarm(_ alarm: Alarm) {
        cancelSnoozeState(for: alarm)
        NotificationScheduler.shared.cancelSnooze(for: alarm)
        ringingAlarm = nil
        clearRingingAlarm()
        soundManager.stop()
        VibrationManager.shared.stop()
        Task { await WakeHardLiveActivityManager.endSnooze() }
        if alarm.weekdays.isEmpty {
            alarmStore.toggle(alarm, isEnabled: false)
        }
        backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)
        showDismissGreeting(after: 300_000_000)
    }

    private func showAlarmSavedToast(for alarm: Alarm) {
        saveToastTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            saveToast = AlarmSaveToast(message: savedToastMessage(for: alarm))
        }
        saveToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                saveToast = nil
            }
        }
    }

    private func savedToastMessage(for alarm: Alarm) -> String {
        guard let fireDate = alarm.nextFireDate else {
            return "Alarm saved"
        }
        return "Alarm will ring in \(durationText(until: fireDate))"
    }

    private func durationText(until fireDate: Date) -> String {
        let totalMinutes = max(0, Int(ceil(fireDate.timeIntervalSinceNow / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)hr \(minutes)min"
        }
        return "\(minutes)min"
    }

    private func showDismissGreeting(after delay: UInt64 = 0) {
        dismissGreetingTask?.cancel()
        dismissGreetingTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }

            let hour = Calendar.current.component(.hour, from: .now)
            let message: String
            if hour < 12 {
                message = "Good morning"
            } else if hour < 18 {
                message = "Good afternoon"
            } else {
                message = "Good evening"
            }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                dismissGreeting = DismissGreeting(message: message)
            }
            try? await Task.sleep(nanoseconds: 1_450_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                dismissGreeting = nil
            }
        }
    }
}

private struct AlarmSaveToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct DismissGreeting: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct AlarmSaveToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
}

private struct DismissGreetingView: View {
    let message: String
    @State private var didAppear = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.16))
                        .frame(width: 92, height: 92)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .scaleEffect(didAppear ? 1 : 0.78)
                }

                VStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.primary)
                        .multilineTextAlignment(.center)
                    Text("Alarm dismissed")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                }
                .opacity(didAppear ? 1 : 0)
                .offset(y: didAppear ? 0 : 8)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                didAppear = true
            }
        }
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
    let onDismiss: () -> Void
    let remainingSnoozes: SnoozeRemaining
    let onSnooze: () -> Void
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

                // Snooze button
                if alarm.snoozeEnabled, remainingSnoozes.canSnooze {
                    Button {
                        onSnooze()
                    } label: {
                        HStack {
                            Image(systemName: "zzz")
                            Text("Snooze \(alarm.snoozeInterval.title)")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.horizontal, 24)
                }
            }
            .padding(24)
        }
        .onAppear {
            // Let BackgroundAlarmEngine own playback continuously from the
            // moment the alarm fires through dismiss/snooze. Calling fire()
            // here is idempotent — it does nothing if the engine is already
            // ringing this alarm. This avoids a handoff to SoundManager that
            // was causing audio to stop when the user switched apps.
            BackgroundAlarmEngine.shared.fire(alarm: alarm)
            VibrationManager.shared.start(alarm: alarm)
        }
    }

    @ViewBuilder
    private var challengeControl: some View {
        switch alarm.challenge {
        case .none:
            Button("Dismiss", action: onDismiss)
                .buttonStyle(PrimaryButtonStyle())
        case .tapHold:
            Button {
                holdProgress += 0.34
                if holdProgress >= 1 { onDismiss() }
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
                if tapCount >= 12 { onDismiss() }
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

private struct SnoozeState: Identifiable, Equatable {
    let id = UUID()
    let alarm: Alarm
    let fireDate: Date
    let remainingSnoozes: Int?
}

private struct ActiveSnooze: Equatable {
    let alarmID: UUID
    let remaining: Int?
}

private enum SnoozeRemaining: Equatable {
    case none
    case unlimited
    case limited(Int)

    var canSnooze: Bool {
        switch self {
        case .none:
            return false
        case .unlimited:
            return true
        case .limited(let count):
            return count > 0
        }
    }

    var displayText: String {
        switch self {
        case .none:
            return "Snooze off"
        case .unlimited:
            return "Unlimited snoozes left"
        case .limited(let count):
            return "\(count) snooze\(count == 1 ? "" : "s") left"
        }
    }
}

private struct SnoozeIdleView: View {
    let state: SnoozeState
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 28) {
                    Spacer()

                    Image(systemName: "zzz")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 82, height: 82)
                        .background(AppTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(spacing: 10) {
                        Text("Snoozed")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primary)
                        Text(timeRemainingText(at: context.date))
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("until \(state.alarm.label) rings again")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Text(snoozeCountText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(AppTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button("Dismiss alarm", action: onDismiss)
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.horizontal, 24)
                        .padding(.top, 6)

                    Spacer()

                    VStack(spacing: 8) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.muted)
                        Text("Swipe up to leave WakeHard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)
                    }
                    .padding(.bottom, 18)
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var snoozeCountText: String {
        guard let remaining = state.remainingSnoozes else {
            return "Unlimited snoozes left"
        }
        return "\(remaining) snooze\(remaining == 1 ? "" : "s") left"
    }

    private func timeRemainingText(at date: Date) -> String {
        let seconds = max(0, Int(ceil(state.fireDate.timeIntervalSince(date))))
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }
}
