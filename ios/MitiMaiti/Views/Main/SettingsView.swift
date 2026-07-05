import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var localization: LocalizationManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.adaptiveColors) private var colors

    @State private var activePickerSheet: PickerSheetType?

    // GDPR export state
    @State private var isExporting = false
    @State private var exportFileUrl: URL?
    @State private var showExportShare = false

    /// Fetch the data export and hand the JSON file to the system share sheet.
    private func exportMyData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let data = try await APIService.shared.exportData()
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mitimaiti_data_export.json")
                try data.write(to: url)
                exportFileUrl = url
                showExportShare = true
            } catch APIError.rateLimited {
                vm.showToast("Export limit reached — try again in an hour")
            } catch {
                vm.showToast("Export failed. Check your connection.")
            }
            isExporting = false
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingMD) {
                    visibilitySection
                    discoverySection
                    communityCultureSection
                    lifestyleSection
                    notificationsSection
                    appearanceSection
                    accountSection
                    aboutSection
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.top, AppTheme.spacingSM)
            }
            .appBackground()

            // Toast overlay
            if let toast = vm.toastMessage {
                toastView(message: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.toastMessage)
                    .zIndex(100)
            }
        }
        .navigationTitle(localization.t("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileUrl {
                ShareSheet(activityItems: [url])
            }
        }
        .alert(localization.t("settings.logOutConfirm"), isPresented: $vm.showLogoutConfirmation) {
            Button(localization.t("settings.logOut"), role: .destructive) { authVM.logout() }
            Button(localization.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(localization.t("settings.logOutMessage"))
        }
        .sheet(isPresented: $vm.showDeleteSheet) {
            deleteAccountSheet
        }
        .sheet(item: $activePickerSheet) { sheetType in
            pickerSheetContent(for: sheetType)
        }
        .onAppear {
            switch themeManager.preference {
            case .light: vm.theme = .light
            case .dark: vm.theme = .dark
            case .system: vm.theme = .auto
            }
        }
        .onChange(of: vm.incognitoMode) { _, newValue in
            vm.showToast(newValue ? "Incognito on" : "Incognito off")
        }
        // Persist backend-backed discovery settings when they change.
        // Split into two ViewModifiers — 19 chained onChange calls in one
        // expression exceeded the Swift type-checker's time budget.
        .modifier(VisibilityPersistence(vm: vm))
        .modifier(FilterPersistence(vm: vm))
    }

    // MARK: - Toast

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
            .padding(.top, 8)
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        settingsSection(title: "VISIBILITY", icon: "eye.fill") {
            ToggleRow(title: localization.t("settings.showInDiscovery"), icon: "eye.fill", isOn: $vm.discoveryEnabled)
            ToggleRow(title: localization.t("settings.incognitoMode"), icon: "eye.slash.fill", isOn: $vm.incognitoMode)
            ToggleRow(title: localization.t("settings.displayFullName"), icon: "person.text.rectangle", isOn: $vm.showFullName)
            ToggleRow(title: localization.t("settings.snoozeProfile"), icon: "moon.zzz.fill", isOn: $vm.isSnoozed)
        }
    }

    // MARK: - Discovery Section (WHO I'M LOOKING FOR)

    private var discoverySection: some View {
        settingsSection(title: "WHO I'M LOOKING FOR", icon: "magnifyingglass") {
            showMeRow
            ageRangeRow
            ToggleRow(
                title: localization.t("settings.verifiedOnly"),
                icon: "checkmark.seal.fill",
                isOn: $vm.verifiedOnly
            )
        }
    }

    private var showMeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(AppTheme.rose)
                    .frame(width: 24)
                Text(localization.t("settings.showMe"))
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                Spacer()
            }

            Picker("Show Me", selection: $vm.genderPreference) {
                ForEach(ShowMe.allCases) { option in
                    Text(option.display).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var ageRangeRow: some View {
        VStack(spacing: 8) {
            ageRangeHeader
            ageRangeSliders
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var ageRangeHeader: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(AppTheme.rose)
                .frame(width: 24)
            Text(localization.t("settings.ageRange"))
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
            Spacer()
            Text("\(Int(vm.ageMin)) - \(Int(vm.ageMax))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.rose)
        }
    }

    private var ageRangeSliders: some View {
        VStack(spacing: 4) {
            HStack {
                Text(localization.t("settings.min"))
                    .font(.system(size: 11))
                    .foregroundColor(colors.textMuted)
                    .frame(width: 28)
                Slider(value: $vm.ageMin, in: 18...50, step: 1) { _ in
                    if vm.ageMin > vm.ageMax { vm.ageMax = vm.ageMin }
                }
                .tint(AppTheme.rose)
            }
            HStack {
                Text(localization.t("settings.max"))
                    .font(.system(size: 11))
                    .foregroundColor(colors.textMuted)
                    .frame(width: 28)
                Slider(value: $vm.ageMax, in: 18...50, step: 1) { _ in
                    if vm.ageMax < vm.ageMin { vm.ageMin = vm.ageMax }
                }
                .tint(AppTheme.rose)
            }
        }
    }

    // MARK: - Community & Culture Section

    private var communityCultureSection: some View {
        settingsSection(title: "COMMUNITY & CULTURE", icon: "globe.asia.australia.fill") {
            filterPickerRow(
                icon: "text.bubble.fill",
                title: "Sindhi Fluency",
                value: vm.fluencyFilter,
                sheetType: .fluency
            )
            filterPickerRow(
                icon: "person.3.sequence.fill",
                title: "Generation",
                value: vm.generationFilter,
                sheetType: .generation
            )
            filterPickerRow(
                icon: "building.columns.fill",
                title: "Religion",
                value: vm.religionFilter,
                sheetType: .religion
            )
            filterPickerRow(
                icon: "leaf.fill",
                title: "Gotra",
                value: vm.gotraFilter,
                sheetType: .gotra
            )
            filterPickerRow(
                icon: "fork.knife",
                title: "Dietary",
                value: vm.dietaryFilter,
                sheetType: .dietary
            )
        }
    }

    // MARK: - Lifestyle Section

    private var lifestyleSection: some View {
        settingsSection(title: "LIFESTYLE", icon: "heart.text.square.fill") {
            filterPickerRow(
                icon: "graduationcap.fill",
                title: "Education",
                value: vm.educationFilter,
                sheetType: .education
            )
            filterPickerRow(
                icon: "smoke.fill",
                title: "Smoking",
                value: vm.smokingFilter,
                sheetType: .smoking
            )
            filterPickerRow(
                icon: "wineglass.fill",
                title: "Drinking",
                value: vm.drinkingFilter,
                sheetType: .drinking
            )
            filterPickerRow(
                icon: "figure.2.and.child.holdinghands",
                title: "Family Plans",
                value: vm.familyPlansFilter,
                sheetType: .familyPlans
            )
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        settingsSection(title: "NOTIFICATIONS", icon: "bell.fill") {
            ToggleRow(
                title: localization.t("settings.matches"),
                icon: "heart.circle.fill",
                isOn: Binding(
                    get: { vm.notifyMatches },
                    set: { vm.notifyMatches = $0 }
                )
            )
            ToggleRow(
                title: localization.t("settings.messages"),
                icon: "message.fill",
                isOn: Binding(
                    get: { vm.notifyMessages },
                    set: { vm.notifyMessages = $0 }
                )
            )
            ToggleRow(
                title: localization.t("settings.likes"),
                icon: "heart.fill",
                isOn: Binding(
                    get: { vm.notifyLikes },
                    set: { vm.notifyLikes = $0 }
                )
            )
            ToggleRow(
                title: localization.t("settings.expiry"),
                icon: "clock.fill",
                isOn: Binding(
                    get: { vm.notifyExpiry },
                    set: { vm.notifyExpiry = $0 }
                )
            )
            ToggleRow(
                title: localization.t("settings.dailyPrompt"),
                icon: "sparkles",
                isOn: Binding(
                    get: { vm.notifyDailyPrompt },
                    set: { vm.notifyDailyPrompt = $0 }
                )
            )
            ToggleRow(
                title: localization.t("settings.newFeatures"),
                icon: "star.fill",
                isOn: Binding(
                    get: { vm.notifyNewFeatures },
                    set: { vm.notifyNewFeatures = $0 }
                )
            )
        }
    }

    // MARK: - Appearance Section (APP)

    private var appearanceSection: some View {
        settingsSection(title: "APP", icon: "paintbrush.fill") {
            themePickerRow
            languageRow
        }
    }

    private var themePickerRow: some View {
        HStack {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundColor(AppTheme.rose)
                .frame(width: 24)
            Text(localization.t("settings.theme"))
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { vm.theme },
                set: { newTheme in
                    vm.theme = newTheme
                    switch newTheme {
                    case .light: themeManager.preference = .light
                    case .dark: themeManager.preference = .dark
                    case .auto: themeManager.preference = .system
                    }
                    vm.showToast("Theme set to \(newTheme.display)")
                }
            )) {
                ForEach(SettingsViewModel.AppearanceTheme.allCases) { theme in
                    Label(theme.display, systemImage: theme.icon).tag(theme)
                }
            }
            .tint(AppTheme.rose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var languageRow: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundColor(AppTheme.rose)
                .frame(width: 24)
            Text(localization.t("settings.language"))
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
            Spacer()
            Picker("", selection: $localization.currentLanguage) {
                ForEach(Language.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .tint(AppTheme.rose)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        settingsSection(title: "ACCOUNT", icon: "person.crop.circle.fill") {
            NavigationLink {
                EditProfileView()
            } label: {
                settingsRow(icon: "pencil", title: localization.t("settings.editProfile"), color: AppTheme.rose)
            }

            NavigationLink {
                SignInMethodsView()
            } label: {
                settingsRow(icon: "key.fill", title: "Sign-in methods", color: AppTheme.rose)
            }

            // Export Data (GDPR) — downloads the JSON and opens the share sheet
            Button {
                exportMyData()
            } label: {
                settingsRow(
                    icon: "square.and.arrow.down",
                    title: isExporting ? "Preparing your data…" : "Export Data",
                    color: AppTheme.rose
                )
            }
            .disabled(isExporting)

            // Change Phone
            changePhoneRow

            Divider()
                .background(colors.borderSubtle)
                .padding(.horizontal, 16)

            accountDangerButtons
        }
    }

    private var changePhoneRow: some View {
        HStack {
            Image(systemName: "phone.fill")
                .foregroundColor(AppTheme.rose)
                .frame(width: 24)
            Text("Change Phone")
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
            Spacer()
            Text("+91 98XXX XXXXX")
                .font(.system(size: 13))
                .foregroundColor(colors.textMuted)
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(colors.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var accountDangerButtons: some View {
        VStack(spacing: 0) {
            Button { vm.showLogoutConfirmation = true } label: {
                settingsRow(icon: "rectangle.portrait.and.arrow.forward", title: localization.t("settings.logOut"), color: AppTheme.warning)
            }

            Button { vm.showDeleteSheet = true } label: {
                settingsRow(icon: "trash.fill", title: localization.t("settings.deleteAccount"), color: AppTheme.error)
            }
        }
    }

    // MARK: - Delete Account Sheet

    private var deleteAccountSheet: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 8)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.error)

            Text("Delete Account")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.textPrimary)

            Text("This action is permanent and cannot be undone. All your matches, messages, and profile data will be permanently deleted.")
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                SecondaryButton(title: "Keep Account") {
                    vm.showDeleteSheet = false
                }

                DangerButton(title: "Delete Account", icon: "trash.fill") {
                    vm.showDeleteSheet = false
                    // Delete server-side, then log out locally.
                    Task {
                        try? await APIService.shared.deleteAccount()
                        authVM.logout()
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        settingsSection(title: "ABOUT", icon: "info.circle.fill") {
            aboutRow(icon: "app.badge", title: localization.t("settings.appVersion"), detail: "2.0.0")
            NavigationLink { LegalView(page: .terms) } label: {
                settingsLinkRow(icon: "doc.text.fill", title: localization.t("settings.termsOfService"))
            }
            NavigationLink { LegalView(page: .privacy) } label: {
                settingsLinkRow(icon: "hand.raised.fill", title: localization.t("settings.privacyPolicy"))
            }
            NavigationLink { LegalView(page: .guidelines) } label: {
                settingsLinkRow(icon: "shield.lefthalf.filled", title: localization.t("settings.communityGuidelines"))
            }
        }
    }

    private func aboutRow(icon: String, title: String, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppTheme.rose)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(colors.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Filter Picker Row

    private func filterPickerRow(icon: String, title: String, value: String, sheetType: PickerSheetType) -> some View {
        Button {
            activePickerSheet = sheetType
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.rose)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(value == "Any" ? colors.textMuted : AppTheme.rose)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Picker Sheet Content

    @ViewBuilder
    private func pickerSheetContent(for type: PickerSheetType) -> some View {
        let (title, options, binding) = pickerData(for: type)
        NavigationStack {
            List {
                ForEach(options, id: \.self) { option in
                    Button {
                        binding.wrappedValue = option
                        activePickerSheet = nil
                        if option != "Any" {
                            vm.showToast("Filter updated")
                        }
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 16))
                                .foregroundColor(colors.textPrimary)
                            Spacer()
                            if binding.wrappedValue == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.rose)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        activePickerSheet = nil
                    }
                    .foregroundColor(AppTheme.rose)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func pickerData(for type: PickerSheetType) -> (String, [String], Binding<String>) {
        switch type {
        case .fluency:
            return ("Sindhi Fluency", SettingsViewModel.fluencyOptions, $vm.fluencyFilter)
        case .generation:
            return ("Generation", SettingsViewModel.generationOptions, $vm.generationFilter)
        case .religion:
            return ("Religion", SettingsViewModel.religionOptions, $vm.religionFilter)
        case .gotra:
            return ("Gotra", SettingsViewModel.gotraOptions, $vm.gotraFilter)
        case .dietary:
            return ("Dietary", SettingsViewModel.dietaryOptions, $vm.dietaryFilter)
        case .education:
            return ("Education", SettingsViewModel.educationOptions, $vm.educationFilter)
        case .smoking:
            return ("Smoking", SettingsViewModel.smokingOptions, $vm.smokingFilter)
        case .drinking:
            return ("Drinking", SettingsViewModel.drinkingOptions, $vm.drinkingFilter)
        case .familyPlans:
            return ("Family Plans", SettingsViewModel.familyPlansOptions, $vm.familyPlansFilter)
        }
    }

    // MARK: - Shared Helpers

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.rose)
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(colors.textMuted)
                        .tracking(1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

                content()
            }
            .padding(.bottom, 8)
        }
    }

    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(colors.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func settingsLinkRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppTheme.rose)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(colors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(colors.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Picker Sheet Type

enum PickerSheetType: String, Identifiable {
    case fluency, generation, religion, gotra, dietary
    case education, smoking, drinking, familyPlans

    var id: String { rawValue }
}

// MARK: - Persistence modifiers
// Split so no single expression carries 19 onChange handlers (type-check
// time-out in the Swift compiler).

private struct VisibilityPersistence: ViewModifier {
    @ObservedObject var vm: SettingsViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: vm.discoveryEnabled) { _, _ in vm.persistDiscoveryEnabled() }
            .onChange(of: vm.ageMin) { _, _ in vm.persistAgeRange() }
            .onChange(of: vm.ageMax) { _, _ in vm.persistAgeRange() }
            .onChange(of: vm.genderPreference) { _, _ in vm.persistGenderPreference() }
            .onChange(of: vm.incognitoMode) { _, _ in vm.persistIncognitoMode() }
            .onChange(of: vm.showFullName) { _, _ in vm.persistShowFullName() }
            .onChange(of: vm.isSnoozed) { _, _ in vm.persistSnoozed() }
            .onChange(of: vm.verifiedOnly) { _, _ in vm.persistVerifiedOnly() }
            .onChange(of: vm.heightMin) { _, _ in vm.persistHeightRange() }
            .onChange(of: vm.heightMax) { _, _ in vm.persistHeightRange() }
    }
}

private struct FilterPersistence: ViewModifier {
    @ObservedObject var vm: SettingsViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: vm.intentFilter) { _, _ in vm.persistIntentFilter() }
            .onChange(of: vm.religionFilter) { _, _ in vm.persistReligionFilter() }
            .onChange(of: vm.educationFilter) { _, _ in vm.persistEducationFilter() }
            .onChange(of: vm.smokingFilter) { _, _ in vm.persistSmokingFilter() }
            .onChange(of: vm.drinkingFilter) { _, _ in vm.persistDrinkingFilter() }
            .onChange(of: vm.fluencyFilter) { _, _ in vm.persistFluencyFilter() }
            .onChange(of: vm.gotraFilter) { _, _ in vm.persistGotraFilter() }
            .onChange(of: vm.dietaryFilter) { _, _ in vm.persistDietaryFilter() }
            .onChange(of: vm.generationFilter) { _, _ in vm.persistGenerationFilter() }
            .onChange(of: vm.familyPlansFilter) { _, _ in vm.persistFamilyPlansFilter() }
    }
}
