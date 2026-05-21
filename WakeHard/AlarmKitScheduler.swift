import Foundation

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
#endif

@MainActor
final class AlarmKitScheduler {
    static let shared = AlarmKitScheduler()

    private let scheduledIDsKey = "wakehard.alarmKit.scheduledIDs.v1"
    private var syncTask: Task<Void, Never>?

    private init() {}

    func requestAuthorizationIfAvailable() async {
        guard #available(iOS 26.0, *) else { return }
        _ = await requestAuthorization()
    }

    func sync(alarms: [Alarm]) {
        guard #available(iOS 26.0, *) else { return }

        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncOnSupportedSystem(alarms: alarms)
        }
    }

    func cancelAll() {
        guard #available(iOS 26.0, *) else { return }

        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.cancelStoredSystemAlarms()
        }
    }

    @available(iOS 26.0, *)
    private func syncOnSupportedSystem(alarms: [Alarm]) async {
        guard await requestAuthorization() else { return }

        let activeAlarms = alarms.filter(\.isEnabled)
        let desiredIDs = Set(activeAlarms.map(\.id))
        let storedIDs = persistedScheduledIDs
        let removedIDs = storedIDs.subtracting(desiredIDs)

        for id in removedIDs {
            guard !Task.isCancelled else { return }
            try? AlarmManager.shared.cancel(id: id)
        }

        for alarm in activeAlarms {
            guard !Task.isCancelled else { return }
            do {
                try? AlarmManager.shared.cancel(id: alarm.id)
                _ = try await AlarmManager.shared.schedule(
                    id: alarm.id,
                    configuration: alarmKitConfiguration(for: alarm)
                )
            } catch {
                print("AlarmKit scheduling failed for \(alarm.id): \(error)")
            }
        }

        persistedScheduledIDs = desiredIDs
    }

    @available(iOS 26.0, *)
    private func requestAuthorization() async -> Bool {
        do {
            switch AlarmManager.shared.authorizationState {
            case .authorized:
                return true
            case .denied:
                return false
            case .notDetermined:
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            @unknown default:
                return false
            }
        } catch {
            print("AlarmKit authorization failed: \(error)")
            return false
        }
    }

    @available(iOS 26.0, *)
    private func cancelStoredSystemAlarms() async {
        let ids = persistedScheduledIDs
        for id in ids {
            guard !Task.isCancelled else { return }
            try? AlarmManager.shared.cancel(id: id)
        }
        persistedScheduledIDs = []
    }

    func stopAlertingAlarm(id: UUID) {
        guard #available(iOS 26.0, *) else { return }

        do {
            guard
                let alarm = try AlarmManager.shared.alarms.first(where: { $0.id == id }),
                alarm.state == .alerting
            else { return }

            try AlarmManager.shared.stop(id: id)
        } catch {
            print("AlarmKit stop failed for \(id): \(error)")
        }
    }

    private var persistedScheduledIDs: Set<UUID> {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: scheduledIDsKey) ?? []
            return Set(strings.compactMap(UUID.init(uuidString:)))
        }
        set {
            let strings = newValue.map(\.uuidString)
            UserDefaults.standard.set(strings, forKey: scheduledIDsKey)
        }
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct WakeHardAlarmMetadata: AlarmMetadata {
    let alarmID: String
    let label: String
}

@available(iOS 26.0, *)
private extension AlarmKitScheduler {
    func alarmKitConfiguration(for alarm: Alarm) -> AlarmManager.AlarmConfiguration<WakeHardAlarmMetadata> {
        let label = alarm.label.isEmpty ? "WakeHard" : alarm.label
        let title = LocalizedStringResource(stringLiteral: label)
        let presentation = AlarmPresentation(alert: alertPresentation(title: title))
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: WakeHardAlarmMetadata(alarmID: alarm.id.uuidString, label: label),
            tintColor: .green
        )

        return .alarm(
            schedule: alarmKitSchedule(for: alarm),
            attributes: attributes,
            stopIntent: OpenWakeHardAlarmIntent(alarmID: alarm.id),
            secondaryIntent: OpenWakeHardAlarmIntent(alarmID: alarm.id),
            // AlarmKit can only play system or bundled app sounds. For
            // selected songs, use silence so the system surface appears
            // without playing a backup tone before WakeHard starts the song.
            sound: .named(alarm.systemAlertSoundFileName)
        )
    }

    func alertPresentation(title: LocalizedStringResource) -> AlarmPresentation.Alert {
        let openButton = AlarmButton(
            text: "Open WakeHard",
            textColor: .white,
            systemImageName: "arrow.up.forward.app"
        )

        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: title,
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        }

        let stopButton = AlarmButton(
            text: "Dismiss",
            textColor: .white,
            systemImageName: "xmark"
        )
        return AlarmPresentation.Alert(
            title: title,
            stopButton: stopButton,
            secondaryButton: openButton,
            secondaryButtonBehavior: .custom
        )
    }

    func alarmKitSchedule(for alarm: Alarm) -> AlarmKit.Alarm.Schedule? {
        if alarm.weekdays.isEmpty || alarm.skippedFireDate != nil {
            guard let fireDate = alarm.nextFireDate else { return nil }
            return .fixed(fireDate)
        }

        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let weekdays = alarm.weekdays
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.alarmKitWeekday)
        return .relative(.init(time: time, repeats: .weekly(weekdays)))
    }
}

@available(iOS 26.0, *)
private extension Weekday {
    var alarmKitWeekday: Locale.Weekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }
}

@available(iOS 26.0, *)
struct OpenWakeHardAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open WakeHard"
    static var description = IntentDescription("Open WakeHard to the ringing alarm screen.")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Alarm ID") var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        await MainActor.run {
            AlarmKitScheduler.shared.stopAlertingAlarm(id: id)
            AlarmRuntimeStore.setRingingAlarm(id)
            NotificationCenter.default.post(name: .alarmKitAlarmOpened, object: id)
        }
        return .result()
    }
}
#endif
