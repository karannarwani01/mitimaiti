import Foundation

// Replace with values from Google Cloud Console.
// `iosClientID` is the iOS OAuth Client ID created for this bundle ID
// (com.mitimaiti.MitiMaiti). `webClientID` is the same Web OAuth Client ID
// the backend validates against (env GOOGLE_WEB_CLIENT_ID); it must be set as
// `serverClientID` on the iOS SDK so the issued ID token's `aud` claim
// matches what the backend's Google verifier expects.
//
// In addition to filling these in, two Info.plist edits are required for the
// OAuth callback to return to the app:
//   1. CFBundleURLTypes → CFBundleURLSchemes contains the reversed iOS client
//      ID (e.g. com.googleusercontent.apps.1234567890-abc...).
//   2. (Optional) GIDClientID = iosClientID — only if you'd rather configure
//      the SDK from the plist instead of in code.
enum GoogleSignInConfig {
    static let iosClientID: String = "820326686046-fnflhh4tdm712irkio6d7npaovtpu9al.apps.googleusercontent.com"
    static let webClientID: String = "820326686046-mnsqmqe8sup8v8fvak4mg1o38pgsaqm0.apps.googleusercontent.com"

    static var isConfigured: Bool {
        !iosClientID.isEmpty && !webClientID.isEmpty
    }
}
