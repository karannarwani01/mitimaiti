import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    private let localization = LocalizationManager.shared
    @State private var animateIn = false
    @FocusState private var emailFieldFocused: Bool
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    cardHeader
                    if authVM.otpSent {
                        codeEntry
                    } else {
                        emailEntry
                    }
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.bottom, 32)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            emailFieldFocused = true
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                animateIn = true
            }
        }
        .onChange(of: authVM.otpSent) { _, sent in
            if sent { codeFieldFocused = true }
        }
        .onDisappear {
            authVM.resetOtpState()
        }
    }

    private var cardHeader: some View {
        HStack {
            Button {
                if authVM.otpSent {
                    authVM.resetOtpState()
                } else {
                    dismiss()
                }
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

    private var emailEntry: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(localization.t("auth.emailEnter.title"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colors.textPrimary)
                Text(localization.t("auth.emailEnter.subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                TextField(localization.t("auth.emailPlaceholder"), text: $authVM.email)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($emailFieldFocused)
                    .tint(AppTheme.rose)

                if !authVM.email.isEmpty {
                    Image(systemName: "envelope.fill")
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
                        emailFieldFocused ? AppTheme.rose : colors.border,
                        lineWidth: emailFieldFocused ? 1.5 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: emailFieldFocused)

            errorView

            Button {
                authVM.sendEmailOTP()
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
            .disabled(authVM.isLoading || authVM.email.isEmpty)
            .opacity(authVM.email.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var codeEntry: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(localization.t("auth.emailCode.title"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colors.textPrimary)
                Text(String(format: localization.t("auth.emailCode.subtitle"), authVM.email))
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            TextField("000000", text: $authVM.otpCode)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(colors.textPrimary)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFieldFocused)
                .tracking(12)
                .frame(height: 64)
                .padding(.horizontal, 14)
                .background(colors.surfaceMedium)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            codeFieldFocused ? AppTheme.rose : colors.border,
                            lineWidth: codeFieldFocused ? 1.5 : 1
                        )
                )
                .onChange(of: authVM.otpCode) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue {
                        authVM.otpCode = digits
                    }
                }

            errorView

            HStack(spacing: 4) {
                if authVM.resendCooldown > 0 {
                    Text(localization.t("auth.resendCodeIn"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.textMuted)
                    Text("\(authVM.resendCooldown)s")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textMuted)
                } else {
                    Button {
                        authVM.sendEmailOTP()
                    } label: {
                        Text(localization.t("auth.resendCode"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.rose)
                    }
                }
            }

            Button {
                authVM.verifyEmailOTP()
            } label: {
                HStack(spacing: 8) {
                    if authVM.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(localization.t("auth.verify"))
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.rose)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(authVM.isLoading || authVM.otpCode.count != 6)
            .opacity(authVM.otpCode.count != 6 ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

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
}
