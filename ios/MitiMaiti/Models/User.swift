import Foundation

struct UserPhoto: Identifiable, Codable, Hashable {
    let id: String
    let url: String
    var urlThumb: String?
    var urlMedium: String?
    var isPrimary: Bool
    var sortOrder: Int
    var isVerified: Bool

    init(id: String = UUID().uuidString, url: String, urlThumb: String? = nil, urlMedium: String? = nil, isPrimary: Bool = false, sortOrder: Int = 0, isVerified: Bool = false) {
        self.id = id
        self.url = url
        self.urlThumb = urlThumb
        self.urlMedium = urlMedium
        self.isPrimary = isPrimary
        self.sortOrder = sortOrder
        self.isVerified = isVerified
    }
}

struct UserPrompt: Identifiable, Codable, Hashable {
    let id: String
    let question: String
    let answer: String

    init(id: String = UUID().uuidString, question: String, answer: String) {
        self.id = id
        self.question = question
        self.answer = answer
    }
}

struct User: Identifiable, Codable, Hashable {
    let id: String
    var phone: String
    var displayName: String
    var dateOfBirth: Date?
    var gender: Gender?
    var bio: String?
    var heightCm: Int?
    var city: String?
    var state: String?
    var country: String?
    var intent: Intent?
    var showMe: ShowMe?
    var isVerified: Bool
    var profileCompleteness: Int
    var photos: [UserPhoto]
    var prompts: [UserPrompt]

    // Basics
    var education: String?
    var occupation: String?
    var company: String?
    var religion: String?
    var smoking: String?
    var drinking: String?
    var exercise: String?
    var wantKids: String?
    var settlingTimeline: String?

    // Sindhi
    var motherTongue: String?
    var sindhiDialect: String?
    var sindhiFluency: SindhiFluency?
    var communitySubGroup: String?
    var gotra: String?
    var familyOriginCity: String?
    var familyOriginCountry: String?
    var generation: String?

    // Chatti
    var familyValues: FamilyValues?
    var jointFamilyPreference: Bool?
    var festivalsCelebrated: [String]?
    var foodPreference: FoodPreference?
    var cuisinePreferences: [String]?
    var culturalActivities: [String]?
    var traditionalAttire: String?

    // Personality
    var interests: [String]
    var musicPreferences: [String]?
    var movieGenres: [String]?
    var travelStyle: String?
    var petPreference: String?
    var languages: [String]?

    var isOnline: Bool
    var lastActive: Date?

    /// Server-computed age. Feed/inbox cards send `age` without a date of birth.
    var ageYears: Int?

    var age: Int {
        if let ageYears { return ageYears }
        guard let dob = dateOfBirth else { return 0 }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }

    var primaryPhoto: UserPhoto? {
        photos.first(where: { $0.isPrimary }) ?? photos.first
    }

    init(
        id: String = UUID().uuidString,
        phone: String = "",
        displayName: String = "",
        dateOfBirth: Date? = nil,
        gender: Gender? = nil,
        bio: String? = nil,
        heightCm: Int? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        intent: Intent? = nil,
        showMe: ShowMe? = nil,
        isVerified: Bool = false,
        profileCompleteness: Int = 0,
        photos: [UserPhoto] = [],
        prompts: [UserPrompt] = [],
        education: String? = nil,
        occupation: String? = nil,
        company: String? = nil,
        religion: String? = nil,
        smoking: String? = nil,
        drinking: String? = nil,
        exercise: String? = nil,
        wantKids: String? = nil,
        settlingTimeline: String? = nil,
        motherTongue: String? = nil,
        sindhiDialect: String? = nil,
        sindhiFluency: SindhiFluency? = nil,
        communitySubGroup: String? = nil,
        gotra: String? = nil,
        familyOriginCity: String? = nil,
        familyOriginCountry: String? = nil,
        generation: String? = nil,
        familyValues: FamilyValues? = nil,
        jointFamilyPreference: Bool? = nil,
        festivalsCelebrated: [String]? = nil,
        foodPreference: FoodPreference? = nil,
        cuisinePreferences: [String]? = nil,
        culturalActivities: [String]? = nil,
        traditionalAttire: String? = nil,
        interests: [String] = [],
        musicPreferences: [String]? = nil,
        movieGenres: [String]? = nil,
        travelStyle: String? = nil,
        petPreference: String? = nil,
        languages: [String]? = nil,
        isOnline: Bool = false,
        lastActive: Date? = nil,
        ageYears: Int? = nil
    ) {
        self.id = id
        self.phone = phone
        self.displayName = displayName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.bio = bio
        self.heightCm = heightCm
        self.city = city
        self.state = state
        self.country = country
        self.intent = intent
        self.showMe = showMe
        self.isVerified = isVerified
        self.profileCompleteness = profileCompleteness
        self.photos = photos
        self.prompts = prompts
        self.education = education
        self.occupation = occupation
        self.company = company
        self.religion = religion
        self.smoking = smoking
        self.drinking = drinking
        self.exercise = exercise
        self.wantKids = wantKids
        self.settlingTimeline = settlingTimeline
        self.motherTongue = motherTongue
        self.sindhiDialect = sindhiDialect
        self.sindhiFluency = sindhiFluency
        self.communitySubGroup = communitySubGroup
        self.gotra = gotra
        self.familyOriginCity = familyOriginCity
        self.familyOriginCountry = familyOriginCountry
        self.generation = generation
        self.familyValues = familyValues
        self.jointFamilyPreference = jointFamilyPreference
        self.festivalsCelebrated = festivalsCelebrated
        self.foodPreference = foodPreference
        self.cuisinePreferences = cuisinePreferences
        self.culturalActivities = culturalActivities
        self.traditionalAttire = traditionalAttire
        self.interests = interests
        self.musicPreferences = musicPreferences
        self.movieGenres = movieGenres
        self.travelStyle = travelStyle
        self.petPreference = petPreference
        self.languages = languages
        self.isOnline = isOnline
        self.lastActive = lastActive
        self.ageYears = ageYears
    }
}
