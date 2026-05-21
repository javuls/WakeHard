import Foundation

@MainActor
final class AlarmStore: ObservableObject {
    @Published var alarms: [Alarm] = [] {
        didSet {
            save()
            NotificationScheduler.shared.rescheduleAll(alarms: alarms)
            AlarmKitScheduler.shared.sync(alarms: alarms)
            BackgroundAlarmEngine.shared.arm(alarms: alarms)
        }
    }

    private let storageKey = "wakehard.alarms.v1"

    init() {
        load()
        if alarms.isEmpty {
            alarms = [
                Alarm(label: "Morning", hour: 7, minute: 0, weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday], sound: .pulse),
                Alarm(label: "Weekend", hour: 9, minute: 0, weekdays: [.saturday, .sunday], sound: .rise, volume: 0.75)
            ]
        }

        NotificationScheduler.shared.rescheduleAll(alarms: alarms)
        AlarmKitScheduler.shared.sync(alarms: alarms)
        BackgroundAlarmEngine.shared.arm(alarms: alarms)
    }

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
    }

    func update(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
    }

    func delete(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
    }

    func delete(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
    }

    func duplicate(_ alarm: Alarm) {
        var copy = alarm
        copy.id = UUID()
        copy.skippedFireDate = nil
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms.insert(copy, at: alarms.index(after: index))
        } else {
            alarms.append(copy)
        }
    }

    func toggle(_ alarm: Alarm, isEnabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].isEnabled = isEnabled
        if isEnabled {
            alarms[index].skippedFireDate = nil
        }
    }

    func skipOnce(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        let skippedFireDate = alarms[index].nextScheduledFireDateIgnoringSkip()
        alarms[index].isEnabled = true
        alarms[index].skippedFireDate = skippedFireDate
    }

    func clearSkip(for alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].skippedFireDate = nil
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            alarms = try JSONDecoder().decode([Alarm].self, from: data)
        } catch {
            alarms = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
