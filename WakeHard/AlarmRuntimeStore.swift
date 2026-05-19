import Foundation

struct PersistedSnoozeState: Codable {
    let alarmID: UUID
    let fireDate: Date
    let remainingSnoozes: Int?
}

enum AlarmRuntimeStore {
    static let snoozeStorageKey = "wakehard.activeSnooze.v1"
    private static let ringingAlarmKey = "wakehard.ringingAlarmID.v1"

    static func setRingingAlarm(_ alarmID: UUID) {
        UserDefaults.standard.set(alarmID.uuidString, forKey: ringingAlarmKey)
    }

    static func clearRingingAlarm() {
        UserDefaults.standard.removeObject(forKey: ringingAlarmKey)
    }

    static func ringingAlarmID() -> UUID? {
        guard
            let idString = UserDefaults.standard.string(forKey: ringingAlarmKey),
            let id = UUID(uuidString: idString)
        else { return nil }
        return id
    }

    static func persistSnooze(_ state: PersistedSnoozeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: snoozeStorageKey)
    }

    static func clearSnooze() {
        UserDefaults.standard.removeObject(forKey: snoozeStorageKey)
    }

    static func activeSnooze() -> PersistedSnoozeState? {
        guard
            let data = UserDefaults.standard.data(forKey: snoozeStorageKey),
            let persisted = try? JSONDecoder().decode(PersistedSnoozeState.self, from: data)
        else { return nil }
        return persisted
    }
}
