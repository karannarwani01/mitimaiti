import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    // Visibility
    @Published var discoveryEnabled = true
    @Published var incognitoMode = false
    @Published var showFullName = true
    @Published var isSnoozed = false

    // Discovery Filters
    @Published var ageMin: Double = 21
    @Published var ageMax: Double = 35
    @Published var heightMin: Double = 150
    @Published var heightMax: Double = 190
    @Published var genderPreference: ShowMe = .women
    @Published var intentFilter: Intent?
    @Published var verifiedOnly = false

    // Community & Culture Filters
    @Published var fluencyFilter: String = "Any"
    @Published var generationFilter: String = "Any"
    @Published var religionFilter: String = "Any"
    @Published var gotraFilter: String = "Any"
    @Published var dietaryFilter: String = "Any"

    // Lifestyle Filters
    @Published var educationFilter: String = "Any"
    @Published var smokingFilter: String = "Any"
    @Published var drinkingFilter: String = "Any"
    @Published var familyPlansFilter: String = "Any"

    // Filter options
    static let fluencyOptions = ["Any", "Fluent", "Conversational", "Basic", "Learning"]
    static let generationOptions = ["Any", "1st Gen", "2nd Gen", "3rd Gen", "4th Gen+"]
    static let religionOptions = ["Any", "Hindu Sindhi", "Muslim Sindhi", "Sikh Sindhi", "Other"]
    static let gotraOptions = ["Any", "Lohana", "Bhatia", "Amil", "Sahiti", "Hyderabadi", "Shikarpuri", "Other"]
    static let dietaryOptions = ["Any", "Vegetarian", "Non-Vegetarian", "Vegan", "Jain"]
    static let educationOptions = ["Any", "Bachelors", "Masters", "PhD", "Professional", "Business Owner"]
    static let smokingOptions = ["Any", "Never", "Occasionally", "Regularly"]
    static let drinkingOptions = ["Any", "Never", "Socially", "Regularly"]
    static let familyPlansOptions = ["Any", "Yes wants kids", "Maybe", "No"]

    // Notifications - backed by NotificationManager.shared.settings
    var notifyMatches: Bool {
        get { NotificationManager.shared.settings.matches }
        set {
            NotificationManager.shared.settings.matches = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifyMessages: Bool {
        get { NotificationManager.shared.settings.messages }
        set {
            NotificationManager.shared.settings.messages = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifyLikes: Bool {
        get { NotificationManager.shared.settings.likes }
        set {
            NotificationManager.shared.settings.likes = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifyFamily: Bool {
        get { NotificationManager.shared.settings.family }
        set {
            NotificationManager.shared.settings.family = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifyExpiry: Bool {
        get { NotificationManager.shared.settings.expiry }
        set {
            NotificationManager.shared.settings.expiry = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifyDailyPrompt: Bool {
        get { NotificationManager.shared.settings.dailyPrompt }
        set {
            NotificationManager.shared.settings.dailyPrompt = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifyNewFeatures: Bool {
        get { NotificationManager.shared.settings.newFeatures }
        set {
            NotificationManager.shared.settings.newFeatures = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }
    var notifySafety: Bool {
        get { NotificationManager.shared.settings.safety }
        set {
            NotificationManager.shared.settings.safety = newValue
            NotificationManager.shared.saveSettings()
            objectWillChange.send()
        }
    }

    // Appearance
    @Published var theme: AppearanceTheme = .auto

    // Account
    @Published var showDeleteConfirmation = false
    @Published var showLogoutConfirmation = false
    @Published var showDeleteSheet = false

    // Toast
    @Published var toastMessage: String?

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    // ── Backend-backed settings ──
    // The discovery feed applies these (discoverable/age/gender), so persist each
    // change to PATCH /me. The backend upserts only the provided keys, so a
    // single-field patch never clobbers other settings.
    private let api = APIService.shared

    func persistDiscoveryEnabled() {
        Task { _ = try? await api.updateProfile(["settings": ["discovery_enabled": discoveryEnabled]]) }
    }

    func persistAgeRange() {
        Task { _ = try? await api.updateProfile(["settings": ["age_min": Int(ageMin), "age_max": Int(ageMax)]]) }
    }

    func persistGenderPreference() {
        Task { _ = try? await api.updateProfile(["settings": ["gender_preference": genderPreference.rawValue]]) }
    }

    enum AppearanceTheme: String, CaseIterable, Identifiable {
        case light, dark, auto
        var id: String { rawValue }
        var display: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .auto: return "circle.lefthalf.filled"
            }
        }
    }
}
