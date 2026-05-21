import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        NotificationScheduler.shared.scheduleKeepOpenWarningIfNeeded(
            hasUpcomingAlarm: hasUpcomingAlarmForTerminationWarning()
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        guard content.categoryIdentifier != "KEEP_OPEN" else {
            return [.banner, .list]
        }

        guard content.categoryIdentifier == "ALARM" else {
            return [.banner, .list, .sound]
        }

        ScreenWakeManager.wakeScreenAndShowAlarm()
        let event = AlarmNotificationEvent(userInfo: content.userInfo)
        NotificationCenter.default.post(name: .alarmNotificationPresented, object: event)
        return [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        let content = response.notification.request.content
        guard content.categoryIdentifier != "KEEP_OPEN" else { return }

        ScreenWakeManager.wakeScreenAndShowAlarm()
        let event = AlarmNotificationEvent(userInfo: content.userInfo)
        NotificationCenter.default.post(name: .alarmNotificationOpened, object: event)
    }

    private func hasUpcomingAlarmForTerminationWarning() -> Bool {
        if
            let snooze = AlarmRuntimeStore.activeSnooze(),
            snooze.fireDate > .now
        {
            return true
        }

        guard
            let data = UserDefaults.standard.data(forKey: "wakehard.alarms.v1"),
            let alarms = try? JSONDecoder().decode([Alarm].self, from: data)
        else { return false }

        return alarms.contains { alarm in
            alarm.isEnabled && alarm.nextFireDate != nil
        }
    }
}

struct AlarmNotificationEvent {
    enum Kind: String {
        case alarm
        case snoozeStatus
        case snoozeRing
    }

    let alarmID: UUID?
    let kind: Kind

    init(userInfo: [AnyHashable: Any]) {
        if
            let idString = userInfo["alarmID"] as? String,
            let id = UUID(uuidString: idString)
        {
            alarmID = id
        } else {
            alarmID = nil
        }

        let rawKind = userInfo["alarmEvent"] as? String
        kind = rawKind.flatMap(Kind.init(rawValue:)) ?? .alarm
    }
}

// MARK: - Screen Wake Manager

enum ScreenWakeManager {
    /// Wakes the screen and requests fullscreen presentation when an alarm fires
    static func wakeScreenAndShowAlarm() {
        // Ensure the key window is visible and in foreground
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                window.isHidden = false
                window.windowLevel = .alert + 1  // Ensure it's above other windows
            }

        // Request fullscreen geometry (iOS 16+)
        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { windowScene in
                    // Request fullscreen to wake the display
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                }
        }

        // Additional attempt to ensure app is in foreground
        if #available(iOS 13.0, *) {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { windowScene in
                    windowScene.windows.forEach { window in
                        window.makeKeyAndVisible()
                    }
                }
        }
    }
}

extension Notification.Name {
    static let alarmNotificationOpened = Notification.Name("alarmNotificationOpened")
    static let alarmNotificationPresented = Notification.Name("alarmNotificationPresented")
    static let alarmKitAlarmOpened = Notification.Name("alarmKitAlarmOpened")
}
