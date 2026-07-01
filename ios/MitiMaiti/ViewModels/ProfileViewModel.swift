import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: User = {
        // Start with an empty user; real profile is loaded via loadProfile().
        // If the user set their name during onboarding, surface it immediately
        // so the UI doesn't flash an empty name before the network call returns.
        var u = User()
        let storedName = UserProfileStore.shared.firstName
        if !storedName.isEmpty { u.displayName = storedName }
        return u
    }()
    @Published var isLoading = false
    @Published var error: String?
    @Published var isSaving = false
    @Published var saveSuccess = false

    // Edit fields
    @Published var editBio = ""
    @Published var editHeight = ""
    @Published var editEducation = ""
    @Published var editOccupation = ""
    @Published var editCompany = ""
    @Published var editReligion = ""
    @Published var editSmoking = ""
    @Published var editDrinking = ""
    @Published var editExercise = ""
    @Published var editFluency: SindhiFluency = .fluent
    @Published var editFamilyValues: FamilyValues = .moderate
    @Published var editFoodPreference: FoodPreference = .vegetarian

    private let api = APIService.shared

    var profileStats: [(String, String, String)] {
        [
            ("eye.fill", "47", "Views"),
            ("heart.fill", "12", "Likes"),
            ("person.2.fill", "5", "Matches")
        ]
    }

    /// Computed profile completeness — reflects what's actually filled on the
    /// ProfileViewModel + the user's stored photos/prompts, rather than a
    /// static value on the User model. Recomputes whenever any @Published
    /// edit field changes (ObservableObject triggers view refresh).
    var computedCompleteness: Int {
        var filled = 0
        let total = 15 // photos + bio + 8 basics + prompts + 4 sindhi/identity

        // Photos
        if !user.photos.isEmpty { filled += 1 }
        // Prompts
        if !user.prompts.isEmpty { filled += 1 }
        // Bio
        if !editBio.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        // Basics (8)
        if !editHeight.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editEducation.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editOccupation.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editCompany.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editReligion.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editSmoking.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editDrinking.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        if !editExercise.trimmingCharacters(in: .whitespaces).isEmpty { filled += 1 }
        // Sindhi / Family identity (4)
        if user.sindhiFluency != nil { filled += 1 }
        if user.familyValues != nil { filled += 1 }
        if user.foodPreference != nil { filled += 1 }
        if !(user.gotra ?? "").isEmpty { filled += 1 }

        return Int((Double(filled) / Double(total)) * 100.0)
    }

    func loadProfile() {
        isLoading = true
        Task {
            do {
                var fetched = try await api.fetchProfile()
                let storedName = UserProfileStore.shared.firstName
                if !storedName.isEmpty { fetched.displayName = storedName }
                user = fetched
                populateEditFields()
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    func populateEditFields() {
        editBio = user.bio ?? ""
        editHeight = user.heightCm.map(String.init) ?? ""
        editEducation = user.education ?? ""
        editOccupation = user.occupation ?? ""
        editCompany = user.company ?? ""
        editReligion = user.religion ?? ""
        editSmoking = user.smoking ?? ""
        editDrinking = user.drinking ?? ""
        editExercise = user.exercise ?? ""
        editFluency = user.sindhiFluency ?? .fluent
        editFamilyValues = user.familyValues ?? .moderate
        editFoodPreference = user.foodPreference ?? .vegetarian
    }

    func saveProfile() {
        isSaving = true

        // Build the nested PATCH /me payload the backend expects (its schema is
        // .strict(), so only send allowed keys, grouped by section, omitting
        // blanks). Enum rawValues match the backend enums. smoking/drinking/
        // exercise have no PATCH schema home, so they are intentionally omitted.
        var basics: [String: Any] = [:]
        let bio = editBio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bio.isEmpty { basics["bio"] = bio }
        if let h = Int(editHeight.trimmingCharacters(in: .whitespaces)), (120...240).contains(h) {
            basics["height_cm"] = h
        }

        var userFields: [String: Any] = [:]
        let edu = editEducation.trimmingCharacters(in: .whitespaces)
        if !edu.isEmpty { userFields["education"] = edu }
        let occ = editOccupation.trimmingCharacters(in: .whitespaces)
        if !occ.isEmpty { userFields["occupation"] = occ }
        let comp = editCompany.trimmingCharacters(in: .whitespaces)
        if !comp.isEmpty { userFields["company"] = comp }
        let rel = editReligion.trimmingCharacters(in: .whitespaces)
        if !rel.isEmpty { userFields["religion"] = rel }

        var payload: [String: Any] = [
            "sindhi": ["sindhi_fluency": editFluency.rawValue],
            "chatti": [
                "family_values": editFamilyValues.rawValue,
                "food_preference": editFoodPreference.rawValue,
            ],
        ]
        if !basics.isEmpty { payload["basics"] = basics }
        if !userFields.isEmpty { payload["user"] = userFields }

        Task {
            do {
                _ = try await api.updateProfile(payload)
                isSaving = false
                saveSuccess = true

                try? await Task.sleep(nanoseconds: 2_000_000_000)
                saveSuccess = false
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }
}
