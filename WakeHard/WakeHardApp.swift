import SwiftUI

@main
struct WakeHardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var soundManager = SoundManager()
    @State private var isLaunching = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(alarmStore)
                    .environmentObject(soundManager)

                if isLaunching {
                    LaunchLoadingView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                AppSettings.registerDefaults()
                NotificationScheduler.shared.configure()
                Task {
                    await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                    await AlarmKitScheduler.shared.requestAuthorizationIfAvailable()
                    AlarmKitScheduler.shared.sync(alarms: alarmStore.alarms)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isLaunching = false
                        }
                    }
                }
            }
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                Text("WakeHard")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }
        }
    }
}
