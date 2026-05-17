import SwiftUI
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var phone = ""
    @Published var email = ""
    @Published var otpCode = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var otpSent = false
    @Published var resendCooldown = 0
    @Published var resendCount = 0

    private let api = APIService.shared
    private var timer: Timer?

    func sendOTP() {
        guard phone.count >= 10 else {
            error = "Please enter a valid phone number"
            return
        }
        isLoading = true
        error = nil

        Task {
            do {
                let success = try await api.sendOTP(phone: phone)
                isLoading = false
                if success {
                    otpSent = true
                    resendCount += 1
                    startResendTimer()
                }
            } catch {
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    func verifyOTP() {
        guard otpCode.count == 6 else {
            error = "Please enter the 6-digit code"
            return
        }
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await api.verifyOTP(phone: phone, code: otpCode)
                isLoading = false
                hasCompletedOnboarding = !result.isNew && result.profileCompleteness >= 50 && result.profileCompleteness >= 50
                isAuthenticated = true
                SocketChat.shared.connect(token: result.accessToken)
            } catch {
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    func sendEmailOTP() {
        guard isValidEmail(email) else {
            error = "Please enter a valid email address"
            return
        }
        isLoading = true
        error = nil

        Task {
            do {
                let success = try await api.sendEmailOTP(email: email)
                isLoading = false
                if success {
                    otpSent = true
                    resendCount += 1
                    startResendTimer()
                }
            } catch {
                isLoading = false
                self.error = "Failed to send code. Please try again."
            }
        }
    }

    func verifyEmailOTP() {
        guard otpCode.count == 6 else {
            error = "Please enter the 6-digit code"
            return
        }
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await api.verifyEmailOTP(email: email, code: otpCode)
                isLoading = false
                hasCompletedOnboarding = !result.isNew && result.profileCompleteness >= 50
                isAuthenticated = true
                SocketChat.shared.connect(token: result.accessToken)
            } catch {
                isLoading = false
                self.error = "Invalid code. Please try again."
            }
        }
    }

    func signInWithGoogle(idToken: String) {
        isLoading = true
        error = nil

        // Extract the user's name from the Google ID token *before* we hit the
        // backend, so onboarding prefill works even if the backend response
        // doesn't carry it back. The ID token is a JWT and its payload
        // contains the `name` claim (full name) plus `given_name`.
        if let name = Self.nameFromIdToken(idToken), !name.isEmpty {
            UserProfileStore.shared.firstName = name
        }

        Task {
            do {
                let result = try await api.verifyGoogleIdToken(idToken)
                isLoading = false
                if let firstName = result.firstName, !firstName.isEmpty {
                    UserProfileStore.shared.firstName = firstName
                }
                hasCompletedOnboarding = !result.isNew && result.profileCompleteness >= 50
                isAuthenticated = true
                SocketChat.shared.connect(token: result.accessToken)
            } catch {
                isLoading = false
                self.error = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    /// Pull the local-part of the `email` claim out of an Apple ID token JWT
    /// and capitalize it as a best-effort name. Apple doesn't expose a name
    /// claim in the token; this is a fallback when credential.fullName is nil
    /// (common after the first sign-in). For `karan.narwani@example.com` this
    /// returns "Karan Narwani"; for `karannarwani01@hotmail.com" it returns
    /// "Karannarwani01" — not great, but better than empty.
    private static func nameGuessFromAppleIdToken(_ idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: pad)
        payload = payload.replacingOccurrences(of: "-", with: "+")
                          .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String,
              let localPart = email.split(separator: "@").first else {
            return nil
        }
        // Strip trailing digits — `karannarwani01` → `karannarwani` — so the
        // prefill reads as a name, not a username.
        let cleaned = String(localPart).trimmingCharacters(in: .decimalDigits)
        guard !cleaned.isEmpty else { return nil }
        return cleaned
            .split(whereSeparator: { ".+_-".contains($0) })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Decode the `name` (or `given_name`) claim from a Google ID token JWT
    /// without verifying the signature — we only trust this for UI prefill,
    /// not for auth.
    private static func nameFromIdToken(_ idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        // JWT uses base64url; pad to a multiple of 4 for Data(base64Encoded:).
        let pad = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: pad)
        payload = payload.replacingOccurrences(of: "-", with: "+")
                          .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let name = json["name"] as? String, !name.isEmpty { return name }
        if let given = json["given_name"] as? String, !given.isEmpty { return given }
        return nil
    }

    func setGoogleSignInError(_ message: String) {
        error = message
    }

    func signInWithApple(
        idToken: String,
        nonce: String?,
        givenName: String?,
        familyName: String?
    ) {
        isLoading = true
        error = nil

        // Apple only sends fullName on the very first sign-in for a given
        // Apple ID and even then is inconsistent — on subsequent sign-ins
        // both fields come back nil. Use fullName when we have it; otherwise
        // fall back to the email local-part from the ID token JWT so the
        // onboarding "What's your full name?" field still has *something* to
        // prefill instead of staying blank.
        let appleName = [givenName, familyName].compactMap { $0 }.joined(separator: " ")
        if !appleName.isEmpty {
            UserProfileStore.shared.firstName = appleName
        } else if let fallback = Self.nameGuessFromAppleIdToken(idToken), !fallback.isEmpty {
            UserProfileStore.shared.firstName = fallback
        }

        Task {
            do {
                let result = try await api.verifyAppleIdToken(
                    idToken,
                    nonce: nonce,
                    givenName: givenName,
                    familyName: familyName
                )
                isLoading = false
                if let firstName = result.firstName, !firstName.isEmpty {
                    UserProfileStore.shared.firstName = firstName
                }
                hasCompletedOnboarding = !result.isNew && result.profileCompleteness >= 50
                isAuthenticated = true
                SocketChat.shared.connect(token: result.accessToken)
            } catch {
                isLoading = false
                self.error = "Apple sign-in failed. Please try again."
            }
        }
    }

    func setAppleSignInError(_ message: String) {
        error = message
    }

    func resetOtpState() {
        otpSent = false
        otpCode = ""
        error = nil
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func logout() {
        isAuthenticated = false
        hasCompletedOnboarding = false
        phone = ""
        email = ""
        otpCode = ""
        otpSent = false
        SocketChat.shared.disconnect()
        Task {
            await api.clearTokens()
        }
    }

    private func isValidEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    private func startResendTimer() {
        resendCooldown = 30
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { t.invalidate(); return }
                if self.resendCooldown > 0 {
                    self.resendCooldown -= 1
                } else {
                    t.invalidate()
                }
            }
        }
    }
}
