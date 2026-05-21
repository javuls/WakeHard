import SwiftUI

enum AppSettings {
    enum Keys {
        static let liveActivityRinging = "wakehard.settings.liveActivityRinging"
        static let liveActivitySnooze = "wakehard.settings.liveActivitySnooze"
        static let liveActivitySkippedOnce = "wakehard.settings.liveActivitySkippedOnce"
        static let liveActivityNextAlarm = "wakehard.settings.liveActivityNextAlarm"
        static let failSafeBackupSound = "wakehard.settings.failSafeBackupSound"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.liveActivityRinging: true,
            Keys.liveActivitySnooze: true,
            Keys.liveActivitySkippedOnce: true,
            Keys.liveActivityNextAlarm: true,
            Keys.failSafeBackupSound: true
        ])
    }

    static var liveActivityRinging: Bool {
        UserDefaults.standard.object(forKey: Keys.liveActivityRinging) as? Bool ?? true
    }

    static var liveActivitySnooze: Bool {
        UserDefaults.standard.object(forKey: Keys.liveActivitySnooze) as? Bool ?? true
    }

    static var liveActivitySkippedOnce: Bool {
        UserDefaults.standard.object(forKey: Keys.liveActivitySkippedOnce) as? Bool ?? true
    }

    static var liveActivityNextAlarm: Bool {
        UserDefaults.standard.object(forKey: Keys.liveActivityNextAlarm) as? Bool ?? true
    }

    static var failSafeBackupSound: Bool {
        UserDefaults.standard.object(forKey: Keys.failSafeBackupSound) as? Bool ?? true
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var alarmStore: AlarmStore
    @EnvironmentObject private var soundManager: SoundManager
    @ObservedObject private var backgroundEngine = BackgroundAlarmEngine.shared
    @State private var editingAlarm: Alarm?
    @State private var isAddingAlarm = false
    @State private var previewAlarm: Alarm?
    @State private var ringingAlarm: Alarm?
    @State private var snoozeState: SnoozeState?
    @State private var activeSnooze: ActiveSnooze?
    @State private var snoozeTask: Task<Void, Never>?
    @State private var saveToast: AlarmSaveToast?
    @State private var saveToastTask: Task<Void, Never>?
    @State private var dismissGreeting: DismissGreeting?
    @State private var dismissGreetingTask: Task<Void, Never>?
    @State private var skipPrompt: SkipOncePrompt?
    @State private var isAddMenuOpen = false
    @State private var isShowingQuickAlarm = false
    @State private var isShowingSettings = false
    @State private var quickAlarmDeleteCandidate: Alarm?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    HeaderView(nextAlarm: nextAlarm) {
                        guard let nextAlarm else { return }
                        guard !nextAlarm.isQuickAlarm else { return }
                        editingAlarm = nextAlarm
                    }
                    List {
                        ForEach(alarmStore.alarms) { alarm in
                            AlarmRow(
                                alarm: alarm,
                                isShowingSkipPrompt: skipPrompt?.alarm.id == alarm.id,
                                onToggle: { handleAlarmToggle(alarm, isEnabled: $0) },
                                onSkipOnce: {
                                    alarmStore.skipOnce(alarm)
                                    refreshUpcomingLiveActivity()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                        skipPrompt = nil
                                    }
                                },
                                onTurnOff: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        skipPrompt = nil
                                    }
                                },
                                onDelete: {
                                    alarmStore.delete(alarm)
                                    refreshUpcomingLiveActivity()
                                },
                                onPreview: {
                                    previewAlarm = alarm
                                },
                                onDuplicate: {
                                    alarmStore.duplicate(alarm)
                                    refreshUpcomingLiveActivity()
                                },
                                onEdit: {
                                    guard !alarm.isQuickAlarm else { return }
                                    editingAlarm = alarm
                                }
                            )
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if alarm.isQuickAlarm {
                                            quickAlarmDeleteCandidate = alarm
                                            return
                                        }
                                        if let index = alarmStore.alarms.firstIndex(where: { $0.id == alarm.id }) {
                                            alarmStore.delete(at: IndexSet(integer: index))
                                            refreshUpcomingLiveActivity()
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }

                        Color.clear
                            .frame(height: 280)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
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

                FloatingAddMenuView(
                    isOpen: $isAddMenuOpen,
                    onQuickAlarm: {
                        isAddMenuOpen = false
                        isShowingQuickAlarm = true
                    },
                    onAlarm: {
                        isAddMenuOpen = false
                        isAddingAlarm = true
                    }
                )
                .zIndex(5)
            }
            .navigationTitle("WakeHard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isAddingAlarm) {
                AlarmEditorView(alarm: Alarm()) { alarm in
                    alarmStore.add(alarm)
                    showAlarmSavedToast(for: alarm)
                    refreshUpcomingLiveActivity()
                }
            }
            .sheet(isPresented: $isShowingQuickAlarm) {
                QuickAlarmEditorView { alarm in
                    alarmStore.add(alarm)
                    showAlarmSavedToast(for: alarm)
                    refreshUpcomingLiveActivity()
                }
                .presentationDetents([.height(660)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView {
                    NotificationScheduler.shared.rescheduleAll(alarms: alarmStore.alarms)
                    refreshUpcomingLiveActivity()
                }
            }
            .sheet(item: $editingAlarm) { alarm in
                AlarmEditorView(alarm: alarm) { updatedAlarm in
                    alarmStore.update(updatedAlarm)
                    showAlarmSavedToast(for: updatedAlarm)
                    refreshUpcomingLiveActivity()
                }
            }
            .alert("Delete quick alarm?", isPresented: isShowingQuickAlarmDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    quickAlarmDeleteCandidate = nil
                }
                Button("Delete", role: .destructive) {
                    if let alarm = quickAlarmDeleteCandidate {
                        alarmStore.delete(alarm)
                        refreshUpcomingLiveActivity()
                    }
                    quickAlarmDeleteCandidate = nil
                }
            } message: {
                Text("Quick alarms cannot be edited. Delete this quick alarm instead?")
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
            .fullScreenCover(item: $previewAlarm) { alarm in
                AlarmRingingView(
                    alarm: alarm,
                    isPreview: true,
                    onDismiss: {
                        dismissPreviewAlarm()
                    },
                    remainingSnoozes: .none,
                    onSnooze: {
                        dismissPreviewAlarm()
                    }
                )
                .interactiveDismissDisabled(true)
            }
            .fullScreenCover(item: $snoozeState) { state in
                SnoozeIdleView(state: state) {
                    dismissSnooze(for: state.alarm)
                }
                    .interactiveDismissDisabled(true)
            }
            .onAppear {
                restoreActiveAlarmState()
                if ringingAlarm == nil, snoozeState == nil {
                    refreshUpcomingLiveActivity()
                }
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
                    if showPendingSnoozeIfNeeded(for: alarm) {
                        backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)
                        return
                    }
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

    private var isShowingQuickAlarmDeleteAlert: Binding<Bool> {
        Binding(
            get: { quickAlarmDeleteCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    quickAlarmDeleteCandidate = nil
                }
            }
        )
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
        backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)

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
        clearRingingAlarm()
        snoozeState = state
        scheduleSnoozeTask(for: state)
        return true
    }

    private func dismissSnooze(for alarm: Alarm) {
        cancelSnoozeState(for: alarm)
        NotificationScheduler.shared.clearDeliveredAlarm(for: alarm)
        if alarm.isQuickAlarm {
            alarmStore.delete(alarm)
        } else if alarm.weekdays.isEmpty {
            alarmStore.toggle(alarm, isEnabled: false)
        }
        backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)
        refreshUpcomingLiveActivity()
        showDismissGreeting(after: 300_000_000)
    }

    private func presentRingingAlarm(_ alarm: Alarm) {
        AlarmRuntimeStore.setRingingAlarm(alarm.id)
        WakeHardLiveActivityManager.startRinging(alarm: alarm)
        if alarm.skippedFireDate != nil {
            alarmStore.clearSkip(for: alarm)
        }
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
        if restoreSnoozeIfNeeded() {
            return
        }
        restoreRingingIfNeeded()
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

    @discardableResult
    private func restoreSnoozeIfNeeded() -> Bool {
        guard snoozeState == nil else { return true }
        guard
            let persisted = AlarmRuntimeStore.activeSnooze(),
            let alarm = alarmStore.alarms.first(where: { $0.id == persisted.alarmID })
        else {
            clearPersistedSnooze()
            return false
        }

        activeSnooze = ActiveSnooze(alarmID: alarm.id, remaining: persisted.remainingSnoozes)
        clearRingingAlarm()
        ringingAlarm = nil

        if persisted.fireDate <= .now {
            ringAfterSnooze(for: alarm, clearNotification: false)
            return true
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
        return true
    }

    private func dismissRingingAlarm(_ alarm: Alarm) {
        cancelSnoozeState(for: alarm)
        NotificationScheduler.shared.cancelSnooze(for: alarm)
        NotificationScheduler.shared.clearDeliveredAlarm(for: alarm)
        ringingAlarm = nil
        clearRingingAlarm()
        soundManager.stop()
        VibrationManager.shared.stop()
        Task { await WakeHardLiveActivityManager.endSnooze() }
        if alarm.isQuickAlarm {
            alarmStore.delete(alarm)
        } else if alarm.weekdays.isEmpty {
            alarmStore.toggle(alarm, isEnabled: false)
        }
        backgroundEngine.stopAlarmAndRearm(alarms: alarmStore.alarms)
        refreshUpcomingLiveActivity()
        showDismissGreeting(after: 300_000_000)
    }

    private func dismissPreviewAlarm() {
        previewAlarm = nil
        soundManager.stop()
        VibrationManager.shared.stop()
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

    private func handleAlarmToggle(_ alarm: Alarm, isEnabled: Bool) {
        if isEnabled {
            alarmStore.toggle(alarm, isEnabled: true)
            refreshUpcomingLiveActivity()
            if skipPrompt?.alarm.id == alarm.id {
                skipPrompt = nil
            }
            return
        }

        if alarm.isQuickAlarm {
            quickAlarmDeleteCandidate = alarm
            return
        }

        alarmStore.toggle(alarm, isEnabled: false)
        refreshUpcomingLiveActivity()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            skipPrompt = SkipOncePrompt(alarm: alarm)
        }
    }

    private func refreshUpcomingLiveActivity() {
        WakeHardLiveActivityManager.showUpcomingAlarm(from: alarmStore.alarms)
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

private struct SkipOncePrompt: Identifiable, Equatable {
    let id = UUID()
    let alarm: Alarm
}

private struct DismissGreeting: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.Keys.liveActivityRinging) private var liveActivityRinging = true
    @AppStorage(AppSettings.Keys.liveActivitySnooze) private var liveActivitySnooze = true
    @AppStorage(AppSettings.Keys.liveActivitySkippedOnce) private var liveActivitySkippedOnce = true
    @AppStorage(AppSettings.Keys.liveActivityNextAlarm) private var liveActivityNextAlarm = true
    @AppStorage(AppSettings.Keys.failSafeBackupSound) private var failSafeBackupSound = true
    let onChange: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        SettingsSection(title: "Live Activities") {
                            SettingsToggleRow(
                                title: "Ringing",
                                subtitle: "Show the alarm state on the Lock Screen and Dynamic Island while it rings.",
                                isOn: $liveActivityRinging
                            )
                            SettingsToggleRow(
                                title: "Snooze countdown",
                                subtitle: "Show the time remaining until snooze rings again.",
                                isOn: $liveActivitySnooze
                            )
                            SettingsToggleRow(
                                title: "Skip once",
                                subtitle: "Show when an alarm has skipped its next ring.",
                                isOn: $liveActivitySkippedOnce
                            )
                            SettingsToggleRow(
                                title: "Next alarm countdown",
                                subtitle: "Keep a live countdown for the next scheduled alarm.",
                                isOn: $liveActivityNextAlarm
                            )
                        }

                        SettingsSection(title: "Audio Safety") {
                            SettingsToggleRow(
                                title: "Fail-safe backup sound",
                                subtitle: "Attach a backup tone to alarm notifications if app audio cannot run.",
                                isOn: $failSafeBackupSound
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: liveActivityRinging) { _, _ in onChange() }
            .onChange(of: liveActivitySnooze) { _, _ in onChange() }
            .onChange(of: liveActivitySkippedOnce) { _, _ in onChange() }
            .onChange(of: liveActivityNextAlarm) { _, _ in onChange() }
            .onChange(of: failSafeBackupSound) { _, _ in onChange() }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .textCase(.uppercase)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(AppTheme.accent)
    }
}

private struct FloatingAddMenuView: View {
    @Binding var isOpen: Bool
    let onQuickAlarm: () -> Void
    let onAlarm: () -> Void

    var body: some View {
        ZStack {
            if isOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            isOpen = false
                        }
                    }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 14) {
                        if isOpen {
                            VStack(spacing: 10) {
                                menuButton(title: "Quick alarm", systemImage: "bolt.fill", action: onQuickAlarm)
                                menuButton(title: "Alarm", systemImage: "alarm.fill", action: onAlarm)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                isOpen.toggle()
                            }
                        } label: {
                            Image(systemName: isOpen ? "xmark" : "plus")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.black)
                                .frame(width: 78, height: 78)
                                .background(AppTheme.accent)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isOpen ? "Close add menu" : "Add")
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func menuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.background)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(AppTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickAlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var durationMinutes = 5
    @State private var sound: AlarmSound = .pulse
    @State private var volume = 0.85
    @State private var vibrateEnabled = true
    let onSave: (Alarm) -> Void

    private let presets = [1, 5, 10, 15, 30, 60]

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Text("Quick alarm")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("+")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(AppTheme.primary)
                        Text("\(durationMinutes)")
                            .font(.system(size: 74, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primary)
                        Text(durationMinutes == 1 ? "min" : "min")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                    Text("Ring at \(ringTimeText)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppTheme.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            durationMinutes = minutes
                        } label: {
                            Text(presetTitle(minutes))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(AppTheme.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 74)
                                .background(durationMinutes == minutes ? AppTheme.accent.opacity(0.32) : AppTheme.panelSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 16) {
                    Picker("Sound", selection: $sound) {
                        ForEach(AlarmSound.allCases) { alarmSound in
                            Text(alarmSound.title).tag(alarmSound)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 14) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(AppTheme.primary)
                        Slider(value: $volume, in: 0.1...1)
                            .tint(AppTheme.accent)
                    }

                    Toggle("Vibrate", isOn: $vibrateEnabled)
                        .tint(AppTheme.accent)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                }

                Button {
                    onSave(makeAlarm())
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }

    private var ringDate: Date {
        Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    private var ringTimeText: String {
        ringDate.formatted(date: .omitted, time: .shortened)
    }

    private func presetTitle(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) hour" : "\(minutes) min"
    }

    private func makeAlarm() -> Alarm {
        let components = Calendar.current.dateComponents([.hour, .minute], from: ringDate)
        return Alarm(
            label: "Quick alarm",
            hour: components.hour ?? 7,
            minute: components.minute ?? 0,
            weekdays: [],
            sound: sound,
            volume: volume,
            vibrateEnabled: vibrateEnabled,
            isQuickAlarm: true,
            snoozeEnabled: false
        )
    }
}

private struct SkipOnceToastView: View {
    let title: String
    let onSkipOnce: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onSkipOnce) {
                HStack(spacing: 12) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onTurnOff) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.background.opacity(0.72))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Turn alarm off")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 58)
        .background(AppTheme.panelSecondary)
        .overlay(
            Capsule()
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }
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

                    if canOpenAlarm {
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
        .disabled(!canOpenAlarm)
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

    private var canOpenAlarm: Bool {
        nextAlarm?.isQuickAlarm == false
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
    let alarm: Alarm
    let isShowingSkipPrompt: Bool
    let onToggle: (Bool) -> Void
    let onSkipOnce: () -> Void
    let onTurnOff: () -> Void
    let onDelete: () -> Void
    let onPreview: () -> Void
    let onDuplicate: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                if alarm.isQuickAlarm {
                    Spacer(minLength: 0)
                } else {
                    weekdayStrip
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isVisuallyOn },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .tint(AppTheme.accent)
            }

            Text(alarm.formattedTime)
                .font(.system(size: 48, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isVisuallyOn ? AppTheme.primary : AppTheme.disabled)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if isShowingSkipPrompt {
                SkipOnceToastView(
                    title: "Tap to skip once",
                    onSkipOnce: onSkipOnce,
                    onTurnOff: onTurnOff
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let skippedMessage {
                Text(skippedMessage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.primary.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(spacing: 12) {
                if alarm.isQuickAlarm {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Quick alarm")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isVisuallyOn ? AppTheme.primary : AppTheme.disabled)
                } else if !alarm.label.isEmpty {
                    Text(alarm.label)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isVisuallyOn ? AppTheme.primary : AppTheme.disabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                if !alarm.isQuickAlarm {
                    ZStack {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.secondary)
                            .rotationEffect(.degrees(90))
                            .frame(width: 34, height: 34)

                        Menu {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                            Button(action: onPreview) {
                                Label("Preview alarm", systemImage: "eye")
                            }
                            Button(action: onSkipOnce) {
                                Label("Skip once", systemImage: "repeat")
                            }
                            Button(action: onDuplicate) {
                                Label("Duplicate alarm", systemImage: "square.on.square")
                            }
                        } label: {
                            Color.clear
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Alarm options")
                    }
                }
            }
        }
        .padding(20)
        .frame(minHeight: 150)
        .background(AppTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !alarm.isQuickAlarm else { return }
            onEdit()
        }
    }

    private var isVisuallyOn: Bool {
        alarm.isEnabled && alarm.skippedFireDate == nil
    }

    private var skippedMessage: String? {
        guard alarm.skippedFireDate != nil, let nextFireDate = alarm.nextFireDate else { return nil }
        let weekday = nextFireDate.formatted(.dateTime.weekday(.wide))
        return "Alarm rings on \(weekday)"
    }

    private var weekdayStrip: some View {
        HStack(spacing: 20) {
            ForEach(Weekday.allCases) { weekday in
                Text(weekday.singleLetter)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(alarm.weekdays.contains(weekday) ? AppTheme.accent : AppTheme.secondary.opacity(0.64))
            }
        }
    }
}

private struct AlarmRingingView: View {
    @EnvironmentObject private var soundManager: SoundManager
    let alarm: Alarm
    var isPreview = false
    let onDismiss: () -> Void
    let remainingSnoozes: SnoozeRemaining
    let onSnooze: () -> Void
    @State private var tapCount = 0
    @State private var completedAction = false

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
                        completedAction = true
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
            if isPreview {
                soundManager.play(alarm: alarm, loops: true)
                VibrationManager.shared.start(alarm: alarm)
                return
            }

            // Let BackgroundAlarmEngine own playback continuously from the
            // moment the alarm fires through dismiss/snooze. Calling fire()
            // here is idempotent — it does nothing if the engine is already
            // ringing this alarm. This avoids a handoff to SoundManager that
            // was causing audio to stop when the user switched apps.
            BackgroundAlarmEngine.shared.fire(alarm: alarm)
            VibrationManager.shared.start(alarm: alarm)
        }
        .onDisappear {
            guard !isPreview, !completedAction else { return }
            BackgroundAlarmEngine.shared.fire(alarm: alarm)
        }
    }

    @ViewBuilder
    private var challengeControl: some View {
        switch alarm.challenge {
        case .none:
            Button {
                completedAction = true
                onDismiss()
            } label: {
                Text("Dismiss")
            }
                .buttonStyle(PrimaryButtonStyle())
        case .tapHold:
            HoldToDismissButton {
                completedAction = true
                onDismiss()
            }
        case .focusTaps:
            Button {
                tapCount += 1
                if tapCount >= 12 {
                    completedAction = true
                    onDismiss()
                }
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

private struct HoldToDismissButton: View {
    @State private var isPressing = false
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
            Text(isPressing ? "Keep holding" : "Hold to dismiss")
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(isPressing ? AppTheme.accent.opacity(0.78) : AppTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: 1.4,
            maximumDistance: 48,
            perform: onDismiss,
            onPressingChanged: { pressing in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isPressing = pressing
                }
            }
        )
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
