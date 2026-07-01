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

class SettingsViewModel : ViewModel() {
    val discoveryEnabled = MutableStateFlow(true); val incognitoMode = MutableStateFlow(false)
    val showFullName = MutableStateFlow(false); val isSnoozed = MutableStateFlow(false)
    val ageMin = MutableStateFlow(21); val ageMax = MutableStateFlow(35)
    val heightMin = MutableStateFlow(150); val heightMax = MutableStateFlow(190)
    val genderPreference = MutableStateFlow(ShowMe.WOMEN); val intentFilter = MutableStateFlow<Intent?>(null)
    val verifiedOnly = MutableStateFlow(false)
    val fluencyFilter = MutableStateFlow<SindhiFluency?>(null); val generationFilter = MutableStateFlow<String?>(null)
    val religionFilter = MutableStateFlow<String?>(null); val gotraFilter = MutableStateFlow<String?>(null)
    val dietaryFilter = MutableStateFlow<FoodPreference?>(null)
    val educationFilter = MutableStateFlow<String?>(null); val smokingFilter = MutableStateFlow<String?>(null)
    val drinkingFilter = MutableStateFlow<String?>(null); val familyPlansFilter = MutableStateFlow<String?>(null)
    val notifyMatches = MutableStateFlow(true); val notifyMessages = MutableStateFlow(true)
    val notifyLikes = MutableStateFlow(true); val notifyFamily = MutableStateFlow(true)
    val notifyExpiry = MutableStateFlow(true); val notifySafety = MutableStateFlow(true)
    val notifyDailyPrompts = MutableStateFlow(true); val notifyNewFeatures = MutableStateFlow(true)
    val theme = MutableStateFlow(AppThemeMode.SYSTEM)
    val showDeleteConfirmation = MutableStateFlow(false); val showLogoutConfirmation = MutableStateFlow(false)
    val showDeleteSheet = MutableStateFlow(false)
    private val _toastMessage = MutableStateFlow<String?>(null)
    val toastMessage: StateFlow<String?> = _toastMessage.asStateFlow()
    fun showToast(message: String) { _toastMessage.value = message; viewModelScope.launch { delay(2000); _toastMessage.value = null } }

    // ── Backend-backed settings ──
    // The discovery feed applies these (age/gender/discoverable), so persist each
    // change to PATCH /me. The backend upserts only the provided keys, so a
    // single-field patch never clobbers other settings.
    private fun patchSettings(settings: Map<String, Any>) {
        viewModelScope.launch { APIService.updateProfile(mapOf("settings" to settings)) }
    }

    fun setDiscoveryEnabled(v: Boolean) {
        discoveryEnabled.value = v
        patchSettings(mapOf("discovery_enabled" to v))
    }

    fun setAgeRange(min: Int, max: Int) {
        ageMin.value = min; ageMax.value = max
        patchSettings(mapOf("age_min" to min, "age_max" to max))
    }

    fun setGenderPreference(v: ShowMe) {
        genderPreference.value = v
        patchSettings(mapOf("gender_preference" to when (v) {
            ShowMe.MEN -> "men"; ShowMe.WOMEN -> "women"; ShowMe.EVERYONE -> "everyone"
        }))
    }
}
