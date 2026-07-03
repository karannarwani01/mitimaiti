import Foundation

// Decodes the multi-table response from GET /v1/me and flattens into a single User.
// Backend returns: { user, basics, sindhi, chatti, personality, photos, settings, ... }
// iOS User struct flattens fields from all of these into one type.

struct ProfileResponse: Decodable {
    let user: UserRow
    let basics: BasicsRow?
    let sindhi: SindhiRow?
    let chatti: ChattiRow?
    let personality: PersonalityRow?
    let photos: [PhotoRow]?
    let capabilities: CapabilitiesRow?

    struct CapabilitiesRow: Decodable {
        let selfieVerification: Bool?
    }

    struct UserRow: Decodable {
        let id: String
        let phone: String?
        let isVerified: Bool?
        let profileCompleteness: Int?
        let needsOnboarding: Bool?
        let isOnline: Bool?
        let lastActive: Date?
        let intent: Intent?
        let education: String?
        let occupation: String?
        let company: String?
        let religion: String?
    }

    struct BasicsRow: Decodable {
        let displayName: String?
        let dateOfBirth: Date?
        let gender: Gender?
        let bio: String?
        let heightCm: Int?
        let city: String?
        let state: String?
        let country: String?
        let smoking: String?
        let drinking: String?
        let exercise: String?
        let wantKids: String?
        let settlingTimeline: String?
        let showMe: ShowMe?
    }

    struct SindhiRow: Decodable {
        let motherTongue: String?
        let sindhiDialect: String?
        let sindhiFluency: SindhiFluency?
        let communitySubGroup: String?
        let gotra: String?
        let familyOriginCity: String?
        let familyOriginCountry: String?
        let generation: String?
    }

    struct ChattiRow: Decodable {
        let familyValues: FamilyValues?
        let jointFamilyPreference: Bool?
        let festivalsCelebrated: [String]?
        let foodPreference: FoodPreference?
        let cuisinePreferences: [String]?
        let culturalActivities: [String]?
        let traditionalAttire: String?
    }

    struct PersonalityRow: Decodable {
        let interests: [String]?
        let musicPreferences: [String]?
        let movieGenres: [String]?
        let travelStyle: String?
        let petPreference: String?
        let languages: [String]?
        let prompts: [PromptRow]?
        let voiceIntroUrl: String?
    }

    struct PromptRow: Decodable {
        let question: String
        let answer: String
    }

    struct PhotoRow: Decodable {
        let id: String
        let url: String
        let urlThumb: String?
        let urlMedium: String?
        let isPrimary: Bool?
        let sortOrder: Int?
        let isVerified: Bool?
    }

    func toUser() -> User {
        User(
            id: user.id,
            phone: user.phone ?? "",
            displayName: basics?.displayName ?? "",
            dateOfBirth: basics?.dateOfBirth,
            gender: basics?.gender,
            bio: basics?.bio,
            heightCm: basics?.heightCm,
            city: basics?.city,
            state: basics?.state,
            country: basics?.country,
            intent: user.intent,
            showMe: basics?.showMe,
            isVerified: user.isVerified ?? false,
            selfieVerificationAvailable: capabilities?.selfieVerification ?? true,
            profileCompleteness: user.profileCompleteness ?? 0,
            photos: (photos ?? []).map {
                UserPhoto(
                    id: $0.id,
                    url: $0.url,
                    urlThumb: $0.urlThumb,
                    urlMedium: $0.urlMedium,
                    isPrimary: $0.isPrimary ?? false,
                    sortOrder: $0.sortOrder ?? 0,
                    isVerified: $0.isVerified ?? false
                )
            },
            prompts: (personality?.prompts ?? []).map {
                UserPrompt(question: $0.question, answer: $0.answer)
            },
            education: user.education,
            occupation: user.occupation,
            company: user.company,
            religion: user.religion,
            smoking: basics?.smoking,
            drinking: basics?.drinking,
            exercise: basics?.exercise,
            wantKids: basics?.wantKids,
            settlingTimeline: basics?.settlingTimeline,
            motherTongue: sindhi?.motherTongue,
            sindhiDialect: sindhi?.sindhiDialect,
            sindhiFluency: sindhi?.sindhiFluency,
            communitySubGroup: sindhi?.communitySubGroup,
            gotra: sindhi?.gotra,
            familyOriginCity: sindhi?.familyOriginCity,
            familyOriginCountry: sindhi?.familyOriginCountry,
            generation: sindhi?.generation,
            familyValues: chatti?.familyValues,
            jointFamilyPreference: chatti?.jointFamilyPreference,
            festivalsCelebrated: chatti?.festivalsCelebrated,
            foodPreference: chatti?.foodPreference,
            cuisinePreferences: chatti?.cuisinePreferences,
            culturalActivities: chatti?.culturalActivities,
            traditionalAttire: chatti?.traditionalAttire,
            interests: personality?.interests ?? [],
            musicPreferences: personality?.musicPreferences,
            movieGenres: personality?.movieGenres,
            travelStyle: personality?.travelStyle,
            petPreference: personality?.petPreference,
            languages: personality?.languages,
            isOnline: user.isOnline ?? false,
            lastActive: user.lastActive,
            voiceIntroUrl: personality?.voiceIntroUrl
        )
    }
}
