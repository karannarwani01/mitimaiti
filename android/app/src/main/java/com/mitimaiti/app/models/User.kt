package com.mitimaiti.app.models

import java.time.LocalDate
import java.time.Period
import java.util.UUID

data class UserPhoto(
    val id: String = UUID.randomUUID().toString(),
    val url: String,
    val urlThumb: String? = null,
    val urlMedium: String? = null,
    val isPrimary: Boolean = false,
    val sortOrder: Int = 0,
    val isVerified: Boolean = false
)

data class UserPrompt(
    val id: String = UUID.randomUUID().toString(),
    val question: String,
    val answer: String
)

data class User(
    val id: String = UUID.randomUUID().toString(),
    val phone: String = "",
    val email: String? = null,
    val displayName: String = "",
    val dateOfBirth: LocalDate? = null,
    val gender: Gender? = null,
    val bio: String = "",
    val heightCm: Int? = null,
    val city: String = "",
    val state: String = "",
    val country: String = "",
    val intent: Intent? = null,
    val showMe: ShowMe? = null,
    val isVerified: Boolean = false,
    val photos: List<UserPhoto> = emptyList(),
    val prompts: List<UserPrompt> = emptyList(),
    val education: String? = null,
    val occupation: String? = null,
    val company: String? = null,
    val religion: String? = null,
    val smoking: String? = null,
    val drinking: String? = null,
    val exercise: String? = null,
    val wantKids: String? = null,
    val settlingTimeline: String? = null,
    val motherTongue: String? = null,
    val sindhiDialect: String? = null,
    val sindhiFluency: SindhiFluency? = null,
    val communitySubGroup: String? = null,
    val gotra: String? = null,
    val familyOriginCity: String? = null,
    val familyOriginCountry: String? = null,
    val generation: String? = null,
    val familyValues: FamilyValues? = null,
    val jointFamilyPreference: String? = null,
    val festivalsCelebrated: List<String> = emptyList(),
    val foodPreference: FoodPreference? = null,
    val cuisinePreferences: List<String> = emptyList(),
    val culturalActivities: List<String> = emptyList(),
    val traditionalAttire: String? = null,
    val interests: List<String> = emptyList(),
    val musicPreferences: List<String> = emptyList(),
    val movieGenres: List<String> = emptyList(),
    val travelStyle: String? = null,
    val petPreference: String? = null,
    val languages: List<String> = emptyList(),
    val isOnline: Boolean = false,
    val lastActive: Long? = null,
    val profileCompleteness: Int = 0,
    val needsOnboarding: Boolean = false,
    /** Server-computed age. Feed/inbox cards send `age` without a date of birth. */
    val ageYears: Int? = null
) {
    val age: Int?
        get() = ageYears ?: dateOfBirth?.let { Period.between(it, LocalDate.now()).years }

    val primaryPhoto: UserPhoto?
        get() = photos.firstOrNull { it.isPrimary } ?: photos.firstOrNull()
}
