import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum GoogleSignInError: LocalizedError {
    case sdkNotInstalled
    case notConfigured
    case noPresenter
    case noIDToken
    case canceled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sdkNotInstalled:
            return "Google Sign-In SDK isn't installed yet. Add the GoogleSignIn-iOS Swift Package in Xcode."
        case .notConfigured:
            return "Google Sign-In is not configured (missing client ID)."
        case .noPresenter:
            return "Couldn't find a view controller to present the Google sign-in flow."
        case .noIDToken:
            return "Google sign-in returned no ID token."
        case .canceled:
            return "Canceled."
        case .failed(let msg):
            return msg
        }
    }
}

@MainActor
enum GoogleSignInService {

    /// Presents the Google sign-in flow on the active scene's root view controller
    /// and returns a verified ID token whose audience equals the configured web
    /// client ID. Caller hands the ID token to APIService.verifyGoogleIdToken.
    static func signIn() async throws -> String {
        #if canImport(GoogleSignIn)
        guard GoogleSignInConfig.isConfigured else { throw GoogleSignInError.notConfigured }
        guard let presenter = topViewController() else { throw GoogleSignInError.noPresenter }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: GoogleSignInConfig.iosClientID,
            serverClientID: GoogleSignInConfig.webClientID
        )

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw GoogleSignInError.noIDToken
            }
            return idToken
        } catch let error as NSError where error.code == GIDSignInError.canceled.rawValue {
            throw GoogleSignInError.canceled
        } catch {
            throw GoogleSignInError.failed(error.localizedDescription)
        }
        #else
        throw GoogleSignInError.sdkNotInstalled
        #endif
    }

    /// Forward an incoming URL to the Google Sign-In SDK (called from the
    /// MitiMaitiApp scene's onOpenURL). Returns true if the SDK consumed the URL.
    @discardableResult
    static func handle(url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    private static func topViewController(
        base: UIViewController? = UIApplication.shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    ) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}
