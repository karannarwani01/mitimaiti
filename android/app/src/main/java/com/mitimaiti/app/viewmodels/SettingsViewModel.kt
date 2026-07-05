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
    val notifyLikes = MutableStateFlow(true)
    val notifyExpiry = MutableStateFlow(true); val notifySafety = MutableStateFlow(true)
    val notifyDailyPrompts = MutableStateFlow(true); val notifyNewFeatures = MutableStateFlow(true)
    val theme = MutableStateFlow(AppThemeMode.SYSTEM)
    val showDeleteConfirmation = MutableStateFlow(false); val showLogoutConfirmation = MutableStateFlow(false)
    val showDeleteSheet = MutableStateFlow(false)
    private val _toastMessage = MutableStateFlow<String?>(null)
    val toastMessage: StateFlow<String?> = _toastMessage.asStateFlow()
    fun showToast(message: String) { _toastMessage.value = message; viewModelScope.launch { delay(2000); _toastMessage.value = null } }

    init {
        loadSettings()
    }

    /** Seed all settings from the server so the screen reflects what the
     *  backend will actually apply (defaults were previously hardcoded and
     *  could silently disagree with the saved preferences). */
    fun loadSettings() {
        viewModelScope.launch {
            APIService.fetchSettings().onSuccess { s ->
                (s["discovery_enabled"] as? Boolean)?.let { discoveryEnabled.value = it }
                (s["incognito_mode"] as? Boolean)?.let { incognitoMode.value = it }
                (s["show_full_name"] as? Boolean)?.let { showFullName.value = it }
                (s["is_snoozed"] as? Boolean)?.let { isSnoozed.value = it }
                (s["age_min"] as? Number)?.let { ageMin.value = it.toInt() }
                (s["age_max"] as? Number)?.let { ageMax.value = it.toInt() }
                (s["height_min"] as? Number)?.let { heightMin.value = it.toInt() }
                (s["height_max"] as? Number)?.let { heightMax.value = it.toInt() }
                (s["gender_preference"] as? String)?.let { g ->
                    genderPreference.value = when (g) {
                        "men" -> ShowMe.MEN; "women" -> ShowMe.WOMEN; else -> ShowMe.EVERYONE
                    }
                }
                (s["verified_only"] as? Boolean)?.let { verifiedOnly.value = it }
                intentFilter.value = (s["intent_filter"] as? String)?.let { v -> Intent.entries.firstOrNull { it.name.equals(v, true) } }
                religionFilter.value = s["religion_filter"] as? String
                educationFilter.value = s["education_filter"] as? String
                smokingFilter.value = s["smoking_filter"] as? String
                drinkingFilter.value = s["drinking_filter"] as? String
                fluencyFilter.value = (s["fluency_filter"] as? String)?.let { v -> SindhiFluency.entries.firstOrNull { it.name.equals(v, true) } }
                gotraFilter.value = s["gotra_filter"] as? String
                dietaryFilter.value = (s["dietary_filter"] as? String)?.let { v -> FoodPreference.entries.firstOrNull { it.name.equals(v, true) } }
                generationFilter.value = s["generation_filter"] as? String
                familyPlansFilter.value = s["family_plans_filter"] as? String
            }
        }
    }

    // ── Backend-backed settings ──
    // The discovery feed applies these, so persist each change to PATCH /me.
    // The backend upserts only the provided keys, so a single-field patch
    // never clobbers other settings. Null clears a filter.
    private fun patchSettings(settings: Map<String, Any?>) {
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

    fun setIncognitoMode(v: Boolean) {
        incognitoMode.value = v
        patchSettings(mapOf("incognito_mode" to v))
    }

    fun setShowFullName(v: Boolean) {
        showFullName.value = v
        patchSettings(mapOf("show_full_name" to v))
    }

    fun setSnoozed(v: Boolean) {
        isSnoozed.value = v
        viewModelScope.launch { APIService.updateProfile(mapOf("user" to mapOf("is_snoozed" to v))) }
    }

    fun setVerifiedOnly(v: Boolean) {
        verifiedOnly.value = v
        patchSettings(mapOf("verified_only" to v))
    }

    fun setHeightRange(min: Int, max: Int) {
        heightMin.value = min; heightMax.value = max
        patchSettings(mapOf("height_min" to min, "height_max" to max))
    }

    fun setIntentFilter(v: Intent?) {
        intentFilter.value = v
        patchSettings(mapOf("intent_filter" to v?.name?.lowercase()))
    }

    fun setReligionFilter(v: String?) {
        religionFilter.value = v
        patchSettings(mapOf("religion_filter" to v))
    }

    fun setEducationFilter(v: String?) {
        educationFilter.value = v
        patchSettings(mapOf("education_filter" to v))
    }

    fun setSmokingFilter(v: String?) {
        smokingFilter.value = v
        patchSettings(mapOf("smoking_filter" to v))
    }

    fun setDrinkingFilter(v: String?) {
        drinkingFilter.value = v
        patchSettings(mapOf("drinking_filter" to v))
    }

    fun setFluencyFilter(v: SindhiFluency?) {
        fluencyFilter.value = v
        patchSettings(mapOf("fluency_filter" to v?.name?.lowercase()))
    }

    fun setGotraFilter(v: String?) {
        gotraFilter.value = v
        patchSettings(mapOf("gotra_filter" to v))
    }

    fun setDietaryFilter(v: FoodPreference?) {
        dietaryFilter.value = v
        patchSettings(mapOf("dietary_filter" to v?.name?.lowercase()))
    }

    fun setGenerationFilter(v: String?) {
        generationFilter.value = v
        patchSettings(mapOf("generation_filter" to v))
    }

    fun setFamilyPlansFilter(v: String?) {
        familyPlansFilter.value = v
        patchSettings(mapOf("family_plans_filter" to v))
    }

    /** Delete the account on the backend, then invoke [onDone] (log out locally). */
    fun deleteAccount(onDone: () -> Unit) {
        viewModelScope.launch {
            APIService.deleteAccount()
            onDone()
        }
    }
}
