import SwiftUI
import UserNotifications

@main
struct MitiMaitiApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var themeManager = ThemeManager()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(authVM)
                    .environmentObject(localization)
                    .environmentObject(themeManager)
                    .preferredColorScheme(themeManager.colorScheme)
                    .withAdaptiveColors()
                    .task {
                        // Force a fresh sign-in on every launch by wiping any
                        // tokens left from a previous run. Stop auto-resuming
                        // the session.
                        await APIService.shared.clearTokens()
                    }

                ToastOverlay()
            }
            .onOpenURL { url in
                GoogleSignInService.handle(url: url)
            }
        }
    }
}

// MARK: - App Delegate for Push Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + sound even when app is in foreground
        completionHandler([.banner, .sound])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let typeString = userInfo["type"] as? String,
           let type = NotificationType(rawValue: typeString),
           let tab = type.destinationTab {
            Task { @MainActor in
                NotificationManager.shared.selectedTab = tab
            }
        }
        completionHandler()
    }
}
