# Mac Session Checklist (iOS)

Everything below happens on the Mac. Total: ~30–40 min.
As of 2026-07-02 the iOS code is ~15 commits ahead of its last build — expect
possible minor Swift compile errors; paste any into Claude and they'll be
fixed fast.

## 1. Pull + build (10 min)
- [ ] `cd mitimaiti && git pull`
- [ ] Open `ios/MitiMaiti.xcodeproj` in Xcode
- [ ] Cmd+B — fix/report any compile errors
- [ ] Cmd+R on a simulator: log in, check Discover loads cards, open a chat,
      check Matches list fills — these were all broken before this batch and
      are the key things to smoke-test

## 2. Firebase push notifications (15 min)
- [ ] Firebase console → mitimaiti project → Project settings → General →
      "Your apps": the iOS app (bundle `com.mitimaiti.MitiMaiti`) should exist
      (added 2026-07-02). Download **GoogleService-Info.plist**
- [ ] Drag the plist into Xcode's MitiMaiti group (check "Copy items if
      needed" + the MitiMaiti target). NOTE: it's gitignored on purpose —
      the repo is public
- [ ] Xcode → project → MitiMaiti target → **Signing & Capabilities** →
      "+ Capability" → add **Push Notifications** (and **Background Modes** →
      tick "Remote notifications")
- [ ] Add the Firebase SDK: File → Add Package Dependencies →
      `https://github.com/firebase/firebase-ios-sdk` → add **FirebaseMessaging**
- [ ] APNs key: developer.apple.com → Certificates, IDs & Profiles → Keys →
      "+" → name it, tick **Apple Push Notifications service (APNs)** →
      register → download the .p8 (once only!) — note the Key ID and Team ID
- [ ] Firebase console → Project settings → **Cloud Messaging** tab → under
      "Apple app configuration" → upload the .p8 + Key ID + Team ID
### Current state (verified 2026-07-04)
The iOS app can **display/handle** notifications but **never registers for
remote push** — `MitiMaitiApp.swift`'s AppDelegate has no
`registerForRemoteNotifications()`, no APNs-token callback, and no
FirebaseMessaging. So the backend (which sends everything via FCM) has no iOS
address to deliver to. Android push works; iOS is the missing half.

### The code is already written — paste it after the SDK is added
Once step-2 config above is done (plist + Push capability + FirebaseMessaging
package + APNs key uploaded), **replace the `AppDelegate` class in
`ios/MitiMaiti/App/MitiMaitiApp.swift` with this** (it mirrors Android's
`FcmTokenRegistrar` + `MitiMaitiMessagingService`):

```swift
import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        // Ask permission, then register with APNs (must be on main thread).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        return true
    }

    // APNs handed us the device token → give it to Firebase (FCM relays to APNs).
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] APNs registration failed: \(error)")
    }

    // Firebase issued/refreshed the FCM token → sync to our backend (same
    // endpoint Android uses: POST /me/fcm-token).
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { try? await APIService.shared.registerFcmToken(fcmToken, platform: "ios") }
    }

    // Show banner while app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Deep-link to the right tab on tap (unchanged behaviour).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let typeString = userInfo["type"] as? String,
           let type = NotificationType(rawValue: typeString),
           let tab = type.destinationTab {
            Task { @MainActor in NotificationManager.shared.selectedTab = tab }
        }
        completionHandler()
    }
}
```

- [ ] After pasting: remove any duplicate `UNUserNotificationCenter` permission
      prompt elsewhere (the AppDelegate now owns it), Cmd+B, and send a test
      push from Firebase console → Cloud Messaging → "Send test message" using
      the FCM token printed for the device.
- [ ] Why this can't be committed ahead of time: it `import`s FirebaseMessaging,
      which isn't in the Xcode project until you add the SPM package — so
      committing it now would break the iOS CI build. Paste it *after* the
      package is added, then commit.

## 3. TestFlight (10 min)
- [ ] Bump build number if needed
- [ ] Product → Archive → Distribute App → App Store Connect → Upload
- [ ] appstoreconnect.apple.com → TestFlight tab → add internal testers

## Known iOS-only gaps (fix on Mac if desired)
- Apple Sign In exists on iOS only (intentional)
- Android profile-photo edit is local-only (PhotoRepository) — same pass can
  look at the iOS photo flow for parity
