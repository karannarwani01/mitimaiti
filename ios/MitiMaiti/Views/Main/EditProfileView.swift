import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors

    // MARK: - Tab selection
    @State private var selectedTab: EditProfileTab = .basics
    @Namespace private var tabAnimation

    enum EditProfileTab: String, CaseIterable {
        case basics = "Basics"
        case sindhi = "Sindhi"
        case cultural = "Cultural"
        case personality = "Personality"
        case photos = "Photos"

        var icon: String {
            switch self {
            case .basics: return "person.fill"
            case .sindhi: return "globe.asia.australia.fill"
            case .cultural: return "star.fill"
            case .personality: return "paintpalette.fill"
            case .photos: return "photo.on.rectangle.angled"
            }
        }
    }

    // MARK: - Edit state (local copies)
    @State private var editName: String = ""
    @State private var editBio: String = ""
    @State private var editDateOfBirth: Date = Date.fromAge(25)
    @State private var editHeight: Int = 170
    @State private var editEducation: String = ""
    @State private var editOccupation: String = ""
    @State private var editCompany: String = ""
    @State private var editReligion: String = ""
    @State private var editSmoking: String = ""
    @State private var editDrinking: String = ""
    @State private var editExercise: String = ""
    @State private var editWantKids: String = ""
    @State private var editSettlingTimeline: String = ""

    @State private var editFluency: SindhiFluency = .fluent
    @State private var editDialect: String = ""
    @State private var editGotra: String = ""
    @State private var editGeneration: String = ""
    @State private var editMotherTongue: String = ""
    @State private var editCommunitySubGroup: String = ""
    @State private var editFamilyOriginCity: String = ""
    @State private var editFamilyOriginCountry: String = ""

    @State private var editFamilyValues: FamilyValues = .moderate
    @State private var editFoodPreference: FoodPreference = .vegetarian
    @State private var editFestivals: [String] = []
    @State private var editCuisines: [String] = []
    @State private var editCulturalActivities: [String] = []

    @State private var editInterests: [String] = []
    @State private var editMusic: [String] = []
    @State private var editMovies: [String] = []
    @State private var editLanguages: [String] = []
    @State private var editTravelStyle: String = ""

    // MARK: - Prompts state
    @State private var editPrompts: [UserPrompt] = []
    @State private var showAddPrompt: Bool = false
    @State private var selectedPromptQuestion: String = "A life goal of mine"
    @State private var promptAnswer: String = ""

    // MARK: - Photos state
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker: Bool = false
    @ObservedObject private var imageStore = UserImageStore.shared

    // MARK: - Save toast
    @State private var showSaveToast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingSM) {
                    selectedTabContent
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.top, AppTheme.spacingSM)
            }
        }
        .appBackground()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
                    .foregroundColor(colors.textSecondary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    applyEditsToViewModel()
                    profileVM.saveProfile()
                } label: {
                    Text("Save")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.rose)
                }
                .disabled(profileVM.isSaving)
            }
        }
        .overlay(alignment: .bottom) {
            if profileVM.saveSuccess {
                saveSuccessBanner
            }
        }
        .overlay(alignment: .top) {
            if showSaveToast {
                Text("Saved")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(AppTheme.success)
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showAddPrompt) {
            addPromptSheet
        }
        .onChange(of: editName) { _ in flashSaveToast() }
        .onChange(of: editBio) { _ in flashSaveToast() }
        .onChange(of: editHeight) { _ in flashSaveToast() }
        .onChange(of: editSmoking) { _ in flashSaveToast() }
        .onChange(of: editDrinking) { _ in flashSaveToast() }
        .onChange(of: editExercise) { _ in flashSaveToast() }
        .onChange(of: editWantKids) { _ in flashSaveToast() }
        .onChange(of: editSettlingTimeline) { _ in flashSaveToast() }
        .onChange(of: editInterests) { _ in flashSaveToast() }
        .onChange(of: editPrompts) { _ in flashSaveToast() }
        .onChange(of: editGeneration) { _ in flashSaveToast() }
        .onChange(of: editFamilyOriginCountry) { _ in flashSaveToast() }
        .onAppear { populateFromUser() }
    }

    // MARK: - Save Success Banner

    private var saveSuccessBanner: some View {
        Text("Profile Saved!")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(AppTheme.success)
            .clipShape(Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 80)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EditProfileTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .white : colors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(AppTheme.roseGradient)
                                        .matchedGeometryEffect(id: "tabIndicator", in: tabAnimation)
                                } else {
                                    Capsule()
                                        .fill(colors.surfaceMedium)
                                        .overlay(
                                            Capsule()
                                                .stroke(colors.borderSubtle, lineWidth: 0.5)
                                        )
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacingMD)
            .padding(.vertical, 10)
        }
        .background(colors.surfaceDark)
    }

    // MARK: - Selected Tab Content

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .basics:
            basicsSection
        case .sindhi:
            sindhiSection
        case .cultural:
            culturalSection
        case .personality:
            personalitySection
        case .photos:
            photosSection
        }
    }

    // MARK: - Section 1: Basics

    private var basicsSection: some View {
        ContentCard {
            VStack(spacing: AppTheme.spacingSM) {
                basicsNameBio
                basicsDateHeight
                basicsWorkFields
                lifestylePickers
            }
            .padding(AppTheme.spacingMD)
        }
    }

    private var basicsNameBio: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Display Name", icon: "person.fill") {
                AppTextField(placeholder: "Your name", text: $editName, icon: "person")
            }
            editField(label: "Bio", icon: "text.quote") {
                bioTextEditor
            }
        }
    }

    private var bioTextEditor: some View {
        ZStack(alignment: .topLeading) {
            if editBio.isEmpty {
                Text("Tell others about yourself...")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
            }
            TextEditor(text: $editBio)
                .font(.system(size: 14))
                .foregroundColor(colors.textPrimary)
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(colors.borderSubtle, lineWidth: 0.5)
                )
        )
    }

    private var basicsDateHeight: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Date of Birth", icon: "calendar") {
                DatePicker(
                    "Birthday",
                    selection: $editDateOfBirth,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(AppTheme.rose)
                .colorScheme(.dark)
            }
            editField(label: "Height (cm)", icon: "ruler") {
                Stepper(value: $editHeight, in: 120...220) {
                    Text("\(editHeight) cm")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                }
                .tint(AppTheme.rose)
            }
        }
    }

    private var basicsWorkFields: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Education", icon: "graduationcap.fill") {
                AppTextField(placeholder: "e.g. B.Tech, IIT", text: $editEducation, icon: "graduationcap")
            }
            editField(label: "Occupation", icon: "briefcase.fill") {
                AppTextField(placeholder: "Job title", text: $editOccupation, icon: "briefcase")
            }
            editField(label: "Company", icon: "building.2.fill") {
                AppTextField(placeholder: "Company name", text: $editCompany, icon: "building.2")
            }
            editField(label: "Religion", icon: "sparkles") {
                AppTextField(placeholder: "e.g. Hindu", text: $editReligion, icon: "sparkles")
            }
        }
    }

    private var lifestylePickers: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Smoking", icon: "smoke.fill") {
                menuPicker(
                    selection: $editSmoking,
                    options: ["", "Never", "Socially", "Regularly"],
                    labels: ["Select", "Never", "Socially", "Regularly"]
                )
            }
            editField(label: "Drinking", icon: "wineglass.fill") {
                menuPicker(
                    selection: $editDrinking,
                    options: ["", "Never", "Socially", "Regularly"],
                    labels: ["Select", "Never", "Socially", "Regularly"]
                )
            }
            editField(label: "Exercise", icon: "figure.run") {
                menuPicker(
                    selection: $editExercise,
                    options: ["", "Never", "Sometimes", "Often", "Daily"],
                    labels: ["Select", "Never", "Sometimes", "Often", "Daily"]
                )
            }
            editField(label: "Want Kids", icon: "figure.and.child.holdinghands") {
                menuPicker(
                    selection: $editWantKids,
                    options: ["", "Want someday", "Don't want", "Have & want more", "Have & done", "Open to it"],
                    labels: ["Select", "Want someday", "Don't want", "Have & want more", "Have & done", "Open to it"]
                )
            }
            editField(label: "Settling Timeline", icon: "calendar.badge.clock") {
                menuPicker(
                    selection: $editSettlingTimeline,
                    options: ["", "ASAP", "1-2 years", "3-5 years", "Not sure"],
                    labels: ["Select", "ASAP", "1-2 years", "3-5 years", "Not sure"]
                )
            }
        }
    }

    // MARK: - Section 2: Sindhi Identity

    private var sindhiSection: some View {
        ContentCard {
            VStack(spacing: AppTheme.spacingSM) {
                sindhiFluencyField
                sindhiTextFields
            }
            .padding(AppTheme.spacingMD)
        }
    }

    private var sindhiFluencyField: some View {
        editField(label: "Sindhi Fluency", icon: "text.bubble.fill") {
            fluencyPicker
        }
    }

    private var sindhiTextFields: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Sindhi Dialect", icon: "waveform") {
                AppTextField(placeholder: "e.g. Kutchi, Hyderabadi", text: $editDialect, icon: "waveform")
            }
            editField(label: "Gotra", icon: "leaf.fill") {
                AppTextField(placeholder: "e.g. Advani", text: $editGotra, icon: "leaf")
            }
            editField(label: "Generation", icon: "clock.arrow.circlepath") {
                menuPicker(
                    selection: $editGeneration,
                    options: ["", "Sindhi-born", "2nd Generation", "3rd Generation", "Mixed heritage"],
                    labels: ["Select", "Sindhi-born", "2nd Generation", "3rd Generation", "Mixed heritage"]
                )
            }
            editField(label: "Mother Tongue", icon: "character.bubble.fill") {
                AppTextField(placeholder: "e.g. Sindhi", text: $editMotherTongue)
            }
            editField(label: "Community Sub-Group", icon: "person.3.fill") {
                AppTextField(placeholder: "e.g. Bhaibund, Amil", text: $editCommunitySubGroup)
            }
            editField(label: "Family Origin City", icon: "mappin.circle.fill") {
                AppTextField(placeholder: "Ancestral city", text: $editFamilyOriginCity, icon: "mappin")
            }
            editField(label: "Family Origin Country", icon: "globe.americas.fill") {
                AppTextField(placeholder: "e.g. India, Pakistan", text: $editFamilyOriginCountry, icon: "globe")
            }
        }
    }

    private var fluencyPicker: some View {
        Picker("Fluency", selection: $editFluency) {
            ForEach(SindhiFluency.allCases) { level in
                Text(level.display).tag(level)
            }
        }
        .pickerStyle(.menu)
        .tint(AppTheme.rose)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(colors.borderSubtle, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Section 3: Cultural

    private var culturalSection: some View {
        ContentCard {
            VStack(spacing: AppTheme.spacingSM) {
                culturalPickerFields
                culturalChipFields
            }
            .padding(AppTheme.spacingMD)
        }
    }

    private var culturalPickerFields: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Family Values", icon: "house.fill") {
                familyValuesPicker
            }
            editField(label: "Food Preference", icon: "fork.knife") {
                foodPreferencePicker
            }
        }
    }

    private var culturalChipFields: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Festivals Celebrated", icon: "party.popper.fill") {
                multiSelectChips(selected: $editFestivals, options: festivalOptions)
            }
            editField(label: "Cuisine Preferences", icon: "frying.pan.fill") {
                multiSelectChips(selected: $editCuisines, options: cuisineOptions)
            }
            editField(label: "Cultural Activities", icon: "theatermasks.fill") {
                multiSelectChips(selected: $editCulturalActivities, options: culturalActivityOptions)
            }
        }
    }

    private var familyValuesPicker: some View {
        Picker("Family Values", selection: $editFamilyValues) {
            ForEach(FamilyValues.allCases) { value in
                Text(value.display).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }

    private var foodPreferencePicker: some View {
        Picker("Food Preference", selection: $editFoodPreference) {
            ForEach(FoodPreference.allCases) { pref in
                Text(pref.display).tag(pref)
            }
        }
        .pickerStyle(.menu)
        .tint(AppTheme.rose)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(colors.borderSubtle, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Section 4: Personality

    private var personalitySection: some View {
        VStack(spacing: AppTheme.spacingSM) {
            ContentCard {
                VStack(spacing: AppTheme.spacingSM) {
                    personalityChipFields
                    personalityTextFields
                }
                .padding(AppTheme.spacingMD)
            }
            ContentCard {
                promptsSection
                    .padding(AppTheme.spacingMD)
            }
        }
    }

    private var personalityChipFields: some View {
        VStack(spacing: AppTheme.spacingSM) {
            editField(label: "Interests", icon: "heart.fill") {
                multiSelectChips(selected: $editInterests, options: interestOptions)
            }
            editField(label: "Music Preferences", icon: "music.note") {
                multiSelectChips(selected: $editMusic, options: musicOptions)
            }
            editField(label: "Movie Genres", icon: "film") {
                multiSelectChips(selected: $editMovies, options: movieGenreOptions)
            }
            editField(label: "Languages", icon: "globe") {
                multiSelectChips(selected: $editLanguages, options: languageOptions)
            }
        }
    }

    private var personalityTextFields: some View {
        editField(label: "Travel Style", icon: "airplane") {
            AppTextField(placeholder: "e.g. Adventure, Luxury", text: $editTravelStyle, icon: "airplane")
        }
    }

    // MARK: - Prompts Section

    private var promptQuestionOptions: [String] {
        [
            "A life goal of mine",
            "The way to my heart is",
            "My Sindhi superpower",
            "My simple pleasures",
            "I geek out on",
            "My most controversial opinion",
            "Together we could",
            "I am convinced that",
            "My non-negotiable",
            "My typical Sunday",
            "The best way to ask me out",
            "I am looking for",
            "We will get along if",
            "I want someone who",
            "My idea of a perfect day"
        ]
    }

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.rose)
                Text("Prompts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }

            ForEach(editPrompts) { prompt in
                promptCard(prompt: prompt)
            }

            if editPrompts.count < 3 {
                Button {
                    selectedPromptQuestion = availablePromptQuestions.first ?? "A life goal of mine"
                    promptAnswer = ""
                    showAddPrompt = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("Add Prompt")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(AppTheme.rose)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                            .fill(AppTheme.rose.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                                    .stroke(AppTheme.rose.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            )
                    )
                }
            }
        }
    }

    private var availablePromptQuestions: [String] {
        let usedQuestions = Set(editPrompts.map { $0.question })
        return promptQuestionOptions.filter { !usedQuestions.contains($0) }
    }

    private func promptCard(prompt: UserPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(prompt.question.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.rose)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editPrompts.removeAll { $0.id == prompt.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.error)
                }
            }
            Text(prompt.answer)
                .font(.system(size: 14))
                .foregroundColor(colors.textPrimary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(colors.borderSubtle, lineWidth: 0.5)
                )
        )
    }

    private var addPromptSheet: some View {
        NavigationView {
            VStack(spacing: AppTheme.spacingMD) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a prompt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                    Picker("Prompt", selection: $selectedPromptQuestion) {
                        ForEach(availablePromptQuestions, id: \.self) { q in
                            Text(q).tag(q)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.rose)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                            .fill(colors.surfaceMedium)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                                    .stroke(colors.borderSubtle, lineWidth: 0.5)
                            )
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your answer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                    ZStack(alignment: .topLeading) {
                        if promptAnswer.isEmpty {
                            Text("Write your answer...")
                                .font(.system(size: 14))
                                .foregroundColor(colors.textMuted)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 20)
                        }
                        TextEditor(text: $promptAnswer)
                            .font(.system(size: 14))
                            .foregroundColor(colors.textPrimary)
                            .frame(height: 120)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .onChange(of: promptAnswer) { newValue in
                                if newValue.count > 200 {
                                    promptAnswer = String(newValue.prefix(200))
                                }
                            }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                            .fill(colors.surfaceMedium)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                                    .stroke(colors.borderSubtle, lineWidth: 0.5)
                            )
                    )
                    HStack {
                        Spacer()
                        Text("\(promptAnswer.count)/200")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(promptAnswer.count >= 200 ? AppTheme.error : colors.textMuted)
                    }
                }

                Spacer()
            }
            .padding(AppTheme.spacingMD)
            .appBackground()
            .navigationTitle("Add Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showAddPrompt = false
                    }
                    .foregroundColor(colors.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let newPrompt = UserPrompt(
                            question: selectedPromptQuestion,
                            answer: promptAnswer
                        )
                        withAnimation {
                            editPrompts.append(newPrompt)
                        }
                        showAddPrompt = false
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.rose)
                    .disabled(promptAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Section 5: Photos

    private var photosSection: some View {
        ContentCard {
            photosGrid
                .padding(AppTheme.spacingMD)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: max(0, 6 - profileVM.user.photos.count),
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        let sortOrder = profileVM.user.photos.count
                        let compressed = uiImage.compressedForUpload() ?? data
                        UserImageStore.shared.save(uiImage, at: sortOrder)

                        do {
                            let uploaded = try await APIService.shared.uploadPhoto(imageData: compressed)
                            profileVM.user.photos.append(uploaded)
                        } catch {
                            ToastManager.shared.show("Upload failed: \(error.localizedDescription)")
                        }
                    }
                }
                selectedPhotoItems = []
                flashSaveToast()
            }
        }
    }

    private var photosGrid: some View {
        let totalSlots = 6
        let columns = photoColumns
        return LazyVGrid(columns: columns, spacing: AppTheme.spacingSM) {
            ForEach(Array(profileVM.user.photos.enumerated()), id: \.element.id) { index, photo in
                photoSlot(photo: photo, index: index)
            }
            ForEach(0..<max(0, totalSlots - profileVM.user.photos.count), id: \.self) { _ in
                addPhotoSlot
            }
        }
    }

    private var photoColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.spacingSM),
            GridItem(.flexible(), spacing: AppTheme.spacingSM),
            GridItem(.flexible(), spacing: AppTheme.spacingSM)
        ]
    }

    private func photoSlot(photo: UserPhoto, index: Int) -> some View {
        // Resolve the stored image for this slot using sortOrder as the index key
        let storedImage: UIImage? = {
            let idx = photo.sortOrder
            guard idx < imageStore.photos.count else { return nil }
            return imageStore.photos[idx]
        }()

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceMedium)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(
                    Group {
                        if let img = storedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .clipped()
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(colors.textMuted)
                            }
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(
                            index == 0
                                ? AppTheme.gold
                                : colors.border,
                            lineWidth: index == 0 ? 2 : 0.5
                        )
                )
                .overlay(alignment: .bottom) {
                    if index == 0 {
                        Text("MAIN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(AppTheme.goldGradient)
                            .clipShape(Capsule())
                            .padding(.bottom, 6)
                    } else if storedImage != nil {
                        // "Set as Main" tap target — only on non-primary occupied slots
                        Button {
                            setAsPrimary(photoIndex: index)
                        } label: {
                            Text("Set as Main")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppTheme.gold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.55))
                                        .overlay(
                                            Capsule()
                                                .stroke(AppTheme.gold.opacity(0.6), lineWidth: 0.5)
                                        )
                                )
                        }
                        .padding(.bottom, 6)
                    }
                }

            Button {
                // Remove from store using the sortOrder index before mutating the array
                UserImageStore.shared.remove(at: photo.sortOrder)
                profileVM.user.photos.removeAll { $0.id == photo.id }
                // Re-number sortOrders and isPrimary so they stay contiguous
                for i in profileVM.user.photos.indices {
                    profileVM.user.photos[i].sortOrder = i
                    profileVM.user.photos[i].isPrimary = (i == 0)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.error)
                    .background(
                        Circle()
                            .fill(colors.background)
                            .frame(width: 18, height: 18)
                    )
            }
            .offset(x: 6, y: -6)
        }
    }

    /// Promote the photo at `photoIndex` to position 0 (primary).
    private func setAsPrimary(photoIndex: Int) {
        guard photoIndex > 0, photoIndex < profileVM.user.photos.count else { return }
        // Move in the image store (handles disk persistence)
        UserImageStore.shared.setPrimary(at: photoIndex)
        // Mirror the reorder in the user's photo model array
        var photos = profileVM.user.photos
        let promoted = photos.remove(at: photoIndex)
        photos.insert(promoted, at: 0)
        // Re-assign sortOrders and isPrimary flags
        for i in photos.indices {
            photos[i].sortOrder = i
            photos[i].isPrimary = (i == 0)
        }
        profileVM.user.photos = photos
        flashSaveToast()
    }

    private var addPhotoSlot: some View {
        Button {
            showPhotoPicker = true
        } label: {
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceDark)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppTheme.rose.opacity(0.6))
                        Text("Add Photo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.textMuted)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(
                            colors.border,
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
        }
    }

    // MARK: - Reusable: Edit Field Card

    private func editField<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.rose)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
            }
            content()
        }
    }

    // MARK: - Reusable: Menu Picker

    private func menuPicker(
        selection: Binding<String>,
        options: [String],
        labels: [String]
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(Array(zip(options, labels)), id: \.0) { option, label in
                Text(label).tag(option)
            }
        }
        .pickerStyle(.menu)
        .tint(AppTheme.rose)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .fill(colors.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .stroke(colors.borderSubtle, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Reusable: Multi-Select Chips

    private func multiSelectChips(
        selected: Binding<[String]>,
        options: [String]
    ) -> some View {
        ChipGrid(selected: selected, options: options)
    }

    // MARK: - Option Lists

    private var festivalOptions: [String] {
        [
            "Cheti Chand", "Diwali", "Holi", "Navratri", "Ganesh Chaturthi",
            "Raksha Bandhan", "Thadri", "Jhulelal Jayanti", "Teej", "Eid"
        ]
    }

    private var cuisineOptions: [String] {
        [
            "Sindhi", "North Indian", "South Indian", "Gujarati", "Mughlai",
            "Chinese", "Italian", "Continental", "Thai", "Japanese"
        ]
    }

    private var culturalActivityOptions: [String] {
        [
            "Garba", "Bhajan", "Community Service", "Theatre",
            "Folk Dance", "Sindhi Literature", "Yoga", "Meditation"
        ]
    }

    private var interestOptions: [String] {
        [
            "Travel", "Cooking", "Cricket", "Music", "Fitness", "Reading",
            "Photography", "Dancing", "Art", "Movies", "Yoga", "Hiking",
            "Coffee", "Food", "Gaming", "Bollywood", "Meditation",
            "Volunteering", "Fashion", "Tech", "Writing", "Tennis",
            "Swimming", "Cycling", "Theatre"
        ]
    }

    private var musicOptions: [String] {
        [
            "Bollywood", "Classical", "Sufi", "Pop", "Rock", "Hip-Hop",
            "Sindhi Folk", "Ghazal", "EDM", "Jazz", "R&B"
        ]
    }

    private var movieGenreOptions: [String] {
        [
            "Bollywood", "Hollywood", "Drama", "Comedy", "Thriller",
            "Romance", "Sci-Fi", "Documentary", "Horror", "Anime"
        ]
    }

    private var languageOptions: [String] {
        [
            "Sindhi", "Hindi", "English", "Gujarati", "Marathi",
            "Urdu", "Punjabi", "Tamil", "Telugu", "Kannada"
        ]
    }

    // MARK: - Data Sync

    private func populateFromUser() {
        let user = profileVM.user
        editName = user.displayName
        editBio = user.bio ?? ""
        editDateOfBirth = user.dateOfBirth ?? Date.fromAge(25)
        editHeight = user.heightCm ?? 170
        editEducation = user.education ?? ""
        editOccupation = user.occupation ?? ""
        editCompany = user.company ?? ""
        editReligion = user.religion ?? ""
        editSmoking = user.smoking ?? ""
        editDrinking = user.drinking ?? ""
        editExercise = user.exercise ?? ""
        editWantKids = user.wantKids ?? ""
        editSettlingTimeline = user.settlingTimeline ?? ""

        editFluency = user.sindhiFluency ?? .fluent
        editDialect = user.sindhiDialect ?? ""
        editGotra = user.gotra ?? ""
        editGeneration = user.generation ?? ""
        editMotherTongue = user.motherTongue ?? ""
        editCommunitySubGroup = user.communitySubGroup ?? ""
        editFamilyOriginCity = user.familyOriginCity ?? ""
        editFamilyOriginCountry = user.familyOriginCountry ?? ""

        editPrompts = user.prompts

        editFamilyValues = user.familyValues ?? .moderate
        editFoodPreference = user.foodPreference ?? .vegetarian
        editFestivals = user.festivalsCelebrated ?? []
        editCuisines = user.cuisinePreferences ?? []
        editCulturalActivities = user.culturalActivities ?? []

        editInterests = user.interests
        editMusic = user.musicPreferences ?? []
        editMovies = user.movieGenres ?? []
        editLanguages = user.languages ?? []
        editTravelStyle = user.travelStyle ?? ""
    }

    private func applyEditsToViewModel() {
        profileVM.user.displayName = editName
        profileVM.user.bio = editBio.isEmpty ? nil : editBio
        profileVM.user.dateOfBirth = editDateOfBirth
        profileVM.user.heightCm = editHeight
        profileVM.user.education = editEducation.isEmpty ? nil : editEducation
        profileVM.user.occupation = editOccupation.isEmpty ? nil : editOccupation
        profileVM.user.company = editCompany.isEmpty ? nil : editCompany
        profileVM.user.religion = editReligion.isEmpty ? nil : editReligion
        profileVM.user.smoking = editSmoking.isEmpty ? nil : editSmoking
        profileVM.user.drinking = editDrinking.isEmpty ? nil : editDrinking
        profileVM.user.exercise = editExercise.isEmpty ? nil : editExercise
        profileVM.user.wantKids = editWantKids.isEmpty ? nil : editWantKids
        profileVM.user.settlingTimeline = editSettlingTimeline.isEmpty ? nil : editSettlingTimeline

        profileVM.user.sindhiFluency = editFluency
        profileVM.user.sindhiDialect = editDialect.isEmpty ? nil : editDialect
        profileVM.user.gotra = editGotra.isEmpty ? nil : editGotra
        profileVM.user.generation = editGeneration.isEmpty ? nil : editGeneration
        profileVM.user.motherTongue = editMotherTongue.isEmpty ? nil : editMotherTongue
        profileVM.user.communitySubGroup = editCommunitySubGroup.isEmpty ? nil : editCommunitySubGroup
        profileVM.user.familyOriginCity = editFamilyOriginCity.isEmpty ? nil : editFamilyOriginCity
        profileVM.user.familyOriginCountry = editFamilyOriginCountry.isEmpty ? nil : editFamilyOriginCountry

        profileVM.user.prompts = editPrompts

        profileVM.user.familyValues = editFamilyValues
        profileVM.user.foodPreference = editFoodPreference
        profileVM.user.festivalsCelebrated = editFestivals.isEmpty ? nil : editFestivals
        profileVM.user.cuisinePreferences = editCuisines.isEmpty ? nil : editCuisines
        profileVM.user.culturalActivities = editCulturalActivities.isEmpty ? nil : editCulturalActivities

        profileVM.user.interests = editInterests
        profileVM.user.musicPreferences = editMusic.isEmpty ? nil : editMusic
        profileVM.user.movieGenres = editMovies.isEmpty ? nil : editMovies
        profileVM.user.languages = editLanguages.isEmpty ? nil : editLanguages
        profileVM.user.travelStyle = editTravelStyle.isEmpty ? nil : editTravelStyle
    }

    private func flashSaveToast() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showSaveToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showSaveToast = false
            }
        }
    }
}

// MARK: - Chip Grid (wrapping layout)

private struct ChipGrid: View {
    @Binding var selected: [String]
    let options: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
            spacing: 8
        ) {
            ForEach(options, id: \.self) { option in
                ChipButton(option: option, isSelected: selected.contains(option)) {
                    toggleOption(option)
                }
            }
        }
    }

    private func toggleOption(_ option: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selected.contains(option) {
                selected.removeAll { $0 == option }
            } else {
                selected.append(option)
            }
        }
    }
}

private struct ChipButton: View {
    let option: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        Button(action: action) {
            Text(option)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(chipForeground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(chipBackground)
                .clipShape(Capsule())
                .overlay(chipBorder)
        }
    }

    private var chipForeground: Color {
        isSelected ? .white : colors.textSecondary
    }

    private var chipBackground: some View {
        Capsule().fill(isSelected ? AppTheme.rose : colors.surfaceMedium)
    }

    private var chipBorder: some View {
        Capsule()
            .stroke(
                isSelected ? AppTheme.rose.opacity(0.6) : colors.borderSubtle,
                lineWidth: 0.5
            )
    }
}
