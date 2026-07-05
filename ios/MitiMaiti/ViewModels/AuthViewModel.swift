import SwiftUI
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var phone = ""
    /// Dial code from the country picker. The backend requires E.164
    /// (+<country><number>) — sending the bare national number 400s every
    /// phone OTP request.
    @Published var countryCode = "+91"
    @Published var email = ""

    /// Full E.164 number composed from the picker's dial code and the typed
    /// number. A typed leading + is trusted as a complete number.
    var e164Phone: String {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") { return "+" + trimmed.filter { $0.isNumber } }
        var digits = trimmed.filter { $0.isNumber }
        while digits.hasPrefix("0") { digits.removeFirst() }
        return countryCode + digits
    }
    @Published var otpCode = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var otpSent = false
    @Published var resendCooldown = 0
    @Published var resendCount = 0

    // Account linking (post-signup "secure your account" step + Settings)
    @Published var showLinkStep = false
    /// true → the link step asks for a mobile number (email/Google/Apple-first
    /// signups); false → it asks for an email (phone-first signups).
    @Published var linkStepSecuresPhone = false
    @Published var linkInProgress = false
    /// nil = idle, "success" = linked, otherwise a user-facing error message.
    @Published var linkResult: String? = nil
    @Published var linkEmailOtpSent = false
    @Published var pendingLinkEmail = ""

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
                let success = try await api.sendOTP(phone: e164Phone)
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
                let result = try await api.verifyOTP(phone: e164Phone, code: otpCode)
                isLoading = false
                hasCompletedOnboarding = !result.needsOnboarding
                // a phone-first signup already has its verified
                // phone — straight to onboarding, no link step. Email/Google
                // can be added later in Settings.
                showLinkStep = false
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
                hasCompletedOnboarding = !result.needsOnboarding
                // New email-first users get the "secure your mobile number" step.
                showLinkStep = result.needsOnboarding
                linkStepSecuresPhone = true
                isAuthenticated = true
                SocketChat.shared.connect(token: result.accessToken)
            } catch {
                isLoading = false
                self.error = "Invalid code. Please try again."
            }
        }
    }

    func clearLinkResult() { linkResult = nil }
    func finishLinkStep() { showLinkStep = false; linkResult = nil }

    func linkEmailAddress(_ rawEmail: String) {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.contains(".") else {
            linkResult = "Please enter a valid email address"; return
        }
        linkInProgress = true
        linkResult = nil
        Task {
            do {
                try await api.linkEmail(email)
                linkInProgress = false
                linkResult = "success"
            } catch {
                linkInProgress = false
                linkResult = "Couldn't link that email — it may already be in use."
            }
        }
    }

    /// Step 1: send an OTP to the email the user wants to add.
    func linkEmailStart(_ rawEmail: String) {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.contains(".") else {
            linkResult = "Please enter a valid email address"; return
        }
        linkInProgress = true
        linkResult = nil
        Task {
            do {
                try await api.linkEmailStart(email)
                pendingLinkEmail = email
                linkEmailOtpSent = true
                linkInProgress = false
            } catch {
                linkInProgress = false
                linkResult = "Couldn't send the code. Please try again."
            }
        }
    }

    /// Step 2: verify the emailed code → attaches the email (or auto-merges).
    func linkEmailVerify(_ code: String) {
        linkInProgress = true
        linkResult = nil
        Task {
            do {
                let merged = try await api.linkEmailVerify(pendingLinkEmail, code: code)
                linkInProgress = false
                linkResult = merged ? "merged" : "success"
            } catch {
                linkInProgress = false
                linkResult = "That code is invalid or expired."
            }
        }
    }

    func resetLinkEmailOtp() { linkEmailOtpSent = false; pendingLinkEmail = "" }

    func linkGoogleAccount() {
        linkInProgress = true
        linkResult = nil
        Task {
            do {
                let idToken = try await GoogleSignInService.signIn()
                // Prefill the onboarding name from the ID token when we don't
                // have one yet (phone-OTP signup linking Google before
                // onboarding). Never overwrites an existing name.
                if UserProfileStore.shared.firstName.isEmpty,
                   let name = Self.nameFromIdToken(idToken), !name.isEmpty {
                    UserProfileStore.shared.firstName = name
                }
                // Google OAuth is trusted directly — no email OTP.
                let merged = try await api.linkGoogle(idToken: idToken)
                linkInProgress = false
                linkResult = merged ? "merged" : "success"
            } catch GoogleSignInError.canceled {
                linkInProgress = false
            } catch {
                linkInProgress = false
                linkResult = "Couldn't link Google. Please try again."
            }
        }
    }

    // MARK: - Phone linking (email-first accounts securing a mobile number)

    @Published var linkPhoneOtpSent = false
    @Published var pendingLinkPhone = ""

    /// Step 1: send an SMS OTP to the phone the user wants to add.
    func linkPhoneStart(_ rawPhone: String) {
        let phone = rawPhone.filter { !$0.isWhitespace }
        guard phone.range(of: #"^\+[1-9]\d{6,14}$"#, options: .regularExpression) != nil else {
            linkResult = "Enter the number with country code, e.g. +971501234567"; return
        }
        linkInProgress = true
        linkResult = nil
        Task {
            do {
                try await api.linkPhoneStart(phone)
                pendingLinkPhone = phone
                linkPhoneOtpSent = true
                linkInProgress = false
            } catch {
                linkInProgress = false
                linkResult = "Couldn't send the code. Please try again."
            }
        }
    }

    /// Step 2: verify the SMS code → attaches the phone (or auto-merges).
    func linkPhoneVerify(_ code: String) {
        linkInProgress = true
        linkResult = nil
        Task {
            do {
                let merged = try await api.linkPhoneVerify(pendingLinkPhone, code: code)
                linkInProgress = false
                linkResult = merged ? "merged" : "success"
            } catch {
                linkInProgress = false
                linkResult = "That code is invalid or expired."
            }
        }
    }

    func resetLinkPhoneOtp() { linkPhoneOtpSent = false; pendingLinkPhone = "" }

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
                hasCompletedOnboarding = !result.needsOnboarding
                // New Google-first users get the "secure your mobile number" step.
                showLinkStep = result.needsOnboarding
                linkStepSecuresPhone = true
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
                hasCompletedOnboarding = !result.needsOnboarding
                // New Apple-first users get the "secure your mobile number" step.
                showLinkStep = result.needsOnboarding
                linkStepSecuresPhone = true
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

    /// Attempt to resume a previously saved session on app launch. If valid
    /// tokens are found and accepted by the backend, the user skips the
    /// Welcome screen; onboarding is shown only if the server says it's still
    /// needed. No stored/valid session leaves the user on Welcome.
    func restoreSession() async {
        guard let needsOnboarding = await api.restoreSession() else { return }
        hasCompletedOnboarding = !needsOnboarding
        isAuthenticated = true
        if let token = await api.currentAccessToken() {
            SocketChat.shared.connect(token: token)
        }
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
