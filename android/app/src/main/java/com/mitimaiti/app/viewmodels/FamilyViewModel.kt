package com.mitimaiti.app.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.*
import com.mitimaiti.app.services.APIService
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class FamilyViewModel : ViewModel() {
    private val _members = MutableStateFlow<List<FamilyMember>>(emptyList())
    val members: StateFlow<List<FamilyMember>> = _members.asStateFlow()
    private val _suggestions = MutableStateFlow<List<FamilySuggestion>>(emptyList())
    val suggestions: StateFlow<List<FamilySuggestion>> = _suggestions.asStateFlow()
    private val _currentInvite = MutableStateFlow<FamilyInvite?>(null)
    val currentInvite: StateFlow<FamilyInvite?> = _currentInvite.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _selectedTab = MutableStateFlow(0)
    val selectedTab: StateFlow<Int> = _selectedTab.asStateFlow()
    private val _selectedMemberId = MutableStateFlow<String?>(null)
    val selectedMemberId: StateFlow<String?> = _selectedMemberId.asStateFlow()
    private val _showInviteModal = MutableStateFlow(false)
    val showInviteModal: StateFlow<Boolean> = _showInviteModal.asStateFlow()
    private val _showRevokeAllModal = MutableStateFlow(false)
    val showRevokeAllModal: StateFlow<Boolean> = _showRevokeAllModal.asStateFlow()
    private val _toastMessage = MutableStateFlow<String?>(null)
    val toastMessage: StateFlow<String?> = _toastMessage.asStateFlow()
    val selectedMember: FamilyMember? get() = _members.value.firstOrNull { it.id == _selectedMemberId.value }

    fun selectTab(tab: Int) { _selectedTab.value = tab }
    fun selectMember(id: String?) { _selectedMemberId.value = id }
    fun toggleInviteModal() { _showInviteModal.value = !_showInviteModal.value }
    fun toggleRevokeAllModal() { _showRevokeAllModal.value = !_showRevokeAllModal.value }

    fun loadFamily() { viewModelScope.launch { _isLoading.value = true; APIService.fetchFamily().onSuccess { (m, s) -> _members.value = m; _suggestions.value = s }.onFailure { _error.value = "Failed to load family data" }; _isLoading.value = false } }
    fun generateInvite() { viewModelScope.launch { APIService.generateInvite().onSuccess { _currentInvite.value = it; _showInviteModal.value = true } } }

    fun joinFamily(code: String, roleTag: String, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            APIService.joinFamily(code, roleTag).onSuccess {
                showToast("Joined family"); loadFamily(); onDone(true)
            }.onFailure {
                showToast("Invalid or expired code"); onDone(false)
            }
        }
    }

    fun updatePermission(memberId: String, permissionName: String, value: Boolean) {
        _members.value = _members.value.map { m -> if (m.id == memberId) { val p = m.permissions; m.copy(permissions = when (permissionName) {
            "canViewProfile" -> p.copy(canViewProfile = value); "canViewPhotos" -> p.copy(canViewPhotos = value); "canViewBasics" -> p.copy(canViewBasics = value)
            "canViewSindhi" -> p.copy(canViewSindhi = value); "canViewMatches" -> p.copy(canViewMatches = value); "canSuggest" -> p.copy(canSuggest = value)
            "canViewCulturalScore" -> p.copy(canViewCulturalScore = value); "canViewKundli" -> p.copy(canViewKundli = value); else -> p }) } else m }
        showToast("Permission updated")
    }

    fun enableAllPermissions(memberId: String) { _members.value = _members.value.map { if (it.id == memberId) it.copy(permissions = FamilyPermissions(true, true, true, true, true, true, true, true)) else it }; showToast("All permissions enabled") }
    fun disableAllPermissions(memberId: String) { _members.value = _members.value.map { if (it.id == memberId) it.copy(permissions = FamilyPermissions(false, false, false, false, false, false, false, false)) else it }; showToast("All permissions disabled") }
    fun revokeMember(memberId: String) { _members.value = _members.value.map { if (it.id == memberId) it.copy(status = FamilyMemberStatus.REVOKED) else it }; _selectedMemberId.value = null; showToast("Access revoked"); viewModelScope.launch { APIService.updateFamilyMember(memberId, mapOf("is_revoked" to true)) } }
    fun revokeAllMembers() { val anyId = _members.value.firstOrNull()?.id; _members.value = _members.value.map { it.copy(status = FamilyMemberStatus.REVOKED) }; _showRevokeAllModal.value = false; showToast("All access revoked"); anyId?.let { id -> viewModelScope.launch { APIService.updateFamilyMember(id, mapOf("revoke_all" to true)) } } }
    fun likeSuggestion(id: String) {
        val s = _suggestions.value.firstOrNull { it.id == id } ?: return
        _suggestions.value = _suggestions.value.filter { it.id != id }
        showToast("Added to your feed!")
        // Record a real like on the suggested person so it actually reaches them.
        viewModelScope.launch { APIService.performAction(s.suggestedUser.id, "like") }
    }
    fun passSuggestion(id: String) {
        val s = _suggestions.value.firstOrNull { it.id == id } ?: return
        _suggestions.value = _suggestions.value.filter { it.id != id }
        viewModelScope.launch { APIService.performAction(s.suggestedUser.id, "pass") }
    }
    private fun showToast(message: String) { _toastMessage.value = message; viewModelScope.launch { delay(2000); _toastMessage.value = null } }
}
