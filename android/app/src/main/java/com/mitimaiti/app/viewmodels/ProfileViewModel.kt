package com.mitimaiti.app.viewmodels

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.mitimaiti.app.models.*
import com.mitimaiti.app.services.APIService
import com.mitimaiti.app.services.PhotoRepository
import com.mitimaiti.app.services.UserPrefs
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ProfileViewModel : ViewModel() {
    private val _user = MutableStateFlow<User?>(null)
    val user: StateFlow<User?> = _user.asStateFlow()
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()
    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving.asStateFlow()
    private val _saveSuccess = MutableStateFlow(false)
    val saveSuccess: StateFlow<Boolean> = _saveSuccess.asStateFlow()

    // Basic fields
    val editBio = MutableStateFlow("")
    val editHeight = MutableStateFlow<Int?>(null)
    val editEducation = MutableStateFlow("")
    val editOccupation = MutableStateFlow("")
    val editCompany = MutableStateFlow("")
    val editReligion = MutableStateFlow("")

    // Lifestyle fields
    val editSmoking = MutableStateFlow("")
    val editDrinking = MutableStateFlow("")
    val editExercise = MutableStateFlow("")
    val editWantKids = MutableStateFlow("")
    val editSettlingTimeline = MutableStateFlow("")

    // Sindhi Identity fields
    val editFluency = MutableStateFlow<SindhiFluency?>(null)
    val editDialect = MutableStateFlow("")
    val editGeneration = MutableStateFlow("")
    val editGotra = MutableStateFlow("")
    val editFamilyOriginCity = MutableStateFlow("")
    val editFamilyOriginCountry = MutableStateFlow("")
    val editCommunitySubGroup = MutableStateFlow("")
    val editMotherTongue = MutableStateFlow("")

    // Cultural fields
    val editFamilyValues = MutableStateFlow<FamilyValues?>(null)
    val editFoodPreference = MutableStateFlow<FoodPreference?>(null)
    val editFestivals = MutableStateFlow<List<String>>(emptyList())
    val editCuisinePreferences = MutableStateFlow<List<String>>(emptyList())

    // Personality fields
    val editInterests = MutableStateFlow<List<String>>(emptyList())
    val editMusicPreferences = MutableStateFlow<List<String>>(emptyList())
    val editMovieGenres = MutableStateFlow<List<String>>(emptyList())
    val editTravelStyle = MutableStateFlow("")
    val editLanguages = MutableStateFlow<List<String>>(emptyList())

    // Prompts editing
    val editPrompts = MutableStateFlow<List<UserPrompt>>(emptyList())

    // ── Voice intro (Hinge-style) ──
    val voiceIntroUrl = MutableStateFlow<String?>(null)
    val isUploadingVoice = MutableStateFlow(false)

    fun uploadVoiceIntro(bytes: ByteArray) {
        viewModelScope.launch {
            isUploadingVoice.value = true
            APIService.uploadVoiceIntro(bytes).onSuccess { url ->
                voiceIntroUrl.value = url
                _user.value = _user.value?.copy(voiceIntroUrl = url)
            }.onFailure { _error.value = "Voice intro upload failed" }
            isUploadingVoice.value = false
        }
    }

    fun deleteVoiceIntro() {
        viewModelScope.launch {
            APIService.deleteVoiceIntro().onSuccess {
                voiceIntroUrl.value = null
                _user.value = _user.value?.copy(voiceIntroUrl = null)
            }
        }
    }

    // ── Selfie verification (pose challenge) ──
    val isVerifying = MutableStateFlow(false)
    val verifyMessage = MutableStateFlow<String?>(null)
    /** The pose the server asked the user to copy; non-null = show the
     *  challenge dialog with a "Take selfie" button. */
    val verifyChallenge = MutableStateFlow<com.mitimaiti.app.services.APIService.VerifyChallenge?>(null)

    /** Step 1: fetch the random pose the user must copy. */
    fun startVerifyChallenge() {
        viewModelScope.launch {
            isVerifying.value = true
            APIService.fetchVerifyChallenge()
                .onSuccess { verifyChallenge.value = it }
                .onFailure { verifyMessage.value = "Couldn't start verification. Please try again." }
            isVerifying.value = false
        }
    }

    fun dismissVerifyChallenge() { verifyChallenge.value = null }

    /** Step 2: upload the pose selfie for face verification. */
    fun verifySelfie(bytes: ByteArray) {
        val pose = verifyChallenge.value ?: return
        viewModelScope.launch {
            isVerifying.value = true
            APIService.verifySelfie(bytes, pose.poseId).onSuccess { result ->
                if (result.verified) {
                    _user.value = _user.value?.copy(isVerified = true)
                    verifyChallenge.value = null
                    verifyMessage.value = "You're verified! Your profile now shows the blue badge."
                } else {
                    verifyMessage.value = result.message
                }
            }.onFailure { err ->
                verifyMessage.value = when (err) {
                    is com.mitimaiti.app.services.APIError.DailyLimitReached ->
                        "You've used all 3 verification attempts for today. Try again tomorrow."
                    is com.mitimaiti.app.services.APIError.MessageRejected -> err.reason
                    else -> "Verification failed. Check your connection and try again."
                }
            }
            isVerifying.value = false
        }
    }

    fun dismissVerifyMessage() { verifyMessage.value = null }

    // Photos from PhotoRepository (shared with onboarding). Index 0 = primary.
    val userPhotos: StateFlow<List<com.mitimaiti.app.services.ProfilePhoto>> = PhotoRepository.photos
    val primaryPhotoUri: Uri? get() = PhotoRepository.primaryPhotoUri

    fun addPhoto(uri: Uri) { PhotoRepository.addPhoto(uri) }

    /** Delete on the server first, then drop locally — previously this only
     *  mutated local state and the photo reappeared on next launch. */
    fun removePhoto(index: Int) {
        val photo = PhotoRepository.photoAt(index) ?: return
        if (photo.id == null) {
            PhotoRepository.removePhoto(index)
            return
        }
        viewModelScope.launch {
            APIService.deletePhoto(photo.id)
                .onSuccess { PhotoRepository.removePhoto(photo) }
                .onFailure { err ->
                    _error.value = if (err is com.mitimaiti.app.services.APIError.MinPhotosRequired) {
                        "You can't delete your only photo — add another first."
                    } else "Couldn't delete the photo. Try again."
                }
        }
    }

    /** Move to front locally AND persist: primary flag + new sort order. */
    fun setPrimaryPhoto(index: Int) {
        val photo = PhotoRepository.photoAt(index) ?: return
        PhotoRepository.setPrimaryPhoto(index)
        val id = photo.id ?: return
        viewModelScope.launch {
            APIService.setPrimaryPhoto(id).onFailure {
                _error.value = "Couldn't update your main photo. Try again."
            }
            val orderedIds = PhotoRepository.photos.value.mapNotNull { it.id }
            if (orderedIds.size > 1) APIService.reorderPhotos(orderedIds)
        }
    }

    fun uploadPhotoBytes(bytes: ByteArray, mimeType: String = "image/jpeg") {
        viewModelScope.launch {
            APIService.uploadPhoto(bytes, mimeType).onSuccess { photo ->
                PhotoRepository.addPhoto(
                    com.mitimaiti.app.services.ProfilePhoto(id = photo.id, uri = Uri.parse(photo.url))
                )
            }.onFailure {
                _error.value = "Photo upload failed"
            }
        }
    }

    /** Primary-picker "new photo from gallery": upload FIRST, then promote the
     *  server-backed photo. The old path added a local-only Uri and bailed on
     *  set-primary (no id), so the pick was never uploaded and vanished on
     *  the next profile load. */
    fun uploadAndSetPrimary(context: android.content.Context, uri: Uri) {
        viewModelScope.launch {
            val bytes = com.mitimaiti.app.utils.ImageCompression.compressForUpload(context, uri)
            if (bytes == null) {
                _error.value = "Couldn't read that photo."
                return@launch
            }
            APIService.uploadPhoto(bytes).onSuccess { photo ->
                PhotoRepository.addPhoto(
                    com.mitimaiti.app.services.ProfilePhoto(id = photo.id, uri = Uri.parse(photo.url))
                )
                val idx = PhotoRepository.photos.value.indexOfFirst { it.id == photo.id }
                if (idx > 0) setPrimaryPhoto(idx)
            }.onFailure { err ->
                _error.value = if (err is com.mitimaiti.app.services.APIError.PhotoLimitReached) {
                    "You already have the maximum of 6 photos."
                } else "Photo upload failed"
            }
        }
    }

    /**
     * Snapshot calculator — used to seed the reactive StateFlow below.
     */
    private fun calculateCompleteness(): Int {
        var filled = 0
        val total = 28

        if (PhotoRepository.photos.value.isNotEmpty()) filled++
        if (editBio.value.isNotBlank()) filled++
        if (editHeight.value != null) filled++
        if (editEducation.value.isNotBlank()) filled++
        if (editOccupation.value.isNotBlank()) filled++
        if (editCompany.value.isNotBlank()) filled++
        if (editReligion.value.isNotBlank()) filled++
        if (editSmoking.value.isNotBlank()) filled++
        if (editDrinking.value.isNotBlank()) filled++
        if (editExercise.value.isNotBlank()) filled++
        if (editWantKids.value.isNotBlank()) filled++
        if (editSettlingTimeline.value.isNotBlank()) filled++
        if (editFluency.value != null) filled++
        if (editDialect.value.isNotBlank()) filled++
        if (editGeneration.value.isNotBlank()) filled++
        if (editGotra.value.isNotBlank()) filled++
        if (editFamilyOriginCity.value.isNotBlank()) filled++
        if (editCommunitySubGroup.value.isNotBlank()) filled++
        if (editMotherTongue.value.isNotBlank()) filled++
        if (editFamilyValues.value != null) filled++
        if (editFoodPreference.value != null) filled++
        if (editFestivals.value.isNotEmpty()) filled++
        if (editCuisinePreferences.value.isNotEmpty()) filled++
        if (editInterests.value.isNotEmpty()) filled++
        if (editMusicPreferences.value.isNotEmpty()) filled++
        if (editMovieGenres.value.isNotEmpty()) filled++
        if (editTravelStyle.value.isNotBlank()) filled++
        if (editLanguages.value.isNotEmpty()) filled++

        return ((filled.toFloat() / total) * 100).toInt()
    }

    /**
     * Reactive profile completeness — recomputes whenever any underlying
     * edit field (or the photo list) changes, so the UI always shows the
     * real percentage. Exposed as a StateFlow so Compose recomposes.
     */
    val completenessFlow: StateFlow<Int> = combine(
        listOf<kotlinx.coroutines.flow.Flow<Any?>>(
            PhotoRepository.photos, editBio, editHeight, editEducation, editOccupation,
            editCompany, editReligion, editSmoking, editDrinking, editExercise,
            editWantKids, editSettlingTimeline, editFluency, editDialect, editGeneration,
            editGotra, editFamilyOriginCity, editCommunitySubGroup, editMotherTongue,
            editFamilyValues, editFoodPreference, editFestivals, editCuisinePreferences,
            editInterests, editMusicPreferences, editMovieGenres, editTravelStyle, editLanguages
        )
    ) { _ -> calculateCompleteness() }
        .stateIn(viewModelScope, SharingStarted.Eagerly, 0)

    /** Kept for backward compat with any call sites that read the snapshot. */
    val computedCompleteness: Int get() = completenessFlow.value

    // ── Daily question (Chai Chat) ──
    private val _dailyPrompt = MutableStateFlow<APIService.DailyPromptState?>(null)
    val dailyPrompt: StateFlow<APIService.DailyPromptState?> = _dailyPrompt.asStateFlow()
    private val _isSavingPromptAnswer = MutableStateFlow(false)
    val isSavingPromptAnswer: StateFlow<Boolean> = _isSavingPromptAnswer.asStateFlow()

    fun loadDailyPrompt() {
        viewModelScope.launch {
            APIService.fetchDailyPrompt().onSuccess { _dailyPrompt.value = it }
        }
    }

    fun answerDailyPrompt(answer: String) {
        val trimmed = answer.trim()
        if (trimmed.isEmpty() || _isSavingPromptAnswer.value) return
        _isSavingPromptAnswer.value = true
        viewModelScope.launch {
            APIService.answerPrompt(trimmed)
                .onSuccess {
                    _dailyPrompt.value = _dailyPrompt.value?.copy(answer = trimmed, answeredToday = true)
                        ?: APIService.DailyPromptState(question = null, answer = trimmed, answeredToday = true)
                }
                .onFailure { _error.value = "Couldn't save your answer. Try again." }
            _isSavingPromptAnswer.value = false
        }
    }

    fun loadProfile() {
        loadDailyPrompt()
        viewModelScope.launch {
            _isLoading.value = true
            APIService.fetchProfile()
                .onSuccess { fetched ->
                    // Override the mock/server name with what the user typed
                    // during onboarding, if we captured one.
                    val storedName = UserPrefs.firstName.value
                    val merged = if (storedName.isNotBlank()) {
                        fetched.copy(displayName = storedName)
                    } else fetched
                    _user.value = merged
                    populateEditFields(merged)
                    // Hydrate the shared photo store from the server (primary
                    // first, then sort order). Previously nothing rehydrated
                    // it, so photos vanished from Profile after a relaunch.
                    if (merged.photos.isNotEmpty()) {
                        val ordered = merged.photos.sortedWith(
                            compareByDescending<com.mitimaiti.app.models.UserPhoto> { it.isPrimary }
                                .thenBy { it.sortOrder }
                        )
                        PhotoRepository.setPhotos(
                            ordered.map {
                                com.mitimaiti.app.services.ProfilePhoto(
                                    id = it.id.ifBlank { null },
                                    uri = Uri.parse(it.url.ifBlank { it.urlMedium ?: "" })
                                )
                            }.filter { it.uri.toString().isNotBlank() }
                        )
                    }
                }
                .onFailure { _error.value = "Failed to load profile" }
            _isLoading.value = false
        }
    }

    private fun populateEditFields(user: User) {
        editBio.value = user.bio
        editHeight.value = user.heightCm
        editEducation.value = user.education ?: ""
        editOccupation.value = user.occupation ?: ""
        editCompany.value = user.company ?: ""
        editReligion.value = user.religion ?: ""
        editSmoking.value = user.smoking ?: ""
        editDrinking.value = user.drinking ?: ""
        editExercise.value = user.exercise ?: ""
        editWantKids.value = user.wantKids ?: ""
        editSettlingTimeline.value = user.settlingTimeline ?: ""
        editFluency.value = user.sindhiFluency
        editDialect.value = user.sindhiDialect ?: ""
        editGeneration.value = user.generation ?: ""
        editGotra.value = user.gotra ?: ""
        editFamilyOriginCity.value = user.familyOriginCity ?: ""
        editFamilyOriginCountry.value = user.familyOriginCountry ?: ""
        editCommunitySubGroup.value = user.communitySubGroup ?: ""
        editMotherTongue.value = user.motherTongue ?: ""
        editFamilyValues.value = user.familyValues
        editFoodPreference.value = user.foodPreference
        editFestivals.value = user.festivalsCelebrated
        editCuisinePreferences.value = user.cuisinePreferences
        editInterests.value = user.interests
        editMusicPreferences.value = user.musicPreferences
        editMovieGenres.value = user.movieGenres
        editTravelStyle.value = user.travelStyle ?: ""
        editLanguages.value = user.languages
        editPrompts.value = user.prompts
        voiceIntroUrl.value = user.voiceIntroUrl
    }

    fun saveProfile() {
        viewModelScope.launch {
            _isSaving.value = true

            // Build the nested PATCH /me payload the backend expects. The schema
            // is .strict(), so only send keys it allows, grouped by section, and
            // omit blanks/nulls. Enum values are the lowercased enum name, which
            // matches the backend enums (e.g. NON_VEGETARIAN -> "non_vegetarian").
            val basics = mutableMapOf<String, Any>()
            if (editBio.value.isNotBlank()) basics["bio"] = editBio.value.trim()
            editHeight.value?.let { if (it in 120..240) basics["height_cm"] = it }
            if (editSmoking.value.isNotBlank()) basics["smoking"] = editSmoking.value
            if (editDrinking.value.isNotBlank()) basics["drinking"] = editDrinking.value
            if (editExercise.value.isNotBlank()) basics["exercise"] = editExercise.value
            if (editWantKids.value.isNotBlank()) basics["want_kids"] = editWantKids.value
            if (editSettlingTimeline.value.isNotBlank()) basics["settling"] = editSettlingTimeline.value

            val userFields = mutableMapOf<String, Any>()
            if (editEducation.value.isNotBlank()) userFields["education"] = editEducation.value.trim()
            if (editOccupation.value.isNotBlank()) userFields["occupation"] = editOccupation.value.trim()
            if (editCompany.value.isNotBlank()) userFields["company"] = editCompany.value.trim()
            if (editReligion.value.isNotBlank()) userFields["religion"] = editReligion.value.trim()

            val sindhi = mutableMapOf<String, Any>()
            if (editMotherTongue.value.isNotBlank()) sindhi["mother_tongue"] = editMotherTongue.value.trim()
            if (editDialect.value.isNotBlank()) sindhi["sindhi_dialect"] = editDialect.value.trim()
            if (editCommunitySubGroup.value.isNotBlank()) sindhi["community_sub_group"] = editCommunitySubGroup.value.trim()
            if (editGotra.value.isNotBlank()) sindhi["gotra"] = editGotra.value.trim()
            editFluency.value?.let { sindhi["sindhi_fluency"] = it.name.lowercase() }
            if (editGeneration.value.isNotBlank()) sindhi["generation"] = editGeneration.value
            if (editFamilyOriginCity.value.isNotBlank()) sindhi["family_origin_city"] = editFamilyOriginCity.value.trim()
            if (editFamilyOriginCountry.value.isNotBlank()) sindhi["family_origin_country"] = editFamilyOriginCountry.value.trim()

            val chatti = mutableMapOf<String, Any>()
            editFamilyValues.value?.let { chatti["family_values"] = it.name.lowercase() }
            editFoodPreference.value?.let { chatti["food_preference"] = it.name.lowercase() }
            if (editFestivals.value.isNotEmpty()) chatti["festivals_celebrated"] = editFestivals.value
            if (editCuisinePreferences.value.isNotEmpty()) chatti["cuisine_preferences"] = editCuisinePreferences.value

            val personality = mutableMapOf<String, Any>()
            if (editInterests.value.isNotEmpty()) personality["interests"] = editInterests.value
            if (editMusicPreferences.value.isNotEmpty()) personality["music_preferences"] = editMusicPreferences.value
            if (editMovieGenres.value.isNotEmpty()) personality["movie_genres"] = editMovieGenres.value
            if (editTravelStyle.value.isNotBlank()) personality["travel_style"] = editTravelStyle.value.trim()
            if (editLanguages.value.isNotEmpty()) personality["languages"] = editLanguages.value
            // Always send prompts so removals persist (empty array clears them)
            personality["prompts"] = editPrompts.value.map {
                mapOf("question" to it.question, "answer" to it.answer)
            }

            val payload = mutableMapOf<String, Any>()
            if (basics.isNotEmpty()) payload["basics"] = basics
            if (userFields.isNotEmpty()) payload["user"] = userFields
            if (sindhi.isNotEmpty()) payload["sindhi"] = sindhi
            if (chatti.isNotEmpty()) payload["chatti"] = chatti
            if (personality.isNotEmpty()) payload["personality"] = personality

            APIService.updateProfile(payload)
                .onSuccess {
                    _saveSuccess.value = true
                    _user.value = _user.value?.copy(
                        bio = editBio.value,
                        heightCm = editHeight.value,
                        education = editEducation.value.ifBlank { null },
                        occupation = editOccupation.value.ifBlank { null },
                        company = editCompany.value.ifBlank { null },
                        religion = editReligion.value.ifBlank { null },
                        smoking = editSmoking.value.ifBlank { null },
                        drinking = editDrinking.value.ifBlank { null },
                        exercise = editExercise.value.ifBlank { null },
                        wantKids = editWantKids.value.ifBlank { null },
                        settlingTimeline = editSettlingTimeline.value.ifBlank { null },
                        sindhiFluency = editFluency.value,
                        sindhiDialect = editDialect.value.ifBlank { null },
                        generation = editGeneration.value.ifBlank { null },
                        gotra = editGotra.value.ifBlank { null },
                        familyOriginCity = editFamilyOriginCity.value.ifBlank { null },
                        familyOriginCountry = editFamilyOriginCountry.value.ifBlank { null },
                        communitySubGroup = editCommunitySubGroup.value.ifBlank { null },
                        motherTongue = editMotherTongue.value.ifBlank { null },
                        familyValues = editFamilyValues.value,
                        foodPreference = editFoodPreference.value,
                        festivalsCelebrated = editFestivals.value,
                        cuisinePreferences = editCuisinePreferences.value,
                        interests = editInterests.value,
                        musicPreferences = editMusicPreferences.value,
                        movieGenres = editMovieGenres.value,
                        travelStyle = editTravelStyle.value.ifBlank { null },
                        languages = editLanguages.value,
                        prompts = editPrompts.value
                    )
                }
                .onFailure { _error.value = "Failed to save profile" }
            _isSaving.value = false
        }
    }

    fun dismissSaveSuccess() { _saveSuccess.value = false }

    fun dismissError() { _error.value = null }
}
