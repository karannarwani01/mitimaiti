package com.mitimaiti.app.viewmodels

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.Gender
import com.mitimaiti.app.models.Intent
import com.mitimaiti.app.models.ShowMe
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.services.PhotoRepository
import com.mitimaiti.app.services.UserPrefs
import com.mitimaiti.app.utils.ImageCompression
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class OnboardingStep { NAME, BIRTHDAY, GENDER, PHOTOS, INTENT, SHOW_ME, LOCATION, READY }

class OnboardingViewModel : ViewModel() {
    private val _currentStep = MutableStateFlow(OnboardingStep.NAME)
    val currentStep: StateFlow<OnboardingStep> = _currentStep.asStateFlow()
    val firstName = MutableStateFlow(UserPrefs.firstName.value); val isNonSindhi = MutableStateFlow(false)

    init {
        // Persist the name to the shared store whenever it changes, so
        // ProfileViewModel can show the right name after onboarding.
        viewModelScope.launch {
            firstName.collect { UserPrefs.setFirstName(it) }
        }
    }
    val birthDay = MutableStateFlow(""); val birthMonth = MutableStateFlow(""); val birthYear = MutableStateFlow("")
    val selectedGender = MutableStateFlow<Gender?>(null)
    val selectedPhotos: StateFlow<List<Uri>> = PhotoRepository.photos
    val selectedIntent = MutableStateFlow<Intent?>(null); val selectedShowMe = MutableStateFlow<ShowMe?>(null)
    val selectedCity = MutableStateFlow("")

    val age: Int? get() {
        val y = birthYear.value.toIntOrNull() ?: return null; val m = birthMonth.value.toIntOrNull() ?: return null; val d = birthDay.value.toIntOrNull() ?: return null
        return try { java.time.Period.between(java.time.LocalDate.of(y, m, d), java.time.LocalDate.now()).years } catch (e: Exception) { null }
    }
    val isAgeValid: Boolean get() = (age ?: 0) >= 18
    val progress: Float get() = (OnboardingStep.entries.indexOf(_currentStep.value) + 1).toFloat() / OnboardingStep.entries.size
    val canProceed: Boolean get() = when (_currentStep.value) {
        OnboardingStep.NAME -> firstName.value.isNotBlank(); OnboardingStep.BIRTHDAY -> isAgeValid
        OnboardingStep.GENDER -> selectedGender.value != null; OnboardingStep.PHOTOS -> selectedPhotos.value.isNotEmpty()
        OnboardingStep.INTENT -> selectedIntent.value != null; OnboardingStep.SHOW_ME -> selectedShowMe.value != null
        OnboardingStep.LOCATION -> selectedCity.value.isNotBlank(); OnboardingStep.READY -> true
    }

    fun nextStep() { val s = OnboardingStep.entries; val i = s.indexOf(_currentStep.value); if (i < s.size - 1) _currentStep.value = s[i + 1] }
    fun previousStep() { val s = OnboardingStep.entries; val i = s.indexOf(_currentStep.value); if (i > 0) _currentStep.value = s[i - 1] }
    fun addPhoto(uri: Uri) { PhotoRepository.addPhoto(uri) }
    fun removePhoto(index: Int) { PhotoRepository.removePhoto(index) }

    private val _isSubmitting = MutableStateFlow(false)
    val isSubmitting: StateFlow<Boolean> = _isSubmitting.asStateFlow()
    private val _submitError = MutableStateFlow<String?>(null)
    val submitError: StateFlow<String?> = _submitError.asStateFlow()

    fun submitOnboarding(context: Context, onDone: (Boolean) -> Unit) {
        android.util.Log.d("Onboarding", "submitOnboarding called, isSubmitting=${_isSubmitting.value}")
        if (_isSubmitting.value) { android.util.Log.w("Onboarding", "early return: already submitting"); return }
        viewModelScope.launch {
            android.util.Log.d("Onboarding", "coroutine started")
            _isSubmitting.value = true
            _submitError.value = null

            val basics = mutableMapOf<String, Any>()
            if (firstName.value.isNotBlank()) basics["display_name"] = firstName.value.trim()
            val y = birthYear.value.toIntOrNull(); val m = birthMonth.value.toIntOrNull(); val d = birthDay.value.toIntOrNull()
            if (y != null && m != null && d != null) {
                basics["date_of_birth"] = "%04d-%02d-%02d".format(y, m, d)
            }
            selectedGender.value?.let { g ->
                basics["gender"] = when (g) {
                    Gender.MAN -> "man"; Gender.WOMAN -> "woman"; Gender.NON_BINARY -> "non-binary"
                }
            }
            if (selectedCity.value.isNotBlank()) basics["city"] = selectedCity.value.trim()

            val userFields = mutableMapOf<String, Any>()
            selectedIntent.value?.let { i ->
                userFields["intent"] = when (i) {
                    Intent.CASUAL -> "casual"; Intent.OPEN -> "open"
                    Intent.SERIOUS, Intent.MARRIAGE -> "marriage"
                }
            }

            val settings = mutableMapOf<String, Any>()
            selectedShowMe.value?.let { s ->
                settings["gender_preference"] = when (s) {
                    ShowMe.MEN -> "men"; ShowMe.WOMEN -> "women"; ShowMe.EVERYONE -> "everyone"
                }
            }

            val payload = mutableMapOf<String, Any>()
            if (basics.isNotEmpty()) payload["basics"] = basics
            if (userFields.isNotEmpty()) payload["user"] = userFields
            if (settings.isNotEmpty()) payload["settings"] = settings

            android.util.Log.d("Onboarding", "calling updateProfile with payload=$payload")
            val profileResult = APIService.updateProfile(payload)
            android.util.Log.d("Onboarding", "updateProfile result: isSuccess=${profileResult.isSuccess}, exceptionOrNull=${profileResult.exceptionOrNull()}")
            if (profileResult.isFailure) {
                _submitError.value = "Couldn't save profile. Please try again."
                _isSubmitting.value = false
                onDone(false)
                return@launch
            }

            for (uri in selectedPhotos.value) {
                val bytes = ImageCompression.compressForUpload(context, uri) ?: continue
                APIService.uploadPhoto(bytes)
            }

            _isSubmitting.value = false
            onDone(true)
        }
    }
}
