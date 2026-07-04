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
    static let gotraOptions = ["Any", "Exclude same gotra", "Lohana", "Bhatia", "Amil", "Sahiti", "Hyderabadi", "Shikarpuri", "Other"]
    static let dietaryOptions = ["Any", "Vegetarian", "Non-Vegetarian", "Vegan", "Jain"]
    static let educationOptions = ["Any", "Bachelors", "Masters", "PhD", "Professional", "Business Owner"]
    static let smokingOptions = ["Any", "Never", "Socially", "Regularly"]
    static let drinkingOptions = ["Any", "Never", "Socially", "Regularly"]
    // Must match the values EditProfile saves to basic_profiles.want_kids so
    // the feed's exact (case-insensitive) match works.
    static let familyPlansOptions = ["Any", "Want kids", "Don't want kids", "Open to kids", "Have kids"]

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
    // The discovery feed applies these, so persist each change to PATCH /me.
    // The backend upserts only the provided keys, so a single-field patch
    // never clobbers other settings. NSNull clears a filter.
    private let api = APIService.shared

    init() {
        Task { await loadSettings() }
    }

    /// Seed all settings from the server so the screen reflects what the
    /// backend will actually apply (defaults were previously hardcoded and
    /// could silently disagree with the saved preferences).
    func loadSettings() async {
        guard let s = try? await api.fetchSettings() else { return }
        if let v = s.discoveryEnabled { discoveryEnabled = v }
        if let v = s.incognitoMode { incognitoMode = v }
        if let v = s.showFullName { showFullName = v }
        if let v = s.isSnoozed { isSnoozed = v }
        if let v = s.ageMin { ageMin = Double(v) }
        if let v = s.ageMax { ageMax = Double(v) }
        if let v = s.heightMin { heightMin = Double(v) }
        if let v = s.heightMax { heightMax = Double(v) }
        if let v = s.genderPreference, let g = ShowMe(rawValue: v) { genderPreference = g }
        if let v = s.verifiedOnly { verifiedOnly = v }
        intentFilter = s.intentFilter.flatMap { Intent(rawValue: $0) }
        religionFilter = s.religionFilter ?? "Any"
        educationFilter = s.educationFilter ?? "Any"
        smokingFilter = s.smokingFilter ?? "Any"
        drinkingFilter = s.drinkingFilter ?? "Any"
        fluencyFilter = s.fluencyFilter.map { $0.capitalized } ?? "Any"
        gotraFilter = s.gotraFilter.map { $0 == "exclude_same" ? "Exclude same gotra" : $0 } ?? "Any"
        dietaryFilter = Self.dietaryDisplay(from: s.dietaryFilter) ?? "Any"
        generationFilter = s.generationFilter ?? "Any"
        familyPlansFilter = s.familyPlansFilter ?? "Any"
    }

    private func patchSettings(_ settings: [String: Any]) {
        Task { _ = try? await api.patchMe(["settings": settings]) }
    }

    /// "Any" → NSNull (clears the filter server-side), otherwise the value.
    private func filterValue(_ display: String, transform: (String) -> String = { $0 }) -> Any {
        display == "Any" ? NSNull() : transform(display)
    }

    private static func dietaryDisplay(from backend: String?) -> String? {
        switch backend {
        case "vegetarian": return "Vegetarian"
        case "non_vegetarian": return "Non-Vegetarian"
        case "vegan": return "Vegan"
        case "jain": return "Jain"
        case "eggetarian": return "Eggetarian"
        default: return nil
        }
    }

    func persistDiscoveryEnabled() {
        patchSettings(["discovery_enabled": discoveryEnabled])
    }

    func persistAgeRange() {
        patchSettings(["age_min": Int(ageMin), "age_max": Int(ageMax)])
    }

    func persistGenderPreference() {
        patchSettings(["gender_preference": genderPreference.rawValue])
    }

    func persistIncognitoMode() {
        patchSettings(["incognito_mode": incognitoMode])
    }

    func persistShowFullName() {
        patchSettings(["show_full_name": showFullName])
    }

    func persistSnoozed() {
        Task { _ = try? await api.patchMe(["user": ["is_snoozed": isSnoozed]]) }
    }

    func persistVerifiedOnly() {
        patchSettings(["verified_only": verifiedOnly])
    }

    func persistHeightRange() {
        patchSettings(["height_min": Int(heightMin), "height_max": Int(heightMax)])
    }

    func persistIntentFilter() {
        patchSettings(["intent_filter": intentFilter.map { $0.rawValue } ?? NSNull()])
    }

    func persistReligionFilter() {
        patchSettings(["religion_filter": filterValue(religionFilter)])
    }

    func persistEducationFilter() {
        patchSettings(["education_filter": filterValue(educationFilter)])
    }

    func persistSmokingFilter() {
        patchSettings(["smoking_filter": filterValue(smokingFilter)])
    }

    func persistDrinkingFilter() {
        patchSettings(["drinking_filter": filterValue(drinkingFilter)])
    }

    func persistFluencyFilter() {
        patchSettings(["fluency_filter": filterValue(fluencyFilter) { $0.lowercased() }])
    }

    func persistGotraFilter() {
        patchSettings(["gotra_filter": filterValue(gotraFilter) {
            $0 == "Exclude same gotra" ? "exclude_same" : $0
        }])
    }

    func persistDietaryFilter() {
        patchSettings(["dietary_filter": filterValue(dietaryFilter) {
            $0.lowercased().replacingOccurrences(of: "-", with: "_")
        }])
    }

    func persistGenerationFilter() {
        // Backend normalises on the leading digit, so "1st Gen" matches "1st".
        patchSettings(["generation_filter": filterValue(generationFilter)])
    }

    func persistFamilyPlansFilter() {
        patchSettings(["family_plans_filter": filterValue(familyPlansFilter)])
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
