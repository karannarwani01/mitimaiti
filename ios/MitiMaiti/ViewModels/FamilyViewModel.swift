import SwiftUI

@MainActor
class FamilyViewModel: ObservableObject {
    @Published var members: [FamilyMember] = []
    @Published var suggestions: [FamilySuggestion] = []
    @Published var currentInvite: FamilyInvite?
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedTab = 0

    // New state for web-parity
    @Published var activeTab: Int = 0 // 0 = members, 1 = suggestions
    @Published var selectedMemberId: String? = nil // nil = list view, string = detail view
    @Published var showInviteModal = false
    @Published var showRevokeAllModal = false
    @Published var toastMessage: String? = nil

    private let api = APIService.shared

    // MARK: - Computed

    var selectedMember: FamilyMember? {
        guard let id = selectedMemberId else { return nil }
        return members.first(where: { $0.id == id })
    }

    // MARK: - Data Loading

    func loadFamily() {
        isLoading = true
        Task {
            do {
                let result = try await api.fetchFamily()
                members = result.members
                suggestions = result.suggestions
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Invite

    func generateInvite() {
        Task {
            do {
                currentInvite = try await api.generateInvite()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func copyInviteCode() {
        guard let invite = currentInvite else { return }
        UIPasteboard.general.string = invite.code
        showToast("Invite code copied!")
    }

    func shareInviteCode() {
        guard let invite = currentInvite else { return }
        let text = "Join my family circle on MitiMaiti! Use code: \(invite.code)\n\(invite.deepLink)"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Permissions

    func updatePermission(memberId: String, keyPath: WritableKeyPath<FamilyPermissions, Bool>, value: Bool) {
        guard let idx = members.firstIndex(where: { $0.id == memberId }) else { return }
        members[idx].permissions[keyPath: keyPath] = value
    }

    func enableAllPermissions(memberId: String) {
        guard let idx = members.firstIndex(where: { $0.id == memberId }) else { return }
        members[idx].permissions = .allEnabled
        showToast("All permissions enabled for \(members[idx].name)")
    }

    func disableAllPermissions(memberId: String) {
        guard let idx = members.firstIndex(where: { $0.id == memberId }) else { return }
        members[idx].permissions = .allDisabled
        showToast("All permissions disabled for \(members[idx].name)")
    }

    // MARK: - Revoke

    func revokeMember(memberId: String) {
        guard let idx = members.firstIndex(where: { $0.id == memberId }) else { return }
        members[idx].status = .revoked
        Task { try? await api.updateFamilyMember(memberId: memberId, body: ["is_revoked": true]) }
    }

    func revokeAllMembers() {
        let anyId = members.first?.id
        for idx in members.indices {
            members[idx].permissions = .allDisabled
        }
        showToast("All family access revoked")
        if let anyId { Task { try? await api.updateFamilyMember(memberId: anyId, body: ["revoke_all": true]) } }
    }

    // MARK: - Suggestions

    func likeSuggestion(id: String) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        let name = suggestion.suggestedUser.displayName
        suggestions.removeAll { $0.id == id }
        showToast("You liked \(name)!")
    }

    func passSuggestion(id: String) {
        suggestions.removeAll { $0.id == id }
        showToast("Passed")
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}
