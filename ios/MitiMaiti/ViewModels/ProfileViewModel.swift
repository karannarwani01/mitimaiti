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

    // ── Voice intro (Hinge-style) ──
    @Published var isUploadingVoice = false

    func uploadVoiceIntro(audioData: Data) {
        isUploadingVoice = true
        Task {
            do {
                let url = try await api.uploadVoiceIntro(audioData: audioData)
                user.voiceIntroUrl = url
            } catch {
                self.error = "Voice intro upload failed"
            }
            isUploadingVoice = false
        }
    }

    func deleteVoiceIntro() {
        Task {
            try? await api.deleteVoiceIntro()
            user.voiceIntroUrl = nil
        }
    }

    // ── Selfie verification (pose challenge) ──
    @Published var isVerifying = false
    @Published var verifyMessage: String?
    /// The pose the server asked the user to copy; non-nil = show the
    /// challenge with a "Take selfie" button.
    @Published var verifyChallenge: APIService.VerifyChallenge?

    /// Step 1: fetch the random pose the user must copy.
    func startVerifyChallenge() {
        isVerifying = true
        Task {
            do {
                verifyChallenge = try await api.fetchVerifyChallenge()
            } catch {
                verifyMessage = "Couldn't start verification. Please try again."
            }
            isVerifying = false
        }
    }

    /// Step 2: upload the pose selfie for face verification.
    func verifySelfie(imageData: Data) {
        guard let pose = verifyChallenge else { return }
        isVerifying = true
        Task {
            do {
                let result = try await api.verifySelfie(imageData: imageData, poseId: pose.poseId)
                if result.verified {
                    user.isVerified = true
                    verifyChallenge = nil
                    verifyMessage = "You're verified! Your profile now shows the blue badge."
                } else {
                    verifyMessage = result.message
                }
            } catch APIError.rateLimited {
                verifyMessage = "You've used all 3 verification attempts for today. Try again tomorrow."
            } catch APIError.serverError(let msg) {
                verifyMessage = msg
            } catch {
                verifyMessage = "Verification failed. Check your connection and try again."
            }
            isVerifying = false
        }
    }

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
    // Optional: nil means "user never set this" — sending a default value for
    // an unset field would silently write fake cultural data to the profile
    // (and skew the cultural compatibility score).
    @Published var editFluency: SindhiFluency?
    @Published var editFamilyValues: FamilyValues?
    @Published var editFoodPreference: FoodPreference?

    private let api = APIService.shared

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

    // ── Daily question (Chai Chat) ──
    struct DailyPromptState {
        var question: String?
        var answer: String?
        var answeredToday: Bool
    }
    @Published var dailyPrompt: DailyPromptState?
    @Published var isSavingPromptAnswer = false

    func loadDailyPrompt() {
        Task {
            if let state = try? await api.fetchDailyPrompt() {
                dailyPrompt = DailyPromptState(
                    question: state.question,
                    answer: state.answer,
                    answeredToday: state.answeredToday
                )
            }
        }
    }

    func answerDailyPrompt(_ answer: String) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSavingPromptAnswer else { return }
        isSavingPromptAnswer = true
        Task {
            do {
                try await api.answerPrompt(trimmed)
                dailyPrompt = DailyPromptState(
                    question: dailyPrompt?.question,
                    answer: trimmed,
                    answeredToday: true
                )
            } catch {
                self.error = "Couldn't save your answer. Try again."
            }
            isSavingPromptAnswer = false
        }
    }

    func loadProfile() {
        isLoading = true
        loadDailyPrompt()
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
        editFluency = user.sindhiFluency
        editFamilyValues = user.familyValues
        editFoodPreference = user.foodPreference
    }

    func saveProfile() {
        isSaving = true

        // Build the nested PATCH /me payload the backend expects (its schema is
        // .strict(), so only send allowed keys, grouped by section, omitting
        // blanks). Enum rawValues match the backend enums.
        var basics: [String: Any] = [:]
        let bio = editBio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bio.isEmpty { basics["bio"] = bio }
        if let h = Int(editHeight.trimmingCharacters(in: .whitespaces)), (120...240).contains(h) {
            basics["height_cm"] = h
        }
        // EditProfileView applies its edits into `user` before calling save,
        // so `user` carries the freshest lifestyle values.
        if let v = user.smoking, !v.isEmpty { basics["smoking"] = v }
        else if !editSmoking.isEmpty { basics["smoking"] = editSmoking }
        if let v = user.drinking, !v.isEmpty { basics["drinking"] = v }
        else if !editDrinking.isEmpty { basics["drinking"] = editDrinking }
        if let v = user.exercise, !v.isEmpty { basics["exercise"] = v }
        else if !editExercise.isEmpty { basics["exercise"] = editExercise }
        if let v = user.wantKids, !v.isEmpty { basics["want_kids"] = v }
        if let v = user.settlingTimeline, !v.isEmpty { basics["settling"] = v }

        var userFields: [String: Any] = [:]
        let edu = editEducation.trimmingCharacters(in: .whitespaces)
        if !edu.isEmpty { userFields["education"] = edu }
        let occ = editOccupation.trimmingCharacters(in: .whitespaces)
        if !occ.isEmpty { userFields["occupation"] = occ }
        let comp = editCompany.trimmingCharacters(in: .whitespaces)
        if !comp.isEmpty { userFields["company"] = comp }
        let rel = editReligion.trimmingCharacters(in: .whitespaces)
        if !rel.isEmpty { userFields["religion"] = rel }

        var payload: [String: Any] = [:]

        // Only send cultural fields the user actually chose — defaults for
        // unset fields would fabricate profile data. EditProfileView applies
        // its edits into `user` before calling saveProfile, so `user` carries
        // the freshest values for the extended Sindhi/personality fields.
        var sindhi: [String: Any] = [:]
        if let fluency = editFluency ?? user.sindhiFluency { sindhi["sindhi_fluency"] = fluency.rawValue }
        if let v = user.motherTongue, !v.isEmpty { sindhi["mother_tongue"] = v }
        if let v = user.sindhiDialect, !v.isEmpty { sindhi["sindhi_dialect"] = v }
        if let v = user.communitySubGroup, !v.isEmpty { sindhi["community_sub_group"] = v }
        if let v = user.gotra, !v.isEmpty { sindhi["gotra"] = v }
        if let v = user.generation, !v.isEmpty { sindhi["generation"] = v }
        if let v = user.familyOriginCity, !v.isEmpty { sindhi["family_origin_city"] = v }
        if let v = user.familyOriginCountry, !v.isEmpty { sindhi["family_origin_country"] = v }
        if !sindhi.isEmpty { payload["sindhi"] = sindhi }

        var chatti: [String: Any] = [:]
        if let values = editFamilyValues ?? user.familyValues { chatti["family_values"] = values.rawValue }
        if let food = editFoodPreference ?? user.foodPreference { chatti["food_preference"] = food.rawValue }
        if let v = user.festivalsCelebrated, !v.isEmpty { chatti["festivals_celebrated"] = v }
        if let v = user.cuisinePreferences, !v.isEmpty { chatti["cuisine_preferences"] = v }
        if let v = user.culturalActivities, !v.isEmpty { chatti["cultural_activities"] = v }
        if !chatti.isEmpty { payload["chatti"] = chatti }

        var personality: [String: Any] = [:]
        if !user.interests.isEmpty { personality["interests"] = user.interests }
        if let v = user.musicPreferences, !v.isEmpty { personality["music_preferences"] = v }
        if let v = user.movieGenres, !v.isEmpty { personality["movie_genres"] = v }
        if let v = user.travelStyle, !v.isEmpty { personality["travel_style"] = v }
        if let v = user.languages, !v.isEmpty { personality["languages"] = v }
        // Always send prompts so removals persist (empty array clears them)
        personality["prompts"] = user.prompts.map { ["question": $0.question, "answer": $0.answer] }
        payload["personality"] = personality

        if !basics.isEmpty { payload["basics"] = basics }
        if !userFields.isEmpty { payload["user"] = userFields }
        guard !payload.isEmpty else {
            isSaving = false
            saveSuccess = true
            return
        }

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
