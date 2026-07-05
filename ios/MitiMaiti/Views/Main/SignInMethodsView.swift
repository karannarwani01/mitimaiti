import SwiftUI

/// Settings → Sign-in methods. Shows which methods are on the account (phone,
/// email, Google) and lets the user add the missing ones. Reuses the same
/// linking calls as the post-OTP LinkAccountView.
struct SignInMethodsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.adaptiveColors) private var colors

    @State private var status: APIService.LinkStatus?
    @State private var loading = true
    @State private var showEmailSheet = false
    @State private var showPhoneSheet = false
    @State private var emailInput = ""
    @State private var phoneInput = ""
    @State private var codeInput = ""

    private var errorMessage: String? {
        guard let r = authVM.linkResult, r != "success" else { return nil }
        return r
    }

    var body: some View {
        List {
            Section(footer: Text("Add more ways to sign in so you always keep this profile.")) {
                methodRow(
                    icon: "phone.fill", title: "Phone",
                    value: status?.phone.map { "•••• " + String($0.suffix(4)) } ?? "Not linked",
                    linked: status?.phone != nil, canAdd: true,
                    action: {
                        authVM.clearLinkResult(); authVM.resetLinkPhoneOtp()
                        phoneInput = ""; codeInput = ""; showPhoneSheet = true
                    }
                )
                methodRow(
                    icon: "envelope.fill", title: "Email",
                    value: status?.email ?? "Not linked",
                    linked: status?.email != nil, canAdd: true,
                    action: { authVM.clearLinkResult(); emailInput = ""; showEmailSheet = true }
                )
                methodRow(
                    icon: "g.circle.fill", title: "Google",
                    value: (status?.google == true) ? "Linked" : "Not linked",
                    linked: status?.google == true, canAdd: true,
                    action: { authVM.linkGoogleAccount() }
                )
            }

            if let msg = errorMessage {
                Section { Text(msg).font(.system(size: 13)).foregroundColor(.red) }
            }
        }
        .navigationTitle("Sign-in methods")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading && status == nil { ProgressView().tint(AppTheme.rose) }
            if authVM.linkInProgress { ProgressView().tint(AppTheme.rose) }
        }
        .task { await refresh() }
        .onChange(of: authVM.linkResult) { newValue in
            if newValue == "success" || newValue == "merged" {
                showEmailSheet = false; showPhoneSheet = false; codeInput = ""
                authVM.resetLinkEmailOtp(); authVM.resetLinkPhoneOtp()
                Task { await refresh(); authVM.clearLinkResult() }
            }
        }
        // Google link sends the email code server-side → open the sheet at the
        // code step (policy: even a Google-proven email is OTP-verified).
        .onChange(of: authVM.linkEmailOtpSent) { sent in
            if sent && !showEmailSheet { codeInput = ""; showEmailSheet = true }
        }
        .sheet(isPresented: $showEmailSheet) { emailSheet }
        .sheet(isPresented: $showPhoneSheet) { phoneSheet }
    }

    @MainActor
    private func refresh() async {
        loading = true
        status = try? await APIService.shared.linkStatus()
        loading = false
    }

    @ViewBuilder
    private func methodRow(icon: String, title: String, value: String, linked: Bool, canAdd: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(linked ? AppTheme.rose : colors.textMuted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(colors.textPrimary)
                Text(value).font(.system(size: 13)).foregroundColor(colors.textMuted)
            }
            Spacer()
            if linked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.18, green: 0.71, blue: 0.45))
            } else if canAdd {
                Button("Add", action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.rose)
                    .disabled(authVM.linkInProgress)
            }
        }
        .padding(.vertical, 4)
    }

    private var emailSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if !authVM.linkEmailOtpSent {
                    Text("We'll send a code to verify it, then link it to your account.")
                        .font(.system(size: 14)).foregroundColor(colors.textSecondary)
                    TextField("you@example.com", text: $emailInput)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                    if let msg = errorMessage {
                        Text(msg).font(.system(size: 12)).foregroundColor(.red)
                    }
                    Button(action: { authVM.linkEmailStart(emailInput) }) {
                        Text(authVM.linkInProgress ? "Sending…" : "Send code")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(emailInput.isEmpty ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(authVM.linkInProgress || emailInput.isEmpty)
                } else {
                    Text("Enter the 6-digit code we sent to \(authVM.pendingLinkEmail.isEmpty ? emailInput : authVM.pendingLinkEmail).")
                        .font(.system(size: 14)).foregroundColor(colors.textSecondary)
                    TextField("000000", text: $codeInput)
                        .keyboardType(.numberPad)
                        .onChange(of: codeInput) { v in codeInput = String(v.filter { $0.isNumber }.prefix(6)) }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                    if let msg = errorMessage {
                        Text(msg).font(.system(size: 12)).foregroundColor(.red)
                    }
                    Button(action: { authVM.linkEmailVerify(codeInput) }) {
                        Text(authVM.linkInProgress ? "Verifying…" : "Verify")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
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
                    Button("Cancel") { showEmailSheet = false; codeInput = ""; authVM.resetLinkEmailOtp() }.disabled(authVM.linkInProgress)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var phoneSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                if !authVM.linkPhoneOtpSent {
                    Text("Include the country code. We'll text a code to verify it.")
                        .font(.system(size: 14)).foregroundColor(colors.textSecondary)
                    TextField("+971501234567", text: $phoneInput)
                        .keyboardType(.phonePad)
                        .onChange(of: phoneInput) { v in
                            phoneInput = String(v.filter { $0.isNumber || $0 == "+" }.prefix(16))
                        }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                    if let msg = errorMessage {
                        Text(msg).font(.system(size: 12)).foregroundColor(.red)
                    }
                    Button(action: { authVM.linkPhoneStart(phoneInput) }) {
                        Text(authVM.linkInProgress ? "Sending…" : "Send code")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(phoneInput.count < 8 ? AppTheme.rose.opacity(0.5) : AppTheme.rose)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(authVM.linkInProgress || phoneInput.count < 8)
                } else {
                    Text("Enter the 6-digit code we texted to \(authVM.pendingLinkPhone.isEmpty ? phoneInput : authVM.pendingLinkPhone).")
                        .font(.system(size: 14)).foregroundColor(colors.textSecondary)
                    TextField("000000", text: $codeInput)
                        .keyboardType(.numberPad)
                        .onChange(of: codeInput) { v in codeInput = String(v.filter { $0.isNumber }.prefix(6)) }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
                    if let msg = errorMessage {
                        Text(msg).font(.system(size: 12)).foregroundColor(.red)
                    }
                    Button(action: { authVM.linkPhoneVerify(codeInput) }) {
                        Text(authVM.linkInProgress ? "Verifying…" : "Verify")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
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
                    Button("Cancel") { showPhoneSheet = false; codeInput = ""; authVM.resetLinkPhoneOtp() }.disabled(authVM.linkInProgress)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
