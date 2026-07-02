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
- [ ] Tell Claude when this is done — the AppDelegate wiring (register for
      remote notifications, forward the APNs token to FirebaseMessaging, sync
      the FCM token to POST /me/fcm-token, deep-link on tap) will be written
      to mirror Android's MitiMaitiMessagingService

## 3. TestFlight (10 min)
- [ ] Bump build number if needed
- [ ] Product → Archive → Distribute App → App Store Connect → Upload
- [ ] appstoreconnect.apple.com → TestFlight tab → add internal testers

## Known iOS-only gaps (fix on Mac if desired)
- Apple Sign In exists on iOS only (intentional)
- Android profile-photo edit is local-only (PhotoRepository) — same pass can
  look at the iOS photo flow for parity
