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
    @State private var emailInput = ""

    private var errorMessage: String? {
        guard let r = authVM.linkResult, r != "success" else { return nil }
        return r
    }

    var body: some View {
        List {
            Section(footer: Text("Add more ways to sign in so you always keep this profile.")) {
                methodRow(
                    icon: "phone.fill", title: "Phone",
                    value: status?.phone.map { "•••• " + String($0.suffix(4)) } ?? "—",
                    linked: status?.phone != nil, canAdd: false, action: {}
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
            if newValue == "success" {
                showEmailSheet = false
                Task { await refresh(); authVM.clearLinkResult() }
            }
        }
        .sheet(isPresented: $showEmailSheet) { emailSheet }
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
                Text("We'll link it to your account. You can sign in with it later.")
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
                Button(action: { authVM.linkEmailAddress(emailInput) }) {
                    Text(authVM.linkInProgress ? "Linking…" : "Link email")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
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
        }
        .presentationDetents([.medium])
    }
}
