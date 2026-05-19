import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private init() {}

    func configure() {
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [])
        let open = UNNotificationAction(identifier: "OPEN_APP", title: "Open", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: "ALARM",
            actions: [open, dismiss],
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
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
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
        content.title = alarm.label.isEmpty ? "WakeHard" : alarm.label
        content.body = "Alarm for \(alarm.formattedTime)"
        content.categoryIdentifier = "ALARM"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(alarm.sound.fileName))
        content.userInfo = ["alarmID": alarm.id.uuidString]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(
            identifier: "\(alarm.id.uuidString)-\(suffix)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
