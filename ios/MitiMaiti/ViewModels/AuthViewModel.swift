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
