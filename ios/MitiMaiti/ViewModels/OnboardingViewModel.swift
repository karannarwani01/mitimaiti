import SwiftUI
import PhotosUI

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .name
    @Published var firstName = UserProfileStore.shared.firstName {
        didSet { UserProfileStore.shared.firstName = firstName }
    }
    @Published var isNonSindhi = false
    @Published var birthDay = 15
    @Published var birthMonth = 6
    @Published var birthYear = 1998
    @Published var selectedGender: Gender?
    @Published var selectedPhotos: [String] = []
    @Published var selectedImages: [UIImage] = []
    @Published var selectedIntent: Intent?
    @Published var selectedShowMe: ShowMe?
    @Published var selectedCity: String?
    @Published var selectedRegion: String?
    @Published var selectedCountry: String?
    @Published var isLoading = false
    @Published var error: String?

    // Tracks which selectedImages indices have already been uploaded so going
    // back-and-forth between steps doesn't re-upload the same photo.
    private var uploadedImageHashes: Set<Int> = []
    private let api = APIService.shared

    init() {
        // No local name (e.g. phone-OTP signup) — the server may still know one
        // (backfilled from a Google/Apple link). Fetch and prefill, but never
        // clobber anything the user has started typing.
        if firstName.isEmpty {
            Task { [weak self] in
                guard let user = try? await APIService.shared.fetchProfile() else { return }
                guard let self, self.firstName.isEmpty, !user.displayName.isEmpty else { return }
                self.firstName = user.displayName
            }
        }
    }

    var age: Int {
        let components = DateComponents(year: birthYear, month: birthMonth, day: birthDay)
        guard let dob = Calendar.current.date(from: components) else { return 0 }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }

    var isAgeValid: Bool {
        age >= 18
    }

    var progress: Double {
        Double(currentStep.rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    var canProceed: Bool {
        switch currentStep {
        case .name: return firstName.count >= 2
        case .birthday: return isAgeValid
        case .gender: return selectedGender != nil
        case .photos: return selectedImages.count >= 1
        case .intent: return selectedIntent != nil
        case .showMe: return selectedShowMe != nil
        case .location: return selectedCity != nil
        case .ready: return true
        }
    }

    func nextStep() {
        guard canProceed else { return }
        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = next
            }
        }
    }

    func previousStep() {
        if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = prev
            }
        }
    }

    func addPhoto() {
        if selectedPhotos.count < 6 {
            selectedPhotos.append("photo_\(selectedPhotos.count + 1)")
        }
    }

    func addImage(_ image: UIImage) {
        guard selectedImages.count < 6 else { return }
        let newIndex = selectedImages.count
        selectedImages.append(image)
        selectedPhotos.append("photo_\(selectedPhotos.count + 1)")
        // Persist every photo; index 0 is the primary/avatar
        UserImageStore.shared.save(image, at: newIndex)
    }

    func removePhoto(at index: Int) {
        guard index < selectedPhotos.count else { return }
        selectedPhotos.remove(at: index)
        if index < selectedImages.count {
            selectedImages.remove(at: index)
        }
        // Keep the store in sync with the current selection
        UserImageStore.shared.setAll(selectedImages)
    }

    /// Upload every photo in selectedImages that we haven't already pushed
    /// to the backend, then advance to the next step. Called from the
    /// Continue button on the photos step so the .ready / Discover screens
    /// see the photos on the user's actual profile.
    func proceedFromPhotos() async {
        guard canProceed else { return }
        isLoading = true
        error = nil

        // Reconcile with the server first. Re-running onboarding or resuming
        // must not blindly append past the 6-photo cap — find how many photos
        // the account already has and only upload enough net-new ones to fill.
        let maxPhotos = 6
        var serverPhotoCount = 0
        if let profile = try? await api.fetchProfile() {
            serverPhotoCount = profile.photos.count
        }
        var remainingSlots = max(0, maxPhotos - serverPhotoCount)
        var uploadedThisPass = false

        for (index, image) in selectedImages.enumerated() {
            let hash = image.hashValue
            if uploadedImageHashes.contains(hash) { continue }
            // Account already at capacity (e.g. photos from a prior run) —
            // nothing more to upload, the requirement is already met.
            if remainingSlots <= 0 { break }
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                continue
            }
            do {
                _ = try await api.uploadPhoto(imageData: data)
                uploadedImageHashes.insert(hash)
                remainingSlots -= 1
                uploadedThisPass = true
            } catch APIError.photoLimitReached {
                // Server says we're already at the limit — not an onboarding
                // failure; the user has enough photos. Stop trying to add more.
                break
            } catch {
                self.error =
                    "Couldn't upload photo \(index + 1): \(error.localizedDescription)"
                isLoading = false
                return
            }
        }

        // Onboarding only needs the account to end up with at least one photo.
        if serverPhotoCount == 0 && !uploadedThisPass && uploadedImageHashes.isEmpty {
            self.error = "Please add at least one photo to continue."
            isLoading = false
            return
        }

        isLoading = false
        nextStep()
    }

    /// Persist every onboarding-collected field to the backend in one
    /// PATCH /me. Photos are uploaded earlier (proceedFromPhotos); this
    /// covers the rest, which until now never left the device. Called once
    /// from the final screen. Returns the backend-recalculated completeness,
    /// or nil if nothing to send / the request failed.
    func submitProfile() async -> Int? {
        var basics: [String: Any] = [:]
        let name = firstName.trimmingCharacters(in: .whitespaces)
        if name.count >= 2 { basics["display_name"] = name }
        basics["date_of_birth"] = String(
            format: "%04d-%02d-%02d", birthYear, birthMonth, birthDay
        )
        if let g = selectedGender { basics["gender"] = g.rawValue }
        if let city = selectedCity?.trimmingCharacters(in: .whitespaces),
           !city.isEmpty {
            basics["city"] = city
        }
        if let st = selectedRegion?.trimmingCharacters(in: .whitespaces),
           !st.isEmpty {
            basics["state"] = st
        }
        if let co = selectedCountry?.trimmingCharacters(in: .whitespaces),
           !co.isEmpty {
            basics["country"] = co
        }

        var userFields: [String: Any] = [:]
        if let intent = selectedIntent { userFields["intent"] = intent.rawValue }

        var settings: [String: Any] = [:]
        if let show = selectedShowMe {
            settings["gender_preference"] = show.rawValue
        }

        var payload: [String: Any] = [:]
        if !basics.isEmpty { payload["basics"] = basics }
        if !userFields.isEmpty { payload["user"] = userFields }
        if !settings.isEmpty { payload["settings"] = settings }
        guard !payload.isEmpty else { return nil }

        do {
            return try await api.patchMe(payload)
        } catch {
            self.error = "Couldn't save your profile: \(error.localizedDescription)"
            return nil
        }
    }
}
