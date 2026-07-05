import SwiftUI
import AuthenticationServices
import CryptoKit

struct PhoneAuthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    private let localization = LocalizationManager.shared
    @State private var selectedCountry = CountryCode.detected()
    @State private var showCountryPicker = false
    @State private var navigateToOTP = false
    @State private var animateIn = false
    @State private var currentAppleNonce: String?
    @FocusState private var phoneFieldFocused: Bool

    // MARK: - Country Code

    struct CountryCode: Identifiable, Hashable {
        let id = UUID()
        let short: String
        let name: String
        let code: String

        static let india = CountryCode(short: "IN", name: "India", code: "+91")
        static let all: [CountryCode] = [
            india,
            CountryCode(short: "AE", name: "UAE", code: "+971"),
            CountryCode(short: "GB", name: "UK", code: "+44"),
            CountryCode(short: "US", name: "USA", code: "+1"),
            CountryCode(short: "CA", name: "Canada", code: "+1"),
            CountryCode(short: "SG", name: "Singapore", code: "+65"),
            CountryCode(short: "HK", name: "Hong Kong", code: "+852"),
            CountryCode(short: "AU", name: "Australia", code: "+61"),
            CountryCode(short: "KE", name: "Kenya", code: "+254"),
            CountryCode(short: "NG", name: "Nigeria", code: "+234")
        ]

        /// Best guess of the user's country from the device region setting.
        /// (Carrier ISO via CoreTelephony is deprecated/unreliable on modern
        /// iOS, so the device region is the standard signal.) No permission
        /// needed. Falls back to India if the region isn't in our list.
        static func detected() -> CountryCode {
            let region: String?
            if #available(iOS 16, *) {
                region = Locale.current.region?.identifier
            } else {
                region = Locale.current.regionCode
            }
            guard let iso = region?.uppercased() else { return .india }
            return all.first { $0.short == iso } ?? .india
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    cardHeader
                    cardContent
                        .padding(.horizontal, AppTheme.spacingMD)
                        .padding(.bottom, 32)
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: authVM.otpSent) { _, sent in
            if sent { navigateToOTP = true }
        }
        .navigationDestination(isPresented: $navigateToOTP) {
            OTPVerificationView()
                .environmentObject(authVM)
        }
        .onAppear {
            phoneFieldFocused = true
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                animateIn = true
            }
        }
    }

    // MARK: - Card Header (back button + logo)

    private var cardHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(colors.surfaceMedium)
                    .clipShape(Circle())
            }

            Spacer()

            Text("MitiMaiti")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.rose)

            Spacer()

            // Balance spacer
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(spacing: 20) {
            // Title & subtitle
            VStack(spacing: 8) {
                Text(localization.t("auth.enterPhone"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                Text(localization.t("auth.sendVerification"))
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
            }

            // Phone input section
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    countryPickerButton
                    phoneInputField
                }
            }

            // Error
            errorView

            // Security note
            securityNote

            // Continue button
            continueButton

            // Divider
            orDivider

            // Social sign-in
            socialButtons

            // Legal
            legalText
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: - Country Picker Button

    private var countryPickerButton: some View {
        Menu {
            ForEach(CountryCode.all) { country in
                Button {
                    selectedCountry = country
                    // The view model composes the E.164 number from this
                    authVM.countryCode = country.code
                } label: {
                    Text("\(country.short) \(country.name) (\(country.code))")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedCountry.short)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.roseGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(selectedCountry.code)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(colors.textMuted)
            }
            .frame(height: 52)
            .padding(.horizontal, 12)
            .background(colors.surfaceMedium)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Phone Input Field

    private var phoneInputField: some View {
        HStack(spacing: 8) {
            TextField(localization.t("auth.phoneNumber"), text: $authVM.phone)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(colors.textPrimary)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($phoneFieldFocused)
                .tint(AppTheme.rose)

            if !authVM.phone.isEmpty {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.rose)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 14)
        .background(colors.surfaceMedium)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    phoneFieldFocused ? AppTheme.rose : colors.border,
                    lineWidth: phoneFieldFocused ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: phoneFieldFocused)
    }

    // MARK: - Error

    @ViewBuilder
    private var errorView: some View {
        if let error = authVM.error {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                Text(error)
                    .font(.system(size: 13))
            }
            .foregroundColor(AppTheme.error)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Security Note

    private var securityNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text(localization.t("auth.securityNote"))
                .font(.system(size: 13))
        }
        .foregroundColor(colors.textMuted)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            authVM.sendOTP()
        } label: {
            HStack(spacing: 8) {
                if authVM.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text(localization.t("auth.continue"))
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppTheme.rose)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(authVM.isLoading || authVM.phone.count < 7)
        .opacity(authVM.phone.count < 7 ? 0.5 : 1)
    }

    // MARK: - Or Divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
            Text(localization.t("common.or"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textMuted)
            Rectangle()
                .fill(colors.border)
                .frame(height: 1)
        }
    }

    // MARK: - Social Buttons

    private var socialButtons: some View {
        HStack(spacing: 10) {
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
                HStack(spacing: 8) {
                    GoogleLogoShape()
                        .frame(width: 18, height: 18)
                    Text("Google")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(colors.surfaceMedium)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colors.border, lineWidth: 1)
                )
            }

            // Apple
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
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Bumble-style: phone is the primary method; Google/Apple are the
            // only alternatives. Email lives in Settings → Sign-in methods.
        }
    }

    // MARK: - Legal

    private var legalText: some View {
        Text(localization.t("auth.legalText"))
            .font(.system(size: 11))
            .foregroundColor(colors.textMuted)
            .multilineTextAlignment(.center)
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

// MARK: - Google Logo (multicolor G drawn with paths)

struct GoogleLogoShape: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 24.0

            // Blue
            var blue = Path()
            blue.move(to: CGPoint(x: 22.56 * s, y: 12.25 * s))
            blue.addCurve(to: CGPoint(x: 22.36 * s, y: 10.0 * s),
                          control1: CGPoint(x: 22.56 * s, y: 11.47 * s),
                          control2: CGPoint(x: 22.49 * s, y: 10.72 * s))
            blue.addLine(to: CGPoint(x: 12.0 * s, y: 10.0 * s))
            blue.addLine(to: CGPoint(x: 12.0 * s, y: 14.26 * s))
            blue.addLine(to: CGPoint(x: 17.92 * s, y: 14.26 * s))
            blue.addCurve(to: CGPoint(x: 15.72 * s, y: 17.58 * s),
                          control1: CGPoint(x: 17.66 * s, y: 15.63 * s),
                          control2: CGPoint(x: 16.89 * s, y: 16.79 * s))
            blue.addLine(to: CGPoint(x: 15.72 * s, y: 20.35 * s))
            blue.addLine(to: CGPoint(x: 19.29 * s, y: 20.35 * s))
            blue.addCurve(to: CGPoint(x: 22.56 * s, y: 12.25 * s),
                          control1: CGPoint(x: 21.37 * s, y: 18.43 * s),
                          control2: CGPoint(x: 22.56 * s, y: 15.61 * s))
            blue.closeSubpath()
            context.fill(blue, with: .color(Color(red: 66/255, green: 133/255, blue: 244/255)))

            // Green
            var green = Path()
            green.move(to: CGPoint(x: 12.0 * s, y: 23.0 * s))
            green.addCurve(to: CGPoint(x: 19.28 * s, y: 20.34 * s),
                           control1: CGPoint(x: 14.97 * s, y: 23.0 * s),
                           control2: CGPoint(x: 17.46 * s, y: 22.02 * s))
            green.addLine(to: CGPoint(x: 15.71 * s, y: 17.57 * s))
            green.addCurve(to: CGPoint(x: 12.0 * s, y: 18.63 * s),
                           control1: CGPoint(x: 14.73 * s, y: 18.23 * s),
                           control2: CGPoint(x: 13.48 * s, y: 18.63 * s))
            green.addCurve(to: CGPoint(x: 5.84 * s, y: 14.1 * s),
                           control1: CGPoint(x: 9.14 * s, y: 18.63 * s),
                           control2: CGPoint(x: 6.71 * s, y: 16.7 * s))
            green.addLine(to: CGPoint(x: 2.18 * s, y: 14.1 * s))
            green.addLine(to: CGPoint(x: 2.18 * s, y: 16.94 * s))
            green.addCurve(to: CGPoint(x: 12.0 * s, y: 23.0 * s),
                           control1: CGPoint(x: 3.99 * s, y: 20.53 * s),
                           control2: CGPoint(x: 7.7 * s, y: 23.0 * s))
            green.closeSubpath()
            context.fill(green, with: .color(Color(red: 52/255, green: 168/255, blue: 83/255)))

            // Yellow
            var yellow = Path()
            yellow.move(to: CGPoint(x: 5.84 * s, y: 14.09 * s))
            yellow.addCurve(to: CGPoint(x: 5.49 * s, y: 12.0 * s),
                            control1: CGPoint(x: 5.62 * s, y: 13.43 * s),
                            control2: CGPoint(x: 5.49 * s, y: 12.73 * s))
            yellow.addCurve(to: CGPoint(x: 5.84 * s, y: 9.91 * s),
                            control1: CGPoint(x: 5.49 * s, y: 11.27 * s),
                            control2: CGPoint(x: 5.62 * s, y: 10.57 * s))
            yellow.addLine(to: CGPoint(x: 5.84 * s, y: 7.07 * s))
            yellow.addLine(to: CGPoint(x: 2.18 * s, y: 7.07 * s))
            yellow.addCurve(to: CGPoint(x: 1.0 * s, y: 12.0 * s),
                            control1: CGPoint(x: 1.43 * s, y: 8.55 * s),
                            control2: CGPoint(x: 1.0 * s, y: 10.22 * s))
            yellow.addCurve(to: CGPoint(x: 2.18 * s, y: 16.93 * s),
                            control1: CGPoint(x: 1.0 * s, y: 13.78 * s),
                            control2: CGPoint(x: 1.43 * s, y: 15.45 * s))
            yellow.addLine(to: CGPoint(x: 5.84 * s, y: 14.09 * s))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(red: 251/255, green: 188/255, blue: 5/255)))

            // Red
            var red = Path()
            red.move(to: CGPoint(x: 12.0 * s, y: 5.38 * s))
            red.addCurve(to: CGPoint(x: 16.21 * s, y: 7.02 * s),
                         control1: CGPoint(x: 13.62 * s, y: 5.38 * s),
                         control2: CGPoint(x: 15.06 * s, y: 5.94 * s))
            red.addLine(to: CGPoint(x: 19.36 * s, y: 3.87 * s))
            red.addCurve(to: CGPoint(x: 12.0 * s, y: 1.0 * s),
                         control1: CGPoint(x: 17.45 * s, y: 2.09 * s),
                         control2: CGPoint(x: 14.97 * s, y: 1.0 * s))
            red.addCurve(to: CGPoint(x: 2.18 * s, y: 7.07 * s),
                         control1: CGPoint(x: 7.7 * s, y: 1.0 * s),
                         control2: CGPoint(x: 3.99 * s, y: 3.47 * s))
            red.addLine(to: CGPoint(x: 5.84 * s, y: 9.91 * s))
            red.addCurve(to: CGPoint(x: 12.0 * s, y: 5.38 * s),
                         control1: CGPoint(x: 6.71 * s, y: 7.31 * s),
                         control2: CGPoint(x: 9.14 * s, y: 5.38 * s))
            red.closeSubpath()
            context.fill(red, with: .color(Color(red: 234/255, green: 67/255, blue: 53/255)))
        }
    }
}
