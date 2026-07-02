import SwiftUI

struct OTPVerificationView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    private let localization = LocalizationManager.shared

    @FocusState private var focusedField: OTPField?
    @State private var digits: [String] = Array(repeating: "", count: 6)
    @State private var shakeOffset: CGFloat = 0
    @State private var animateIn = false

    // MARK: - Focus Enum

    enum OTPField: Int, CaseIterable {
        case d0, d1, d2, d3, d4, d5
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // White card container (matching web design)
                    VStack(spacing: 0) {
                        cardHeader
                        cardContent
                    }
                    .background(colors.cardDark)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: colors.elevatedShadowColor, radius: 24, x: 0, y: 8)
                    .padding(.horizontal, AppTheme.spacingMD)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 20)

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            focusedField = .d0
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                animateIn = true
            }
        }
        .onChange(of: authVM.error) { _, newError in
            if newError != nil {
                triggerShake()
            }
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack {
            Button {
                authVM.otpSent = false
                dismiss()
            } label: {
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
                Text(localization.t("auth.verifyNumber"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                Text(localization.t("auth.enterCode"))
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)

                Text(maskedPhone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.rose)
            }

            // OTP input fields
            otpFieldsRow

            // Demo hint
            demoHint

            // Error
            errorView

            // Verify button
            verifyButton

            // Resend section
            resendSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: - OTP Fields

    private var otpFieldsRow: some View {
        HStack(spacing: 10) {
            ForEach(OTPField.allCases, id: \.rawValue) { field in
                otpDigitBox(field: field)
            }
        }
        .offset(x: shakeOffset)
    }

    private func otpDigitBox(field: OTPField) -> some View {
        let index = field.rawValue
        let isFocused = focusedField == field
        let hasValue = !digits[index].isEmpty

        let borderColor: Color = {
            if isFocused { return AppTheme.rose }
            if hasValue { return AppTheme.rose }
            return colors.border
        }()

        let bgColor: Color = hasValue
            ? AppTheme.rose.opacity(0.05)
            : colors.surfaceMedium

        return TextField("", text: $digits[index])
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(colors.textPrimary)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
            )
            .focused($focusedField, equals: field)
            .onChange(of: digits[index]) { _, newValue in
                handleDigitChange(index: index, value: newValue)
            }
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 10)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.75)
                    .delay(Double(index) * 0.05),
                value: animateIn
            )
    }

    // MARK: - Demo Hint

    /// The fixed 123456 code only works when the backend runs in dev mode.
    /// Never show it in release builds — real users get a real OTP.
    @ViewBuilder
    private var demoHint: some View {
        #if DEBUG
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
            Text(localization.t("auth.demoCode"))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(AppTheme.gold)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppTheme.gold.opacity(0.1))
        )
        #endif
    }

    // MARK: - Error View

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

    // MARK: - Verify Button

    private var verifyButton: some View {
        Button {
            authVM.otpCode = digits.joined()
            authVM.verifyOTP()
        } label: {
            HStack(spacing: 8) {
                if authVM.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text(localization.t("auth.verify"))
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(allDigitsFilled ? AppTheme.rose : AppTheme.rose.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(authVM.isLoading || !allDigitsFilled)
    }

    // MARK: - Resend Section

    private var resendSection: some View {
        VStack(spacing: 8) {
            if authVM.resendCooldown > 0 {
                HStack(spacing: 6) {
                    Text(localization.t("auth.resendCodeIn"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.textMuted)
                    Text("\(authVM.resendCooldown)s")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                }
            } else if authVM.resendCount < 3 {
                Button {
                    authVM.sendOTP()
                    digits = Array(repeating: "", count: 6)
                    focusedField = .d0
                } label: {
                    Text(localization.t("auth.resendCode"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.rose)
                }
            }

            if authVM.resendCount >= 3 {
                Text(localization.t("auth.maxResend"))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.error)
            }
        }
    }

    // MARK: - Helpers

    private var allDigitsFilled: Bool {
        digits.allSatisfy { !$0.isEmpty }
    }

    private var maskedPhone: String {
        let phone = authVM.phone
        if phone.count >= 10 {
            let masked = String(repeating: "•", count: phone.count - 4)
            return masked + phone.suffix(4)
        }
        return phone
    }

    private func handleDigitChange(index: Int, value: String) {
        // Handle paste of full OTP code
        if value.count > 1 {
            let cleaned = value.filter { $0.isNumber }
            if cleaned.count == 6 {
                for i in 0..<6 {
                    let charIndex = cleaned.index(cleaned.startIndex, offsetBy: i)
                    digits[i] = String(cleaned[charIndex])
                }
                focusedField = .d5
                submitAfterDelay()
                return
            }
            digits[index] = String(cleaned.last ?? Character(""))
        }

        // Auto-advance to next field
        if !digits[index].isEmpty && index < 5 {
            focusedField = OTPField(rawValue: index + 1)
        }

        // Handle backspace: move to previous field
        if digits[index].isEmpty && index > 0 {
            focusedField = OTPField(rawValue: index - 1)
        }

        // Auto-verify when all 6 digits entered
        if allDigitsFilled {
            submitAfterDelay()
        }
    }

    private func submitAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            authVM.otpCode = digits.joined()
            authVM.verifyOTP()
        }
    }

    private func triggerShake() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default) { shakeOffset = 6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.default) { shakeOffset = -4 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.spring()) { shakeOffset = 0 }
        }
    }
}
