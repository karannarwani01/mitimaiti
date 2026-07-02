import SwiftUI
import PhotosUI

struct OnboardingContainerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.adaptiveColors) private var colors
    @StateObject private var vm = OnboardingViewModel()
    private let localization = LocalizationManager.shared

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Flex spacer above the card so short content centers
                        // vertically; tall content (e.g. with keyboard up) just
                        // scrolls past this naturally.
                        Spacer(minLength: 20)

                        // White card container matching web design
                        VStack(spacing: 0) {
                            // Progress bar at top of card
                            progressBar

                            // Card header: back + step counter
                            cardHeader

                            // Title + subtitle
                            titleSection

                            // Step content
                            stepContentSection

                            // Continue button inside card
                            continueButton
                        }
                        .background(colors.cardDark)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: colors.elevatedShadowColor, radius: 24, x: 0, y: 8)
                        .padding(.horizontal, AppTheme.spacingMD)

                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: vm.currentStep)
    }

    // MARK: - Progress Bar (top of card)

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(colors.border)
                    .frame(height: 4)

                Rectangle()
                    .fill(AppTheme.roseGradient)
                    .frame(width: geo.size.width * vm.progress, height: 4)
                    .animation(.spring(response: 0.4), value: vm.progress)
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        HStack {
            if vm.currentStep != .name {
                Button { vm.previousStep() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 36, height: 36)
                }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }

            Spacer()

            Text("\(localization.t("onboarding.step")) \(vm.currentStep.rawValue + 1) \(localization.t("onboarding.of")) \(OnboardingStep.allCases.count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textMuted)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(vm.currentStep.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(colors.textPrimary)

            Text(vm.currentStep.subtitle)
                .font(.system(size: 14))
                .foregroundColor(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Step Content

    private var stepContentSection: some View {
        VStack(spacing: 0) {
            stepView(for: vm.currentStep)
        }
        .padding(.horizontal, 20)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .id(vm.currentStep)
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .name: NameStepContent(vm: vm)
        case .birthday: BirthdayStepContent(vm: vm)
        case .gender: GenderStepContent(vm: vm)
        case .photos: PhotosStepContent(vm: vm)
        case .intent: IntentStepContent(vm: vm)
        case .showMe: ShowMeStepContent(vm: vm)
        case .location: LocationStepContent(vm: vm)
        case .ready: ReadyStepContent(vm: vm, onComplete: { authVM.completeOnboarding() })
        }
    }

    // MARK: - Continue Button (inside card)

    @ViewBuilder
    private var continueButton: some View {
        if vm.currentStep == .ready {
            EmptyView()
        } else {
            Button {
                if vm.currentStep == .photos {
                    Task { await vm.proceedFromPhotos() }
                } else {
                    vm.nextStep()
                }
            } label: {
                if vm.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(localization.t("onboarding.continue"))
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(vm.canProceed ? AppTheme.rose : AppTheme.roseLight)
            )
            .disabled(!vm.canProceed || vm.isLoading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Name Step

private struct NameStepContent: View {
    @ObservedObject var vm: OnboardingViewModel
    @Environment(\.adaptiveColors) private var colors
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Underline-style input matching web
            VStack(alignment: .leading, spacing: 0) {
                TextField("Enter your full name", text: $vm.firstName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                    .focused($isFocused)
                    .tint(AppTheme.rose)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(isFocused ? AppTheme.rose : colors.border)
                    .frame(height: isFocused ? 2 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)

                HStack {
                    Text("Your family name can be hidden in Settings")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textMuted)
                    Spacer()
                    Text("\(vm.firstName.count)/50")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textMuted)
                }
                .padding(.top, 8)
            }

            // "Not Sindhi?" toggle card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not Sindhi? No worries!")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Text("Open to vibing with the Sindhi community")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $vm.isNonSindhi)
                    .tint(AppTheme.rose)
                    .labelsHidden()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.rose.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.rose.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Birthday Step

private struct BirthdayStepContent: View {
    @ObservedObject var vm: OnboardingViewModel
    @Environment(\.adaptiveColors) private var colors
    @State private var dayText = ""
    @State private var monthText = ""
    @State private var monthInputText = ""
    @State private var yearText = ""

    private enum BirthdayField { case month }
    @FocusState private var focusedField: BirthdayField?

    private let days = Array(1...31)

    private var years: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(stride(from: currentYear - 18, through: currentYear - 98, by: -1))
    }

    var body: some View {
        VStack(spacing: 16) {
            // 3-field input row matching web
            HStack(spacing: 10) {
                dayPickerField
                monthPickerField
                yearPickerField
            }

            // Age validation
            if !dayText.isEmpty && !monthText.isEmpty && !yearText.isEmpty {
                ageIndicator
            }
        }
        .onChange(of: dayText) { _, _ in updateVM() }
        .onChange(of: monthText) { _, _ in updateVM() }
        .onChange(of: yearText) { _, _ in updateVM() }
        .onChange(of: focusedField) { _, newField in
            // Month field just lost focus — commit any pending single-digit input
            if newField != .month {
                parseMonth(monthInputText, commitIfSingleDigit: true)
            }
        }
    }

    private var dayPickerField: some View {
        TextField("Day", text: $dayText)
            .keyboardType(.numberPad)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(dayText.isEmpty ? colors.textMuted : colors.textPrimary)
            .multilineTextAlignment(.leading)
            .onChange(of: dayText) { _, newValue in
                let filtered = String(newValue.filter { $0.isNumber }.prefix(2))
                if filtered != newValue { dayText = filtered }
                if let day = Int(filtered), day >= 1, day <= 31 {
                    vm.birthDay = day
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(colors.surfaceMedium)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
    }

    private var monthPickerField: some View {
        TextField("Month", text: $monthInputText)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(monthText.isEmpty ? colors.textMuted : colors.textPrimary)
            .multilineTextAlignment(.leading)
            .focused($focusedField, equals: .month)
            .onChange(of: monthInputText) { _, newValue in
                parseMonth(newValue, commitIfSingleDigit: false)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(colors.surfaceMedium)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
    }

    private let monthAbbreviations = [
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    private func parseMonth(_ input: String, commitIfSingleDigit: Bool) {
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            monthText = ""
            return
        }
        // If the field already shows a valid capitalized abbreviation (e.g. after we set it),
        // confirm the match and return to avoid an onChange loop.
        if trimmed.count == 3, let idx = monthAbbreviations.firstIndex(of: trimmed) {
            let abbrev = monthAbbreviations[idx].capitalized
            if monthText == abbrev { return }  // already set, nothing to do
            monthText = abbrev
            vm.birthMonth = idx + 1
            return
        }
        // Try numeric
        if let num = Int(trimmed), num >= 1, num <= 12 {
            // Two-digit months (10, 11, 12) always commit immediately.
            // Single-digit months (1–9) only commit when the field loses focus.
            let isTwoDigit = trimmed.count == 2
            if isTwoDigit || commitIfSingleDigit {
                let abbrev = monthAbbreviations[num - 1].capitalized
                monthText = abbrev
                monthInputText = abbrev
                vm.birthMonth = num
            } else {
                // Still a valid-in-progress number — store the month value but keep raw input
                vm.birthMonth = num
                monthText = monthAbbreviations[num - 1].capitalized  // used by age indicator
            }
            return
        }
        // Try abbreviation prefix match (first 3 chars of longer input)
        let prefix = String(trimmed.prefix(3))
        if trimmed.count >= 3, let idx = monthAbbreviations.firstIndex(of: prefix) {
            let abbrev = monthAbbreviations[idx].capitalized
            monthText = abbrev
            monthInputText = abbrev
            vm.birthMonth = idx + 1
            return
        }
        // No valid match yet — keep monthText empty so age indicator stays hidden
        monthText = ""
    }

    private var yearPickerField: some View {
        TextField("Year", text: $yearText)
            .keyboardType(.numberPad)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(yearText.isEmpty ? colors.textMuted : colors.textPrimary)
            .multilineTextAlignment(.leading)
            .onChange(of: yearText) { _, newValue in
                let filtered = String(newValue.filter { $0.isNumber }.prefix(4))
                if filtered != newValue { yearText = filtered }
                if let year = Int(filtered), year >= 1900, year <= Calendar.current.component(.year, from: Date()) {
                    vm.birthYear = year
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(colors.surfaceMedium)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colors.border, lineWidth: 1)
            )
    }

    private var ageIndicator: some View {
        let isValid = vm.isAgeValid
        return HStack(spacing: 8) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(isValid ? AppTheme.success : AppTheme.error)
            Text(isValid ? "You're \(vm.age) years old" : "Must be 18 or older")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isValid ? colors.textSecondary : AppTheme.error)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func updateVM() {
        if let day = Int(dayText) { vm.birthDay = day }
        if let year = Int(yearText) { vm.birthYear = year }
    }
}

// MARK: - Radio Indicator (reusable, matches web design)

private struct RadioIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppTheme.rose : Color.gray.opacity(0.4), lineWidth: 2)
                .frame(width: 24, height: 24)

            if isSelected {
                Circle()
                    .fill(AppTheme.rose)
                    .frame(width: 14, height: 14)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Gender Step

private struct GenderStepContent: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Gender.allCases) { gender in
                GenderCard(gender: gender, isSelected: vm.selectedGender == gender) {
                    withAnimation(.spring(response: 0.3)) {
                        vm.selectedGender = gender
                    }
                }
            }
        }
    }
}

private struct GenderCard: View {
    let gender: Gender
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.adaptiveColors) private var colors

    private var symbolName: String {
        switch gender {
        case .man: return "figure.stand"
        case .woman: return "figure.stand.dress"
        case .nonBinary: return "figure.arms.open"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? AppTheme.rose : colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? AppTheme.rose.opacity(0.1) : colors.surfaceMedium)
                    )

                Text(gender.display)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Spacer()

                RadioIndicator(isSelected: isSelected)
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusCard)
                .fill(colors.cardDark)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusCard)
                        .stroke(isSelected ? AppTheme.rose : colors.border, lineWidth: isSelected ? 1.5 : 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusCard))
    }
}

// MARK: - Photos Step

private struct PhotosStepContent: View {
    @ObservedObject var vm: OnboardingViewModel
    @Environment(\.adaptiveColors) private var colors
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: AppTheme.spacingMD) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    if index < vm.selectedImages.count {
                        filledPhotoSlot(at: index)
                    } else {
                        emptyPhotoSlot(index: index)
                    }
                }
            }

            photoCountLabel

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colors.border)
                        .frame(height: 6)
                    Capsule()
                        .fill(AppTheme.rose)
                        .frame(width: geo.size.width * (Double(vm.selectedImages.count) / 6.0), height: 6)
                        .animation(.easeOut(duration: 0.3), value: vm.selectedImages.count)
                }
            }
            .frame(height: 6)

            Text("Profiles with 3+ photos get 4x more matches")
                .font(.system(size: 12))
                .foregroundColor(colors.textMuted)
                .multilineTextAlignment(.center)

            if let err = vm.error {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .photosPicker(
            isPresented: $showPicker,
            selection: $selectedItems,
            maxSelectionCount: 6 - vm.selectedImages.count,
            matching: .images
        )
        .onChange(of: selectedItems) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        vm.addImage(image)
                    }
                }
                selectedItems = []
            }
        }
    }

    private func filledPhotoSlot(at index: Int) -> some View {
        // Constrain the whole slot to the same 3:4 frame the empty slots use,
        // then crop the image to fill that frame and overlay controls. The
        // previous structure put aspectRatio + clipShape directly on the
        // Image, which let the Image's intrinsic size overflow the grid cell
        // and bleed into adjacent slots.
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay(
                Image(uiImage: vm.selectedImages[index])
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                Button { vm.removePhoto(at: index) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                if index == 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text("MAIN")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.gold)
                    .clipShape(Capsule())
                    .padding(6)
                }
            }
            .shadow(color: colors.cardShadowColor, radius: 6, x: 0, y: 3)
    }

    private func emptyPhotoSlot(index: Int) -> some View {
        Button { showPicker = true } label: {
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surfaceMedium.opacity(0.5))
                .aspectRatio(3.0 / 4.0, contentMode: .fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            Color.gray.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6])
                        )
                )
                .overlay(
                    VStack(spacing: 6) {
                        if index == 0 && vm.selectedImages.isEmpty {
                            // First slot: camera icon + Main label
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(colors.textMuted.opacity(0.6))
                            HStack(spacing: 3) {
                                Image(systemName: "star")
                                    .font(.system(size: 10))
                                Text("Main")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(AppTheme.gold)
                        } else {
                            // Other slots: just a + icon
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(colors.textMuted.opacity(0.5))
                        }
                    }
                )
        }
    }

    private var photoCountLabel: some View {
        HStack {
            Text("\(vm.selectedImages.count)/6")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.textSecondary)
        }
    }
}

// MARK: - Intent Step

private struct IntentStepContent: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Intent.allCases.filter { $0 != .marriage }) { intent in
                IntentCard(intent: intent, isSelected: vm.selectedIntent == intent) {
                    withAnimation(.spring(response: 0.3)) {
                        vm.selectedIntent = intent
                    }
                }
            }
        }
    }
}

private struct IntentCard: View {
    let intent: Intent
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.adaptiveColors) private var colors

    private var symbolName: String {
        switch intent {
        case .casual: return "cup.and.saucer.fill"
        case .serious: return "heart.fill"
        case .open: return "sparkles"
        case .marriage: return "person.2.fill"
        }
    }

    private var descriptionText: String {
        switch intent {
        case .casual: return "Keep it light and see where things go"
        case .serious: return "Ready for the real thing"
        case .open: return "Let fate decide, open to all possibilities"
        case .marriage: return "Looking to settle down"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? AppTheme.rose : colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? AppTheme.rose.opacity(0.1) : colors.surfaceMedium)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(intent.display)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Text(descriptionText)
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                }

                Spacer()

                RadioIndicator(isSelected: isSelected)
                    .padding(.top, 6)
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusCard)
                .fill(colors.cardDark)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusCard)
                        .stroke(isSelected ? AppTheme.rose : colors.border, lineWidth: isSelected ? 1.5 : 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusCard))
    }
}

// MARK: - ShowMe Step

private struct ShowMeStepContent: View {
    @ObservedObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(ShowMe.allCases) { pref in
                ShowMeCard(pref: pref, isSelected: vm.selectedShowMe == pref) {
                    withAnimation(.spring(response: 0.3)) {
                        vm.selectedShowMe = pref
                    }
                }
            }
        }
    }
}

private struct ShowMeCard: View {
    let pref: ShowMe
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.adaptiveColors) private var colors

    private var symbolName: String {
        switch pref {
        case .men: return "figure.stand"
        case .women: return "figure.stand.dress"
        case .everyone: return "figure.2.arms.open"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? AppTheme.rose : colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? AppTheme.rose.opacity(0.1) : colors.surfaceMedium)
                    )

                Text(pref.display)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colors.textPrimary)

                Spacer()

                RadioIndicator(isSelected: isSelected)
            }
            .padding(18)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusCard)
                .fill(colors.cardDark)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusCard)
                        .stroke(isSelected ? AppTheme.rose : colors.border, lineWidth: isSelected ? 1.5 : 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusCard))
    }
}

// MARK: - Location Step

private struct LocationStepContent: View {
    @ObservedObject var vm: OnboardingViewModel
    @Environment(\.adaptiveColors) private var colors
    @StateObject private var locationDetector = LocationDetector()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private let mockCities = [
        "Mumbai", "Delhi", "Bangalore", "Hyderabad", "Chennai",
        "Pune", "Ahmedabad", "Kolkata", "Jaipur", "Lucknow",
        "Dubai", "Abu Dhabi", "London", "New York", "Toronto",
        "Singapore", "Hong Kong", "Sydney", "Nairobi", "Lagos"
    ]

    private var filteredCities: [String] {
        if searchText.isEmpty { return mockCities }
        return mockCities.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: AppTheme.spacingMD) {
            // Auto-detect location button — matches Android: circular icon badge
            // with two-line label, so icon stays visible while the spinner runs.
            Button {
                locationDetector.detectLocation { detectedCity, region, country in
                    if let c = detectedCity {
                        vm.selectedCity = c
                        vm.selectedRegion = region
                        vm.selectedCountry = country
                        searchText = ""
                        isSearchFocused = false
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.rose.opacity(0.1))
                            .frame(width: 40, height: 40)
                        if locationDetector.isDetecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.rose))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AppTheme.rose)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locationDetector.isDetecting ? "Detecting location..." : "Use my current location")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.rose)
                        Text("Auto-detect your city")
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusLG)
                        .fill(AppTheme.rose.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusLG)
                                .stroke(AppTheme.rose.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .disabled(locationDetector.isDetecting)

            // Divider
            HStack(spacing: 12) {
                Rectangle().fill(colors.border).frame(height: 1)
                Text("or search for a city")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.textMuted)
                Rectangle().fill(colors.border).frame(height: 1)
            }

            // Selected city card
            if let selectedCity = vm.selectedCity, !selectedCity.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.rose)

                    Text(selectedCity)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Spacer()

                    Button {
                        vm.selectedCity = nil
                        vm.selectedRegion = nil
                        vm.selectedCountry = nil
                        searchText = ""
                        isSearchFocused = true
                    } label: {
                        Text("Change")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.rose)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .fill(AppTheme.rose.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                                .stroke(AppTheme.rose.opacity(0.15), lineWidth: 1)
                        )
                )
            } else {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(colors.textMuted)

                    TextField("Search for a city...", text: $searchText)
                        .font(.system(size: 16))
                        .foregroundColor(colors.textPrimary)
                        .focused($isSearchFocused)
                        .tint(AppTheme.rose)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(colors.surfaceMedium)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSearchFocused ? AppTheme.rose : colors.border, lineWidth: isSearchFocused ? 1.5 : 1)
                )

                // City list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCities, id: \.self) { city in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    vm.selectedCity = city
                                    // Manual pick from the mock list has no
                                    // reliable region/country — clear stale
                                    // values from a prior auto-detect.
                                    vm.selectedRegion = nil
                                    vm.selectedCountry = nil
                                    searchText = ""
                                    isSearchFocused = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin")
                                        .font(.system(size: 14))
                                        .foregroundColor(colors.textMuted)
                                        .frame(width: 24)

                                    Text(city)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(colors.textPrimary)

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }

                            if city != filteredCities.last {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
                .background(colors.surfaceMedium)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colors.border, lineWidth: 1)
                )
            }
        }
    }
}

// MARK: - Location Detector

import CoreLocation

@MainActor
class LocationDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isDetecting = false
    private let manager = CLLocationManager()
    private var completion: ((String?, String?, String?) -> Void)?
    private var requestPending = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func detectLocation(completion: @escaping (String?, String?, String?) -> Void) {
        self.completion = completion
        isDetecting = true
        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            // Wait for authorizationDidChange before requesting location.
            requestPending = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(nil, nil, nil)
        @unknown default:
            finish(nil, nil, nil)
        }
    }

    private func finish(_ city: String?, _ region: String?, _ country: String?) {
        isDetecting = false
        requestPending = false
        completion?(city, region, country)
        completion = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.requestPending else { return }
            let status = manager.authorizationStatus
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.requestPending = false
                manager.requestLocation()
            case .denied, .restricted:
                self.finish(nil, nil, nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                let placemark = placemarks?.first
                self.finish(
                    placemark?.locality,
                    placemark?.administrativeArea,
                    placemark?.country
                )
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(nil, nil, nil)
        }
    }
}

// MARK: - Confetti Particle

private struct ConfettiParticle: View {
    let color: Color
    let isCircle: Bool
    @State private var xOffset: CGFloat = 0
    @State private var yOffset: CGFloat = -60
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        Group {
            if isCircle {
                Circle()
                    .fill(color)
                    .frame(width: CGFloat.random(in: 6...10), height: CGFloat.random(in: 6...10))
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 8...14))
            }
        }
        .rotationEffect(.degrees(rotation))
        .offset(x: xOffset, y: yOffset)
        .opacity(opacity)
        .onAppear {
            let randomX = CGFloat.random(in: -140...140)
            let randomY = CGFloat.random(in: 200...400)
            let delay = Double.random(in: 0...0.6)
            withAnimation(.easeOut(duration: 2.0).delay(delay)) {
                xOffset = randomX
                yOffset = randomY
                rotation = Double.random(in: -360...360)
            }
            withAnimation(.easeIn(duration: 0.8).delay(delay + 1.2)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Ready Step

private struct ReadyStepContent: View {
    @ObservedObject var vm: OnboardingViewModel
    @Environment(\.adaptiveColors) private var colors
    let onComplete: () -> Void
    @State private var animateEmoji = false
    @State private var showConfetti = false
    @State private var showEditProfile = false

    private let confettiColors: [Color] = [
        AppTheme.rose, .pink, .orange, .yellow, .purple, .blue, .green, .red
    ]

    // Real, backend-computed profile completeness (0–100). The backend's
    // calculateCompleteness() is the single source of truth used for
    // matching, so we show that instead of a local guess that always maxes
    // out after onboarding. nil until the GET /me fetch resolves.
    @State private var realCompleteness: Int?

    // Whether the onboarding profile PATCH has completed — gates "Go to
    // Discover" so the save can't be cancelled by navigation.
    @State private var profileSaved = false
    @State private var savingBeforeExit = false

    private var completenessFraction: Double {
        Double(min(max(realCompleteness ?? 0, 0), 100)) / 100.0
    }

    var body: some View {
        ZStack {
            VStack(spacing: 14) {
                // Celebration icon with spring animation
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.roseGradient)
                    .scaleEffect(animateEmoji ? 1.0 : 0.3)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.5),
                        value: animateEmoji
                    )

                Text("You're In!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                Text("Welcome to the MitiMaiti community, \(vm.firstName)!")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textSecondary)
                    .multilineTextAlignment(.center)

                // Profile preview card with gradient header
                profileCardWithGradient

                // Sindhi identity prompt (tappable → edit profile)
                Button { showEditProfile = true } label: {
                    sindhiIdentityPrompt
                }
                .sheet(isPresented: $showEditProfile) {
                    NavigationStack {
                        EditProfileView()
                            .environmentObject(ProfileViewModel())
                    }
                }

                // Go to Discover button. Disabled until the profile PATCH
                // resolves: navigating away tears down this view and cancels
                // the in-flight save, which lost the whole onboarding profile
                // and bounced users back into onboarding on next launch.
                Button {
                    if profileSaved {
                        onComplete()
                    } else {
                        Task {
                            savingBeforeExit = true
                            if let submitted = await vm.submitProfile() {
                                realCompleteness = submitted
                                profileSaved = true
                            }
                            savingBeforeExit = false
                            if profileSaved { onComplete() }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if savingBeforeExit || !profileSaved {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text(savingBeforeExit ? "Saving your profile…" : "Finishing up…")
                                .font(.system(size: 17, weight: .semibold))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                            Text("✨ Go to Discover")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.roseGradient)
                    )
                }
                .disabled(savingBeforeExit)
            }

            // Confetti overlay
            if showConfetti {
                ForEach(0..<30, id: \.self) { i in
                    ConfettiParticle(
                        color: confettiColors[i % confettiColors.count],
                        isCircle: i % 2 == 0
                    )
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            animateEmoji = true
            showConfetti = true
        }
        .task {
            // Persist everything onboarding collected (name, DOB, gender,
            // intent, show-me, city) — until now this never left the device.
            // patchMe returns the backend-recalculated completeness, the
            // single source of truth used for matching / shown on ProfileView.
            if let submitted = await vm.submitProfile() {
                realCompleteness = submitted
                profileSaved = true
            } else if let user = try? await APIService.shared.fetchProfile() {
                realCompleteness = user.profileCompleteness
            }
        }
    }

    private var profileCardWithGradient: some View {
        VStack(spacing: 0) {
            // Rose gradient header with centered avatar (matching web)
            ZStack {
                LinearGradient(
                    colors: [AppTheme.rose, AppTheme.roseDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 120)

                // Sparkle icons
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "sparkle")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(12)
                    }
                    Spacer()
                    HStack {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(12)
                        Spacer()
                    }
                }
                .frame(height: 120)

                // Centered avatar - show real photo if available
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 72, height: 72)

                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                        .frame(width: 72, height: 72)

                    if let img = UserImageStore.shared.profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipShape(Circle())
                    } else {
                        Text(String(vm.firstName.prefix(1)).uppercased())
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 16
                )
            )

            // Profile info section (white)
            VStack(alignment: .leading, spacing: 10) {
                // Name, age
                Text("\(vm.firstName), \(vm.age)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                // Location
                if let city = vm.selectedCity {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: 13))
                        Text("\(city), India")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(colors.textSecondary)
                }

                // Completeness
                VStack(spacing: 6) {
                    HStack {
                        Text("Profile completeness")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colors.textMuted)
                        Spacer()
                        Text(realCompleteness.map { "\($0)%" } ?? "…")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.rose)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colors.border)
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.roseGradient)
                                .frame(width: geo.size.width * completenessFraction, height: 6)
                                .animation(.easeOut(duration: 0.8), value: completenessFraction)
                        }
                    }
                    .frame(height: 6)
                }

                Text("Fill out more to get better matches!")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(16)
        }
        .background(colors.cardDark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 0.5)
        )
        .shadow(color: colors.cardShadowColor, radius: 8, x: 0, y: 4)
    }

    private var sindhiIdentityPrompt: some View {
        HStack(spacing: 12) {
            // Om icon in gold circle
            Image(systemName: "om")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.gold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppTheme.gold.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.isNonSindhi ? "Complete your Profile" : "Complete your Sindhi Identity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text(vm.isNonSindhi ? "Add more details for better matching" : "Add fluency, gotra, festivals for better cultural matching")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colors.textMuted)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.warning.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
