import Foundation

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
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
                try await AlarmManager.shared.schedule(
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
            sound: .named(alarm.sound.fileName)
        )
    }

    func alertPresentation(title: LocalizedStringResource) -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title)
        }

        let stopButton = AlarmButton(
            text: "Dismiss",
            textColor: .white,
            systemImageName: "xmark"
        )
        return AlarmPresentation.Alert(title: title, stopButton: stopButton)
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
#endif
