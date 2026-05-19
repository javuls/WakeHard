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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        guard content.categoryIdentifier == "ALARM" else {
            return [.banner, .list, .sound]
        }

        ScreenWakeManager.wakeScreenAndShowAlarm()
        let event = AlarmNotificationEvent(userInfo: content.userInfo)
        NotificationCenter.default.post(name: .alarmNotificationPresented, object: event)
        return []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        ScreenWakeManager.wakeScreenAndShowAlarm()
        let event = AlarmNotificationEvent(userInfo: response.notification.request.content.userInfo)
        NotificationCenter.default.post(name: .alarmNotificationOpened, object: event)
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
}
