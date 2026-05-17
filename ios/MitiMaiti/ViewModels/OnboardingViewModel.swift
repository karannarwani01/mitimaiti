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
    @Published var isLoading = false
    @Published var error: String?

    // Tracks which selectedImages indices have already been uploaded so going
    // back-and-forth between steps doesn't re-upload the same photo.
    private var uploadedImageHashes: Set<Int> = []
    private let api = APIService.shared

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
        for (index, image) in selectedImages.enumerated() {
            let hash = image.hashValue
            if uploadedImageHashes.contains(hash) {
                continue
            }
            guard let data = image.jpegData(compressionQuality: 0.85) else {
                continue
            }
            do {
                _ = try await api.uploadPhoto(imageData: data)
                uploadedImageHashes.insert(hash)
            } catch {
                self.error = "Couldn't upload photo \(index + 1): \(error.localizedDescription)"
                isLoading = false
                return
            }
        }
        isLoading = false
        nextStep()
    }
}
