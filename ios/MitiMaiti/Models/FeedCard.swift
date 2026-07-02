import Foundation

struct CulturalDimension: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let score: Int
    let maxScore: Int

    var percentage: Double {
        guard maxScore > 0 else { return 0 }
        return Double(score) / Double(maxScore) * 100
    }

    init(id: String = UUID().uuidString, name: String, description: String, score: Int, maxScore: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.score = score
        self.maxScore = maxScore
    }
}

struct CulturalScore: Codable, Hashable {
    let overallScore: Int
    let badge: CulturalBadge
    let dimensions: [CulturalDimension]
}

struct KundliGuna: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let score: Int
    let maxScore: Int

    init(id: String = UUID().uuidString, name: String, description: String, score: Int, maxScore: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.score = score
        self.maxScore = maxScore
    }
}

struct KundliScore: Codable, Hashable {
    let totalScore: Int
    let maxScore: Int
    let tier: KundliTier
    let gunas: [KundliGuna]

    init(totalScore: Int, maxScore: Int = 36, tier: KundliTier, gunas: [KundliGuna]) {
        self.totalScore = totalScore
        self.maxScore = maxScore
        self.tier = tier
        self.gunas = gunas
    }
}

struct FeedCard: Identifiable, Codable, Hashable {
    let id: String
    let user: User
    let culturalScore: CulturalScore
    let kundliScore: KundliScore?
    let commonInterests: Int
    let distanceKm: Double?
    var isExplore: Bool

    init(
        id: String = UUID().uuidString,
        user: User,
        culturalScore: CulturalScore,
        kundliScore: KundliScore? = nil,
        commonInterests: Int = 0,
        distanceKm: Double? = nil,
        isExplore: Bool = false
    ) {
        self.id = id
        self.user = user
        self.culturalScore = culturalScore
        self.kundliScore = kundliScore
        self.commonInterests = commonInterests
        self.distanceKm = distanceKm
        self.isExplore = isExplore
    }

    // MARK: - Decoding the backend's FLAT card shape
    //
    // GET /feed returns user fields at the top level of each card (no nested
    // `user` object), `cultural_score` as an Int with `cultural_badge` beside
    // it, and `is_explore` only on explore cards. The synthesized decoder
    // expected a nested structure and threw on every feed response, leaving
    // the iOS deck permanently empty.

    private enum FlatKeys: String, CodingKey {
        case id, firstName, displayName, age, city, state, country, bio,
             intent, isVerified, profileCompleteness, photos, aboutMe,
             interests, culturalScore, culturalBadge, kundliScore, kundliTier,
             commonInterests, dailyPromptAnswer, distanceKm, isOnline,
             sindhiFluency, familyValues, foodPreference, heightCm, education,
             occupation, company, religion, smoking, drinking, exercise,
             isExplore
    }

    private struct FlatPhoto: Decodable {
        let url: String?
        let urlThumb: String?
        let urlMedium: String?
        let isPrimary: Bool?
        let sortOrder: Int?
        let isVerified: Bool?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlatKeys.self)

        let cardId = try c.decode(String.self, forKey: .id)
        self.id = cardId

        let photos: [UserPhoto] = ((try? c.decodeIfPresent([FlatPhoto].self, forKey: .photos)) ?? nil)?
            .compactMap { p in
                guard let url = p.url ?? p.urlMedium else { return nil }
                return UserPhoto(
                    url: url,
                    urlThumb: p.urlThumb,
                    urlMedium: p.urlMedium,
                    isPrimary: p.isPrimary ?? false,
                    sortOrder: p.sortOrder ?? 0,
                    isVerified: p.isVerified ?? false
                )
            } ?? []

        self.user = User(
            id: cardId,
            displayName: try c.decodeIfPresent(String.self, forKey: .displayName)
                ?? c.decodeIfPresent(String.self, forKey: .firstName) ?? "",
            gender: nil,
            bio: try c.decodeIfPresent(String.self, forKey: .bio)
                ?? c.decodeIfPresent(String.self, forKey: .aboutMe),
            heightCm: try? c.decodeIfPresent(Int.self, forKey: .heightCm),
            city: try? c.decodeIfPresent(String.self, forKey: .city),
            state: try? c.decodeIfPresent(String.self, forKey: .state),
            country: try? c.decodeIfPresent(String.self, forKey: .country),
            intent: ((try? c.decodeIfPresent(Intent.self, forKey: .intent)) ?? nil),
            isVerified: ((try? c.decodeIfPresent(Bool.self, forKey: .isVerified)) ?? nil) ?? false,
            profileCompleteness: ((try? c.decodeIfPresent(Int.self, forKey: .profileCompleteness)) ?? nil) ?? 0,
            photos: photos,
            education: try? c.decodeIfPresent(String.self, forKey: .education),
            occupation: try? c.decodeIfPresent(String.self, forKey: .occupation),
            company: try? c.decodeIfPresent(String.self, forKey: .company),
            religion: try? c.decodeIfPresent(String.self, forKey: .religion),
            smoking: try? c.decodeIfPresent(String.self, forKey: .smoking),
            drinking: try? c.decodeIfPresent(String.self, forKey: .drinking),
            exercise: try? c.decodeIfPresent(String.self, forKey: .exercise),
            sindhiFluency: ((try? c.decodeIfPresent(SindhiFluency.self, forKey: .sindhiFluency)) ?? nil),
            familyValues: ((try? c.decodeIfPresent(FamilyValues.self, forKey: .familyValues)) ?? nil),
            foodPreference: ((try? c.decodeIfPresent(FoodPreference.self, forKey: .foodPreference)) ?? nil),
            interests: ((try? c.decodeIfPresent([String].self, forKey: .interests)) ?? nil) ?? [],
            isOnline: ((try? c.decodeIfPresent(Bool.self, forKey: .isOnline)) ?? nil) ?? false,
            ageYears: ((try? c.decodeIfPresent(Int.self, forKey: .age)) ?? nil)
        )

        let score = ((try? c.decodeIfPresent(Int.self, forKey: .culturalScore)) ?? nil) ?? 0
        let badge = ((try? c.decodeIfPresent(CulturalBadge.self, forKey: .culturalBadge)) ?? nil)
            ?? (score >= 85 ? .gold : score >= 65 ? .green : score >= 40 ? .orange : CulturalBadge.none)
        self.culturalScore = CulturalScore(overallScore: score, badge: badge, dimensions: [])

        if let kundli = ((try? c.decodeIfPresent(Int.self, forKey: .kundliScore)) ?? nil),
           let tier = ((try? c.decodeIfPresent(KundliTier.self, forKey: .kundliTier)) ?? nil) {
            self.kundliScore = KundliScore(totalScore: kundli, tier: tier, gunas: [])
        } else {
            self.kundliScore = nil
        }

        self.commonInterests = ((try? c.decodeIfPresent(Int.self, forKey: .commonInterests)) ?? nil) ?? 0
        self.distanceKm = ((try? c.decodeIfPresent(Double.self, forKey: .distanceKm)) ?? nil)
        self.isExplore = ((try? c.decodeIfPresent(Bool.self, forKey: .isExplore)) ?? nil) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FlatKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(user.displayName, forKey: .displayName)
        try c.encode(culturalScore.overallScore, forKey: .culturalScore)
        try c.encode(culturalScore.badge, forKey: .culturalBadge)
        try c.encode(commonInterests, forKey: .commonInterests)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try c.encode(isExplore, forKey: .isExplore)
    }
}
