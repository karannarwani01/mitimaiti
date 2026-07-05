import SwiftUI

/// Shown right after signup (optional / skippable). Secures the OTHER contact
/// method on the account so any of them retrieves this profile on a future
/// login. Phone-first signups are asked for an email (typed or Google — either
/// way the email gets an OTP before it links); email/Google/Apple-first
/// signups are asked for a mobile number, verified by SMS OTP.
struct LinkAccountView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.adaptiveColors) private var colors

    @State private var showEmailSheet = false
    @State private var showPhoneSheet = false
    @State private var emailInput = ""
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

            Text("Secure your account")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(colors.textPrimary)
                .padding(.top, 24)

            Text(authVM.linkStepSecuresPhone
                 ? "Add your mobile number as a backup way to sign in. We'll text you a code to verify it."
                 : "Add a backup way to sign in, so you keep your profile even if you change your phone number.")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .padding(.top, 10)

            if linked {
                VStack(spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(red: 0.18, green: 0.71, blue: 0.45))
                            .font(.system(size: 24))
                        Text(authVM.linkResult == "merged"
                             ? "We found your existing profile and merged your sign-ins."
                             : "You're all set — backup sign-in added.")
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
                VStack(spacing: 12) {
                    if authVM.linkStepSecuresPhone {
                        Button(action: {
                            authVM.clearLinkResult(); authVM.resetLinkPhoneOtp()
                            phoneInput = ""; codeInput = ""; showPhoneSheet = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "phone.fill")
                                Text("Add a mobile number").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(authVM.linkInProgress)
                    } else {
                        Button(action: {
                            authVM.clearLinkResult(); authVM.resetLinkEmailOtp()
                            emailInput = ""; codeInput = ""; showEmailSheet = true
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope.fill")
                                Text("Add an email address").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(authVM.linkInProgress)

                        // Still OTP-verifies the email — the backend sends the
                        // code and the sheet opens at the code step.
                        Button(action: { authVM.linkGoogleAccount() }) {
                            Text("Continue with Google")
                                .font(.system(size: 16))
                                .foregroundColor(colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(colors.border, lineWidth: 1.5)
                                )
                        }
                        .disabled(authVM.linkInProgress)
                    }

                    if authVM.linkInProgress {
                        ProgressView().tint(AppTheme.rose).padding(.top, 8)
                    }
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 32)

                Button(action: { authVM.finishLinkStep() }) {
                    Text("Skip for now")
                        .font(.system(size: 15))
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.top, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .sheet(isPresented: $showEmailSheet) {
            emailSheet
        }
        .sheet(isPresented: $showPhoneSheet) {
            phoneSheet
        }
        // Google link sends the code server-side → open the sheet at the code step.
        .onChange(of: authVM.linkEmailOtpSent) { sent in
            if sent && !showEmailSheet { codeInput = ""; showEmailSheet = true }
        }
    }

    private var emailSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if !authVM.linkEmailOtpSent {
                    Text("We'll send a code to verify it, then link it to your account.")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)

                    TextField("you@example.com", text: $emailInput)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                } else {
                    Text("Enter the 6-digit code we sent to \(authVM.pendingLinkEmail.isEmpty ? emailInput : authVM.pendingLinkEmail).")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)

                    TextField("000000", text: $codeInput)
                        .keyboardType(.numberPad)
                        .onChange(of: codeInput) { v in codeInput = String(v.filter(\.isNumber).prefix(6)) }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                }

                if let msg = errorMessage {
                    Text(msg).font(.system(size: 12)).foregroundColor(.red)
                }

                if !authVM.linkEmailOtpSent {
                    Button(action: { authVM.linkEmailStart(emailInput) }) {
                        Text(authVM.linkInProgress ? "Sending…" : "Send code")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(emailInput.isEmpty ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(authVM.linkInProgress || emailInput.isEmpty)
                } else {
                    Button(action: { authVM.linkEmailVerify(codeInput) }) {
                        Text(authVM.linkInProgress ? "Verifying…" : "Verify")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(codeInput.count < 4 ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(authVM.linkInProgress || codeInput.count < 4)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(authVM.linkEmailOtpSent ? "Enter the code" : "Add your email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showEmailSheet = false; codeInput = ""; authVM.resetLinkEmailOtp()
                    }.disabled(authVM.linkInProgress)
                }
            }
            .onChange(of: authVM.linkResult) { newValue in
                if newValue == "success" || newValue == "merged" { showEmailSheet = false }
            }
        }
        .presentationDetents([.medium])
    }

    private var phoneSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if !authVM.linkPhoneOtpSent {
                    Text("Include the country code. We'll text a code to verify it.")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)

                    TextField("+971501234567", text: $phoneInput)
                        .keyboardType(.phonePad)
                        .onChange(of: phoneInput) { v in
                            phoneInput = String(v.filter { $0.isNumber || $0 == "+" }.prefix(16))
                        }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                } else {
                    Text("Enter the 6-digit code we texted to \(phoneInput).")
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)

                    TextField("000000", text: $codeInput)
                        .keyboardType(.numberPad)
                        .onChange(of: codeInput) { v in codeInput = String(v.filter(\.isNumber).prefix(6)) }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                }

                if let msg = errorMessage {
                    Text(msg).font(.system(size: 12)).foregroundColor(.red)
                }

                if !authVM.linkPhoneOtpSent {
                    Button(action: { authVM.linkPhoneStart(phoneInput) }) {
                        Text(authVM.linkInProgress ? "Sending…" : "Send code")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(phoneInput.count < 8 ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(authVM.linkInProgress || phoneInput.count < 8)
                } else {
                    Button(action: { authVM.linkPhoneVerify(codeInput) }) {
                        Text(authVM.linkInProgress ? "Verifying…" : "Verify")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(codeInput.count < 4 ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(authVM.linkInProgress || codeInput.count < 4)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(authVM.linkPhoneOtpSent ? "Enter the code" : "Add your number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPhoneSheet = false; codeInput = ""; authVM.resetLinkPhoneOtp()
                    }.disabled(authVM.linkInProgress)
                }
            }
            .onChange(of: authVM.linkResult) { newValue in
                if newValue == "success" || newValue == "merged" { showPhoneSheet = false }
            }
        }
        .presentationDetents([.medium])
    }
}
