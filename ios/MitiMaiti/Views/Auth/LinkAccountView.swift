import SwiftUI

/// Bumble-style "Can we get your number?" — shown after a Google/Apple/email
/// signup so every account ends up anchored to a verified phone. Uses the
/// link/phone/start + verify SMS OTP flow.
///
/// Flip `phoneStepSkippable` to false once Twilio is upgraded from trial —
/// then the step becomes mandatory, matching Bumble exactly.
struct LinkAccountView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.adaptiveColors) private var colors

    private let phoneStepSkippable = true

    @State private var phoneInput = ""
    @State private var codeInput = ""

    private var linked: Bool { authVM.linkResult == "success" || authVM.linkResult == "merged" }
    private var errorMessage: String? {
        guard let r = authVM.linkResult, r != "success", r != "merged" else { return nil }
        return r
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("logo_mark")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(linked ? "Number verified!" : "Can we get your number?")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(colors.textPrimary)
                .padding(.top, 24)

            if linked {
                VStack(spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(red: 0.18, green: 0.71, blue: 0.45))
                            .font(.system(size: 24))
                        Text(authVM.linkResult == "merged"
                             ? "We found your existing profile and merged your sign-ins."
                             : "Your account is secured with your phone number.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                    }
                    Button(action: { authVM.finishLinkStep() }) {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)
            } else {
                Text(authVM.linkPhoneOtpSent
                     ? "Enter the 6-digit code we texted to \(authVM.pendingLinkPhone)."
                     : "We'll text you a code to verify it. It keeps your account secure and makes signing back in easy.")
                    .font(.system(size: 15))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                VStack(spacing: 16) {
                    if !authVM.linkPhoneOtpSent {
                        TextField("+971501234567", text: $phoneInput)
                            .keyboardType(.phonePad)
                            .onChange(of: phoneInput) { v in
                                phoneInput = String(v.filter { $0.isNumber || $0 == "+" }.prefix(16))
                            }
                            .padding()
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))

                        Button(action: { authVM.linkPhoneStart(phoneInput) }) {
                            Text(authVM.linkInProgress ? "Sending…" : "Send code")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(phoneInput.count < 8 ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(authVM.linkInProgress || phoneInput.count < 8)
                    } else {
                        TextField("000000", text: $codeInput)
                            .keyboardType(.numberPad)
                            .onChange(of: codeInput) { v in codeInput = String(v.filter(\.isNumber).prefix(6)) }
                            .padding()
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))

                        Button(action: { authVM.linkPhoneVerify(codeInput) }) {
                            Text(authVM.linkInProgress ? "Verifying…" : "Verify")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(codeInput.count < 4 ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(authVM.linkInProgress || codeInput.count < 4)

                        Button(action: {
                            codeInput = ""; authVM.resetLinkPhoneOtp(); authVM.clearLinkResult()
                        }) {
                            Text("Change number")
                                .font(.system(size: 14))
                                .foregroundColor(colors.textSecondary)
                        }
                        .disabled(authVM.linkInProgress)
                    }

                    if authVM.linkInProgress {
                        ProgressView().tint(AppTheme.rose)
                    }
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal, 32)

                if phoneStepSkippable {
                    Button(action: { authVM.finishLinkStep() }) {
                        Text("Skip for now")
                            .font(.system(size: 15))
                            .foregroundColor(colors.textSecondary)
                    }
                    .padding(.top, 20)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}
