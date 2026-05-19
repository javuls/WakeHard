import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private init() {}

    func configure() {
        let open = UNNotificationAction(identifier: "OPEN_APP", title: "Open WakeHard", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: "ALARM",
            actions: [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            // Request critical alert permission for alarms to ensure screen wakes
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert])
        } catch {
            print("Notification authorization failed: \(error)")
        }
    }

    func rescheduleAll(alarms: [Alarm]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for alarm in alarms where alarm.isEnabled {
            schedule(alarm: alarm)
        }
        restorePendingSnoozeIfNeeded(alarms: alarms)
    }

    private func schedule(alarm: Alarm) {
        if alarm.weekdays.isEmpty {
            scheduleOnce(alarm: alarm)
            return
        }

        for weekday in alarm.weekdays {
            var components = alarm.dateComponents
            components.weekday = weekday.rawValue
            addRequest(alarm: alarm, components: components, repeats: true, suffix: weekday.shortTitle)
        }
    }

    private func scheduleOnce(alarm: Alarm) {
        let nextDate = Calendar.current.nextDate(
            after: .now,
            matching: alarm.dateComponents,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) ?? .now.addingTimeInterval(60)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
        addRequest(alarm: alarm, components: components, repeats: false, suffix: "once")
    }

    private func addRequest(alarm: Alarm, components: DateComponents, repeats: Bool, suffix: String) {
        let content = UNMutableNotificationContent()
        content.title = "Alarm ringing"
        content.subtitle = alarm.label.isEmpty ? "WakeHard" : alarm.label
        content.body = "Slide or tap to open WakeHard"
        content.categoryIdentifier = "ALARM"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(alarm.sound.fileName))
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "alarmEvent": "alarm"
        ]

        // Mark as critical alert to ensure screen wakes (if permission granted)
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .critical
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(
            identifier: "\(alarm.id.uuidString)-\(suffix)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleSnooze(alarm: Alarm, fireDate: Date, remainingSnoozes: Int?, showStatusNotification: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: snoozeNotificationIdentifiers(for: alarm))

        if showStatusNotification {
            center.removeDeliveredNotifications(withIdentifiers: deliveredAlarmNotificationIdentifiers(for: alarm))
            addSnoozeStatusNotification(alarm: alarm, fireDate: fireDate, remainingSnoozes: remainingSnoozes)
        }

        let content = UNMutableNotificationContent()
        content.title = "Snooze is over"
        content.subtitle = alarm.label.isEmpty ? "WakeHard" : alarm.label
        content.body = "Snooze is over. Slide or tap to open WakeHard"
        content.categoryIdentifier = "ALARM"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(alarm.sound.fileName))
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "alarmEvent": "snoozeRing"
        ]

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "\(alarm.id.uuidString)-snooze",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelSnooze(for alarm: Alarm) {
        let center = UNUserNotificationCenter.current()
        let identifiers = snoozeNotificationIdentifiers(for: alarm)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func addSnoozeStatusNotification(alarm: Alarm, fireDate: Date, remainingSnoozes: Int?) {
        let content = UNMutableNotificationContent()
        content.title = "Snoozed"
        content.body = snoozeStatusBody(fireDate: fireDate, remainingSnoozes: remainingSnoozes)
        content.categoryIdentifier = "ALARM"
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "alarmEvent": "snoozeStatus"
        ]

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive
        }

        let request = UNNotificationRequest(
            identifier: "\(alarm.id.uuidString)-snooze-status",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func snoozeStatusBody(fireDate: Date, remainingSnoozes: Int?) -> String {
        let minutes = max(1, Int(ceil(fireDate.timeIntervalSinceNow / 60)))
        let time = DateFormatter.localizedString(from: fireDate, dateStyle: .none, timeStyle: .short)
        let snoozeText: String
        if let remainingSnoozes {
            snoozeText = "\(remainingSnoozes) snooze\(remainingSnoozes == 1 ? "" : "s") left"
        } else {
            snoozeText = "Unlimited snoozes left"
        }
        return "Rings at \(time) • \(minutes) min left • \(snoozeText)"
    }

    private func snoozeNotificationIdentifiers(for alarm: Alarm) -> [String] {
        [
            "\(alarm.id.uuidString)-snooze",
            "\(alarm.id.uuidString)-snooze-status"
        ]
    }

    private func deliveredAlarmNotificationIdentifiers(for alarm: Alarm) -> [String] {
        var identifiers = ["\(alarm.id.uuidString)-once"]
        identifiers.append(contentsOf: Weekday.allCases.map { "\(alarm.id.uuidString)-\($0.shortTitle)" })
        identifiers.append(contentsOf: snoozeNotificationIdentifiers(for: alarm))
        return identifiers
    }

    private func restorePendingSnoozeIfNeeded(alarms: [Alarm]) {
        guard
            let persisted = AlarmRuntimeStore.activeSnooze(),
            persisted.fireDate > .now,
            let alarm = alarms.first(where: { $0.id == persisted.alarmID })
        else { return }

        scheduleSnooze(alarm: alarm, fireDate: persisted.fireDate, remainingSnoozes: persisted.remainingSnoozes)
    }
}
