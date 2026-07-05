import SwiftUI
import AuthenticationServices
import CryptoKit

/// Bumble-style landing: full-screen brand moment with the auth methods as
/// stacked full-width pills at the bottom — Apple (per platform convention),
/// phone number, Google — plus the legal line. No marketing scroll; signup
/// and sign-in are the same buttons.
struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    private let localization = LocalizationManager.shared
    @Environment(\.adaptiveColors) private var colors
    @State private var currentAppleNonce: String?
    @State private var animateIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // ── Brand moment ──
                VStack(spacing: 16) {
                    Text(localization.t("welcome.title"))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.roseGradient)

                    Text(localization.t("welcome.subtitle"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.gold, AppTheme.goldLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .multilineTextAlignment(.center)

                    Text(localization.t("welcome.tagline"))
                        .font(.system(size: 15))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.top, 4)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : -20)

                Spacer()

                // ── Auth methods (stacked pills, Bumble-style) ──
                VStack(spacing: 12) {
                    // Apple first — platform convention on iOS
                    SignInWithAppleButton(
                        onRequest: { request in
                            let nonce = randomNonce()
                            currentAppleNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = sha256(nonce)
                        },
                        onCompletion: { result in
                            switch result {
                            case .success(let auth):
                                guard
                                    let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                                    let tokenData = credential.identityToken,
                                    let token = String(data: tokenData, encoding: .utf8)
                                else {
                                    authVM.setAppleSignInError("Apple sign-in failed: missing token")
                                    return
                                }
                                authVM.signInWithApple(
                                    idToken: token,
                                    nonce: currentAppleNonce,
                                    givenName: credential.fullName?.givenName,
                                    familyName: credential.fullName?.familyName
                                )
                            case .failure(let err):
                                let nsErr = err as NSError
                                if nsErr.code != ASAuthorizationError.canceled.rawValue {
                                    authVM.setAppleSignInError(nsErr.localizedDescription)
                                }
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    // Phone — the primary MitiMaiti method
                    NavigationLink {
                        PhoneAuthView().environmentObject(authVM)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16))
                            Text("Use cell phone number")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(AppTheme.roseGradient)
                        )
                    }

                    // Google
                    Button {
                        Task {
                            do {
                                let idToken = try await GoogleSignInService.signIn()
                                authVM.signInWithGoogle(idToken: idToken)
                            } catch GoogleSignInError.canceled {
                                // user dismissed — silent
                            } catch {
                                authVM.setGoogleSignInError(error.localizedDescription)
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            GoogleLogoShape()
                                .frame(width: 18, height: 18)
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(colors.surfaceMedium)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(colors.border, lineWidth: 1.5)
                        )
                    }

                    if authVM.isLoading {
                        ProgressView().tint(AppTheme.rose).padding(.top, 4)
                    }
                    if let error = authVM.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.error)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)

                // ── Legal ──
                VStack(spacing: 8) {
                    Text(localization.t("auth.legalText"))
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.spacingLG)

                    HStack(spacing: 20) {
                        NavigationLink { LegalView(page: .terms) } label: {
                            Text("Terms").font(.system(size: 12)).foregroundColor(colors.textMuted)
                        }
                        NavigationLink { LegalView(page: .privacy) } label: {
                            Text("Privacy").font(.system(size: 12)).foregroundColor(colors.textMuted)
                        }
                        NavigationLink { LegalView(page: .guidelines) } label: {
                            Text("Guidelines").font(.system(size: 12)).foregroundColor(colors.textMuted)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .appBackground()
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                    animateIn = true
                }
            }
        }
    }

    // MARK: - Apple Sign-In nonce helpers

    private func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                fatalError("SecRandomCopyBytes failed: OSStatus \(status)")
            }
            for r in randoms where remaining > 0 {
                if r < charset.count {
                    result.append(charset[Int(r)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
