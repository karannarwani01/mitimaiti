import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var profileVM: ProfileViewModel
    private let localization = LocalizationManager.shared
    @Environment(\.adaptiveColors) private var colors
    @State private var showEditProfile = false
    @State private var showSettings = false
    @State private var showFamily = false
    @State private var appeared = false

    // MARK: - Avatar photo-change state
    @State private var showAvatarActionSheet = false
    @State private var showAvatarPhotoPicker = false
    @State private var showUploadedPhotosPicker = false
    @State private var avatarPickerItem: PhotosPickerItem? = nil

    // MARK: - Selfie verification state
    @State private var showVerifyCamera = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingLG) {
                    headerSection
                    photoCarousel
                        .sectionFadeIn(appeared: appeared, delay: 0.05)
                    completenessCard
                        .sectionFadeIn(appeared: appeared, delay: 0.1)
                    if !profileVM.user.isVerified && profileVM.user.selfieVerificationAvailable {
                        getVerifiedCard
                            .sectionFadeIn(appeared: appeared, delay: 0.12)
                    }
                    if profileVM.dailyPrompt?.question != nil {
                        dailyQuestionCard
                            .sectionFadeIn(appeared: appeared, delay: 0.13)
                    }
                    bioSection
                        .sectionFadeIn(appeared: appeared, delay: 0.2)
                    promptsSection
                        .sectionFadeIn(appeared: appeared, delay: 0.25)
                    aboutMeSection
                        .sectionFadeIn(appeared: appeared, delay: 0.3)
                    sindhiIdentitySection
                        .sectionFadeIn(appeared: appeared, delay: 0.35)
                    interestsSection
                        .sectionFadeIn(appeared: appeared, delay: 0.4)
                    actionButtons
                        .sectionFadeIn(appeared: appeared, delay: 0.45)
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, AppTheme.spacingMD)
            }
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(colors.textPrimary)
                    }
                }
            }
            .navigationDestination(isPresented: $showEditProfile) {
                EditProfileView()
                    .environmentObject(profileVM)
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showFamily) {
                FamilyView()
            }
            .onAppear {
                profileVM.loadProfile()
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            }
            // Avatar: action-sheet choice
            .confirmationDialog("Change Profile Photo", isPresented: $showAvatarActionSheet, titleVisibility: .visible) {
                Button("Choose from Gallery") { showAvatarPhotoPicker = true }
                if !imageStore.photos.isEmpty {
                    Button("Choose from Uploaded Photos") { showUploadedPhotosPicker = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            // Avatar: gallery picker
            .photosPicker(isPresented: $showAvatarPhotoPicker, selection: $avatarPickerItem, matching: .images)
            .onChange(of: avatarPickerItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        imageStore.save(uiImage, at: 0)
                    }
                    avatarPickerItem = nil
                }
            }
            // Avatar: pick from already-uploaded photos
            .sheet(isPresented: $showUploadedPhotosPicker) {
                UploadedPhotosPickerSheet(imageStore: imageStore) { selectedIndex in
                    imageStore.setPrimary(at: selectedIndex)
                    showUploadedPhotosPicker = false
                }
            }
            // pose challenge — "copy this pose", then the camera.
            .alert(
                "Copy this pose",
                isPresented: Binding(
                    get: { profileVM.verifyChallenge != nil && !showVerifyCamera },
                    set: { if !$0 && !showVerifyCamera { profileVM.verifyChallenge = nil } }
                )
            ) {
                Button("Take selfie") { showVerifyCamera = true }
                Button("Cancel", role: .cancel) { profileVM.verifyChallenge = nil }
            } message: {
                if let pose = profileVM.verifyChallenge {
                    Text("\(pose.emoji) \(pose.name)\n\(pose.instruction). We'll compare the selfie to your profile photos — it's never saved.")
                }
            }
            // Selfie verification camera + result alert
            .sheet(isPresented: $showVerifyCamera) {
                CameraGalleryPicker(sourceType: .camera) { url in
                    if let data = try? Data(contentsOf: url) {
                        profileVM.verifySelfie(imageData: data)
                    }
                }
                .ignoresSafeArea()
            }
            .alert(
                profileVM.user.isVerified ? "Verified! ✅" : "Verification",
                isPresented: Binding(
                    get: { profileVM.verifyMessage != nil },
                    set: { if !$0 { profileVM.verifyMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { profileVM.verifyMessage = nil }
            } message: {
                Text(profileVM.verifyMessage ?? "")
            }
        }
    }

    // MARK: - Today's Question (Chai Chat) — the answer shows on your Discover card

    @State private var promptEditing = false
    @State private var promptText = ""

    private var dailyQuestionCard: some View {
        let prompt = profileVM.dailyPrompt
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("☕")
                Text("Today's Question")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.saffron)
                Spacer()
                if prompt?.answeredToday == true && !promptEditing {
                    Text("Answered ✓")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                }
            }
            Text(prompt?.question ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)

            if !promptEditing, let answer = prompt?.answer, !answer.isEmpty {
                HStack {
                    Text("“\(answer)”")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                    Spacer()
                    Button("Edit") {
                        promptText = answer
                        promptEditing = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.rose)
                }
            } else if !promptEditing {
                Button {
                    promptText = ""
                    promptEditing = true
                } label: {
                    Text("Answer — it shows on your card")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.rose))
                }
            } else {
                TextField("Your answer…", text: $promptText, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(colors.surfaceMedium))
                    .onChange(of: promptText) { _, newValue in
                        if newValue.count > 500 { promptText = String(newValue.prefix(500)) }
                    }
                HStack {
                    Text("\(promptText.count)/500")
                        .font(.caption2)
                        .foregroundColor(colors.textMuted)
                    Spacer()
                    Button("Cancel") { promptEditing = false }
                        .font(.system(size: 13))
                        .foregroundColor(colors.textMuted)
                    Button {
                        profileVM.answerDailyPrompt(promptText)
                        promptEditing = false
                    } label: {
                        Text(profileVM.isSavingPromptAnswer ? "Saving…" : "Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppTheme.rose))
                    }
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profileVM.isSavingPromptAnswer)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colors.cardDark)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.border, lineWidth: 0.5))
        )
        .padding(.horizontal, AppTheme.spacingMD)
    }

    // MARK: - Get Verified card (photo verification)

    private var getVerifiedCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundColor(AppTheme.info)

            VStack(alignment: .leading, spacing: 2) {
                Text("Get Verified")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Text("Take a quick selfie to earn the blue badge. Your selfie is never stored.")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textMuted)
            }

            Spacer()

            Button {
                profileVM.startVerifyChallenge()
            } label: {
                if profileVM.isVerifying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                        .frame(width: 52, height: 28)
                } else {
                    Text("Verify")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                }
            }
            .background(Capsule().fill(AppTheme.rose))
            .disabled(profileVM.isVerifying)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colors.surfaceMedium)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ZStack {
                    LinearGradient(
                        colors: [
                            AppTheme.rose.opacity(0.4),
                            AppTheme.roseDark.opacity(0.5),
                            AppTheme.rose.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    RadialGradient(
                        colors: [AppTheme.rose.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 140
                    )
                    .blendMode(.screen)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLG))

                profileAvatarRing
                    .offset(y: 54)
            }

            Spacer().frame(height: 62)

            nameAndLocation

            // Intent badge
            intentBadge

            Spacer().frame(height: AppTheme.spacingMD)

            Button { showEditProfile = true } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                    Text(localization.t("profile.editProfile"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.vertical, 12)
                .background(AppTheme.roseGradient)
                .clipShape(Capsule())
                .shadow(color: AppTheme.rose.opacity(0.35), radius: 12, x: 0, y: 5)
            }
        }
        .padding(.top, AppTheme.spacingSM)
    }

    // MARK: - Photo Carousel

    @ViewBuilder
    private var photoCarousel: some View {
        if !profileVM.user.photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSM) {
                    ForEach(Array(profileVM.user.photos.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated()), id: \.element.id) { index, photo in
                        photoCarouselItem(photo: photo, isMain: index == 0)
                    }
                }
                .padding(.horizontal, AppTheme.spacingXS)
            }
        }
    }

    @ObservedObject private var imageStore = UserImageStore.shared

    private func photoCarouselItem(photo: UserPhoto, isMain: Bool) -> some View {
        // Resolve: local store first (by sortOrder index), then remote URL
        let storeImage: UIImage? = {
            let idx = photo.sortOrder
            guard idx < imageStore.photos.count else { return nil }
            return imageStore.photos[idx]
        }()

        return ZStack(alignment: .topLeading) {
            if let localImg = storeImage {
                Image(uiImage: localImg)
                    .resizable()
                    .scaledToFill()
            } else if photo.url.hasPrefix("http"), let imageURL = URL(string: photo.url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
        }
        .frame(width: 120, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                .stroke(isMain ? AppTheme.gold : colors.border, lineWidth: isMain ? 2 : 0.5)
        )
        .overlay(alignment: .topLeading) {
            if isMain {
                Text("MAIN")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppTheme.goldGradient)
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
    }

    private var photoPlaceholder: some View {
        LinearGradient(
            colors: [AppTheme.rose.opacity(0.3), AppTheme.roseDark.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundColor(colors.textMuted)
        )
    }

    // MARK: - Intent Badge

    @ViewBuilder
    private var intentBadge: some View {
        if let intent = profileVM.user.intent {
            HStack(spacing: 4) {
                Image(systemName: intent.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(intent.display)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(intentColor(intent))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(intentColor(intent).opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(intentColor(intent).opacity(0.3), lineWidth: 0.5)
                    )
            )
            .padding(.top, AppTheme.spacingSM)
        }
    }

    private func intentColor(_ intent: Intent) -> Color {
        switch intent {
        case .casual: return AppTheme.info
        case .serious: return AppTheme.gold
        case .open: return Color.purple
        case .marriage: return AppTheme.rose
        }
    }

    // MARK: - Unified Progress Ring Avatar

    private var profileAvatarRing: some View {
        ZStack {
            Circle()
                .stroke(colors.border, lineWidth: 4)
                .frame(width: 120, height: 120)

            Circle()
                .trim(from: 0, to: completenessProgress)
                .stroke(
                    AppTheme.roseGradient,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: completenessProgress)

            ProfileAvatar(
                url: profileVM.user.photos.first?.url,
                name: profileVM.user.displayName,
                size: 108,
                isOnline: profileVM.user.isOnline,
                showBorder: false,
                useProfileImage: true
            )

            Button { showAvatarActionSheet = true } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppTheme.roseGradient)
                            .shadow(color: AppTheme.rose.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
            }
            .offset(x: 40, y: 40)

            if profileVM.user.isVerified {
                verifiedBadge
                    .offset(x: -40, y: 40)
            }
        }
    }

    private var verifiedBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 24))
            .foregroundColor(AppTheme.info)
            .background(
                Circle()
                    .fill(colors.background)
                    .frame(width: 28, height: 28)
            )
    }

    private var nameAndLocation: some View {
        VStack(spacing: AppTheme.spacingXS) {
            HStack(spacing: 6) {
                Text(profileVM.user.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colors.textPrimary)

                if profileVM.user.age > 0 {
                    Text(", \(profileVM.user.age)")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                }
            }

            if let city = profileVM.user.city {
                HStack(spacing: AppTheme.spacingXS) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                    Text(city)
                        .font(.system(size: 14))
                }
                .foregroundColor(colors.textSecondary)
            }
        }
    }

    // MARK: - Profile Completeness Card

    private var completenessCard: some View {
        Button { showEditProfile = true } label: {
            ContentCard {
                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    HStack(spacing: AppTheme.spacingSM) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.rose)

                        Text(localization.t("profile.completeness"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colors.textPrimary)

                        Spacer()

                        Text("\(profileVM.computedCompleteness)%")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.rose)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colors.border)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.roseGradient)
                                .frame(width: geo.size.width * completenessProgress, height: 8)
                                .animation(.easeInOut(duration: 0.8), value: completenessProgress)
                        }
                    }
                    .frame(height: 8)

                    Text(localization.t("profile.completeForMatches"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                }
                .padding(AppTheme.spacingMD)
            }
        }
        .buttonStyle(.plain)
    }

    private var completenessProgress: Double {
        Double(profileVM.user.profileCompleteness) / 100.0
    }

    // MARK: - Bio Section

    @ViewBuilder
    private var bioSection: some View {
        if let bio = profileVM.user.bio, !bio.isEmpty {
            ContentCard {
                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    sectionLabel(icon: "text.quote", title: localization.t("profile.bio"))

                    HStack(alignment: .top, spacing: AppTheme.spacingSM) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.rose.opacity(0.3))

                        Text(bio)
                            .font(.system(size: 15).italic())
                            .foregroundColor(colors.textPrimary)
                            .lineSpacing(4)
                    }
                }
                .padding(AppTheme.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Prompts Section

    @ViewBuilder
    private var promptsSection: some View {
        VStack(spacing: AppTheme.spacingSM) {
            if !profileVM.user.prompts.isEmpty {
                ForEach(profileVM.user.prompts) { prompt in
                    promptCard(prompt: prompt)
                }
            }

            if profileVM.user.prompts.count < 3 {
                Button { showEditProfile = true } label: {
                    ContentCard {
                        HStack(spacing: AppTheme.spacingSM) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(AppTheme.rose)
                            Text("Add prompts")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.rose)
                            Spacer()
                            Text("\(profileVM.user.prompts.count)/3")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textMuted)
                        }
                        .padding(AppTheme.spacingMD)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func promptCard(prompt: UserPrompt) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                Text(prompt.question.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.rose)
                    .tracking(1.2)
                Text(prompt.answer)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .lineSpacing(3)
            }
            .padding(AppTheme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - About Me Section

    private var aboutMeSection: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                HStack {
                    sectionLabel(icon: "person.fill", title: localization.t("profile.aboutMe"))
                    Spacer()
                    Text("\(aboutMeFilledCount)/\(aboutMeTotalCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textMuted)
                }

                aboutMeFieldRow(icon: "ruler", label: localization.t("profile.height"), value: profileVM.user.heightCm.map { "\($0) cm" })
                aboutMeFieldRow(icon: "graduationcap.fill", label: localization.t("profile.education"), value: profileVM.user.education)
                aboutMeFieldRow(icon: "briefcase.fill", label: localization.t("profile.occupation"), value: profileVM.user.occupation)
                aboutMeFieldRow(icon: "building.2.fill", label: localization.t("profile.company"), value: profileVM.user.company)
                aboutMeFieldRow(icon: "hands.sparkles.fill", label: localization.t("profile.religion"), value: profileVM.user.religion)
                aboutMeFieldRow(icon: "smoke.fill", label: localization.t("profile.smoking"), value: profileVM.user.smoking)
                aboutMeFieldRow(icon: "wineglass.fill", label: localization.t("profile.drinking"), value: profileVM.user.drinking)
                aboutMeFieldRow(icon: "figure.run", label: localization.t("profile.exercise"), value: profileVM.user.exercise)
                aboutMeFieldRow(icon: "figure.and.child.holdinghands", label: localization.t("profile.wantKids"), value: profileVM.user.wantKids)
            }
            .padding(AppTheme.spacingMD)
        }
    }

    private func aboutMeFieldRow(icon: String, label: String, value: String?) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.rose)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textSecondary)
                .frame(width: 110, alignment: .leading)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textPrimary)
            } else {
                Button { showEditProfile = true } label: {
                    Text("Add")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textMuted)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.spacingXS)
    }

    private var aboutMeFilledCount: Int {
        var count = 0
        if profileVM.user.heightCm != nil { count += 1 }
        if profileVM.user.education != nil { count += 1 }
        if profileVM.user.occupation != nil { count += 1 }
        if profileVM.user.company != nil { count += 1 }
        if profileVM.user.religion != nil { count += 1 }
        if profileVM.user.smoking != nil { count += 1 }
        if profileVM.user.drinking != nil { count += 1 }
        if profileVM.user.exercise != nil { count += 1 }
        if profileVM.user.wantKids != nil { count += 1 }
        return count
    }

    private var aboutMeTotalCount: Int { 9 }

    // MARK: - Sindhi Identity Section

    private var sindhiIdentitySection: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                HStack {
                    sectionLabel(icon: "globe.asia.australia.fill", title: localization.t("profile.sindhiIdentity"))
                    Spacer()
                    Text("\(sindhiFilledCount)/\(sindhiTotalCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textMuted)
                }

                sindhiFieldRow(icon: "waveform.and.mic", label: localization.t("profile.sindhiFluency"), value: profileVM.user.sindhiFluency?.display)
                sindhiFieldRow(icon: "character.bubble.fill", label: localization.t("profile.dialect"), value: profileVM.user.sindhiDialect)
                sindhiFieldRow(icon: "mouth.fill", label: localization.t("profile.motherTongue"), value: profileVM.user.motherTongue)
                sindhiFieldRow(icon: "leaf.fill", label: localization.t("profile.gotra"), value: profileVM.user.gotra)
                sindhiFieldRow(icon: "clock.arrow.circlepath", label: localization.t("profile.generation"), value: profileVM.user.generation)
                sindhiFieldRow(icon: "house.fill", label: localization.t("profile.familyValues"), value: profileVM.user.familyValues?.display)
                sindhiFieldRow(icon: "fork.knife", label: localization.t("profile.foodPreference"), value: profileVM.user.foodPreference?.display)
            }
            .padding(AppTheme.spacingMD)
        }
    }

    private func sindhiFieldRow(icon: String, label: String, value: String?) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.rose)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textSecondary)
                .frame(width: 110, alignment: .leading)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textPrimary)
            } else {
                Button { showEditProfile = true } label: {
                    Text("Add")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.textMuted)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppTheme.spacingXS)
    }

    private var sindhiFilledCount: Int {
        var count = 0
        if profileVM.user.sindhiFluency != nil { count += 1 }
        if profileVM.user.sindhiDialect != nil { count += 1 }
        if profileVM.user.motherTongue != nil { count += 1 }
        if profileVM.user.gotra != nil { count += 1 }
        if profileVM.user.generation != nil { count += 1 }
        if profileVM.user.familyValues != nil { count += 1 }
        if profileVM.user.foodPreference != nil { count += 1 }
        return count
    }

    private var sindhiTotalCount: Int { 7 }

    // MARK: - Interests Section

    @ViewBuilder
    private var interestsSection: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                HStack {
                    sectionLabel(icon: "heart.fill", title: localization.t("profile.interests"))
                    Spacer()
                    Text("\(profileVM.user.interests.count)/10")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textMuted)
                }

                if profileVM.user.interests.isEmpty {
                    Button { showEditProfile = true } label: {
                        HStack(spacing: AppTheme.spacingSM) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.rose)
                            Text("Add interests")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppTheme.rose)
                        }
                        .padding(.vertical, AppTheme.spacingSM)
                    }
                } else {
                    InterestsFlowLayout(spacing: AppTheme.spacingSM) {
                        ForEach(profileVM.user.interests, id: \.self) { interest in
                            Text(interest)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.rose)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(AppTheme.rose.opacity(0.1))
                                        .overlay(
                                            Capsule()
                                                .stroke(AppTheme.rose.opacity(0.25), lineWidth: 0.5)
                                        )
                                )
                        }
                    }
                }
            }
            .padding(AppTheme.spacingMD)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: AppTheme.spacingSM) {
            SecondaryButton(title: localization.t("family.familyMode"), icon: "person.3.fill") {
                showFamily = true
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.rose)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colors.textPrimary)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.rose)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colors.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)

            Spacer()
        }
        .padding(.vertical, AppTheme.spacingSM)
    }
}

// MARK: - Interests Flow Layout

struct InterestsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}

// MARK: - Section Fade-In Modifier

private struct SectionFadeIn: ViewModifier {
    let appeared: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(
                .easeOut(duration: 0.35).delay(delay),
                value: appeared
            )
    }
}

extension View {
    fileprivate func sectionFadeIn(appeared: Bool, delay: Double) -> some View {
        modifier(SectionFadeIn(appeared: appeared, delay: delay))
    }
}

// MARK: - Uploaded Photos Picker Sheet

struct UploadedPhotosPickerSheet: View {
    @ObservedObject var imageStore: UserImageStore
    let onSelect: (Int) -> Void

    @Environment(\.adaptiveColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if imageStore.photos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 44))
                            .foregroundColor(colors.textMuted)
                        Text("No uploaded photos yet")
                            .font(.system(size: 15))
                            .foregroundColor(colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(imageStore.photos.enumerated()), id: \.offset) { index, photo in
                            Button {
                                onSelect(index)
                            } label: {
                                ZStack(alignment: .topLeading) {
                                    Image(uiImage: photo)
                                        .resizable()
                                        .scaledToFill()
                                        .aspectRatio(3 / 4, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                                                .stroke(
                                                    index == 0 ? AppTheme.gold : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )

                                    if index == 0 {
                                        Text("MAIN")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(AppTheme.goldGradient)
                                            .clipShape(Capsule())
                                            .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppTheme.spacingMD)
                }
            }
            .appBackground()
            .navigationTitle("Choose Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(colors.textSecondary)
                }
            }
        }
    }
}
