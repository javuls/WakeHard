import SwiftUI

@main
struct WakeHardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var soundManager = SoundManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(alarmStore)
                .environmentObject(soundManager)
                .onAppear {
                    NotificationScheduler.shared.configure()
                    Task { await NotificationScheduler.shared.requestAuthorizationIfNeeded() }
                }
        }
    }
}
