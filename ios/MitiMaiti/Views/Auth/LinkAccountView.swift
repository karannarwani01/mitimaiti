import SwiftUI

/// Shown right after OTP for new users (optional / skippable). Lets them attach
/// an email or their Google account to this phone-based profile so any of them
/// retrieves it on a future login. Also reachable from Settings.
struct LinkAccountView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.adaptiveColors) private var colors

    @State private var showEmailSheet = false
    @State private var emailInput = ""

    private var linked: Bool { authVM.linkResult == "success" }
    private var errorMessage: String? {
        guard let r = authVM.linkResult, r != "success" else { return nil }
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

            Text("Add a backup way to sign in, so you keep your profile even if you change your phone number.")
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
                        Text("You're all set — backup sign-in added.")
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
                    Button(action: { authVM.clearLinkResult(); emailInput = ""; showEmailSheet = true }) {
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
    }

    private var emailSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("We'll link it to your account. You can sign in with it later.")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)

                TextField("you@example.com", text: $emailInput)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))

                if let msg = errorMessage {
                    Text(msg).font(.system(size: 12)).foregroundColor(.red)
                }

                Button(action: { authVM.linkEmailAddress(emailInput) }) {
                    Text(authVM.linkInProgress ? "Linking…" : "Link email")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(emailInput.isEmpty ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(authVM.linkInProgress || emailInput.isEmpty)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Add your email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEmailSheet = false }.disabled(authVM.linkInProgress)
                }
            }
            .onChange(of: authVM.linkResult) { newValue in
                if newValue == "success" { showEmailSheet = false }
            }
        }
        .presentationDetents([.medium])
    }
}
