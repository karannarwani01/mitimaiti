import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var feedVM: FeedViewModel
    @Environment(\.adaptiveColors) private var colors
    private let localization = LocalizationManager.shared
    @State private var showFilters = false
    @State private var showNotifications = false
    @EnvironmentObject var profileVM: ProfileViewModel
    @State private var showEditProfile = false
    @State private var bannerDismissed = false
    @State private var showShareSheet = false
    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                discoverHeader
                mainContent
            }
            .appBackground()
            .sheet(isPresented: $feedVM.showScoreBreakdown) {
                if let card = feedVM.selectedCard {
                    ScoreBreakdownSheet(card: card)
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheetView()
                    .environmentObject(feedVM)
            }
            .sheet(isPresented: $showNotifications) {
                NotificationPanelView()
            }
            .alert(localization.t("discover.itsAMatch"), isPresented: $feedVM.showMatchAlert) {
                Button(localization.t("discover.sendMessage")) {}
                Button(localization.t("discover.keepDiscovering"), role: .cancel) {}
            } message: {
                if let user = feedVM.matchedUser {
                    Text("You and \(user.displayName) liked each other! Start a conversation within 24 hours.")
                }
            }
            .navigationDestination(isPresented: $showEditProfile) {
                EditProfileView()
                    .environmentObject(profileVM)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [
                    "Join MitiMaiti - the dating app for the Sindhi community! Download now: https://mitimaiti.app/download"
                ])
            }
        }
    }

    // MARK: - Header

    private var discoverHeader: some View {
        HStack {
            Text(localization.t("discover.title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.textPrimary)

            Spacer()

            // Notification bell
            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 20))
                        .foregroundColor(colors.textPrimary)

                    if notificationManager.unreadCount > 0 {
                        Text("\(min(notificationManager.unreadCount, 9))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(AppTheme.rose))
                            .offset(x: 8, y: -6)
                    }
                }
                .frame(width: 40, height: 40)
            }

            // Filters pill button matching web
            Button { showFilters = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                    Text("Filters")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(colors.cardDark)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(colors.border, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, AppTheme.spacingMD)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if feedVM.isLoading {
            DiscoverCardSkeleton()
                .padding(.top, 8)
            Spacer()
        } else if feedVM.cards.isEmpty {
            Spacer()
            VStack(spacing: 16) {
                EmptyStateView(
                    icon: "heart.slash",
                    title: localization.t("discover.noMoreProfiles"),
                    message: localization.t("discover.noMoreProfilesMessage"),
                    actionTitle: localization.t("discover.adjustFilters"),
                    action: { showFilters = true }
                )
                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                        Text(localization.t("discover.inviteFriends"))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.rose)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppTheme.rose.opacity(0.15))
                            .overlay(
                                Capsule()
                                    .stroke(AppTheme.rose.opacity(0.3), lineWidth: 0.5)
                            )
                    )
                }
            }
            Spacer()
        } else {
            cardDeckView
        }
    }

    // MARK: - Card Deck View (matching web)

    @State private var showProfileDetail = false
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeRotation: Double = 0
    @State private var isAnimating = false
    @State private var passButtonPressed = false
    @State private var likeButtonPressed = false

    /// Normalized swipe progress: -1 (full left) to +1 (full right)
    private var swipeProgress: CGFloat {
        let threshold: CGFloat = 150
        return min(max(swipeOffset / threshold, -1), 1)
    }

    private var cardDeckView: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width - 16 - 48 // leading 16 + trailing 48 for deck edges
            let cardHeight = cardWidth * (4.2 / 3.0)  // 3:4.2 aspect ratio

            VStack(spacing: 0) {
                // Deck with right-side peeking edges
                ZStack {
                    ForEach((1...5).reversed(), id: \.self) { i in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(white: 1.0 - Double(i) * 0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                            )
                            .padding(.leading, 16)
                            .padding(.trailing, 8 + CGFloat(5 - i) * 8)
                            .padding(.top, CGFloat(i * 3))
                            .padding(.bottom, CGFloat(i * 3))
                    }

                    if let card = feedVM.cards.first {
                        activeCard(card: card)
                            .padding(.leading, 16)
                            .padding(.trailing, 48)
                            .overlay(swipeOverlay)
                            .offset(x: swipeOffset)
                            .rotationEffect(.degrees(swipeRotation))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard !isAnimating else { return }
                                        swipeOffset = value.translation.width
                                        swipeRotation = Double(value.translation.width / 20)
                                    }
                                    .onEnded { value in
                                        guard !isAnimating else { return }
                                        let threshold: CGFloat = 100
                                        if value.translation.width < -threshold {
                                            swipeOffCard(direction: .left)
                                        } else if value.translation.width > threshold {
                                            swipeOffCard(direction: .right)
                                        } else {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                swipeOffset = 0
                                                swipeRotation = 0
                                            }
                                        }
                                    }
                            )
                    }
                }
                .frame(height: cardHeight)

                // Pass / Like buttons with scale animation and haptic feedback
                HStack(spacing: 16) {
                    Button {
                        guard !isAnimating else { return }
                        passButtonPressed.toggle()
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        swipeOffCard(direction: .left)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(colors.cardDark)
                                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isAnimating)

                    Button {
                        guard !isAnimating else { return }
                        likeButtonPressed.toggle()
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        swipeOffCard(direction: .right)
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(AppTheme.rose)
                                    .shadow(color: AppTheme.rose.opacity(0.4), radius: 8, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isAnimating)
                }
                .padding(.vertical, 6)

                // Complete your profile banner
                if profileVM.user.profileCompleteness < 90 && !bannerDismissed {
                    completeBanner
                }
            }
        }
        .sheet(isPresented: $showProfileDetail) {
            if let card = feedVM.selectedCard {
                ProfileDetailSheet(card: card, feedVM: feedVM)
            }
        }
    }

    // MARK: - Swipe Overlay (LIKE / NOPE text)

    private var swipeOverlay: some View {
        ZStack {
            // LIKE overlay (right swipe)
            Text("LIKE")
                .font(.system(size: 48, weight: .heavy))
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, lineWidth: 4)
                )
                .rotationEffect(.degrees(-15))
                .opacity(Double(max(0, swipeProgress)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 40)
                .padding(.leading, 36)

            // NOPE overlay (left swipe)
            Text("NOPE")
                .font(.system(size: 48, weight: .heavy))
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 4)
                )
                .rotationEffect(.degrees(15))
                .opacity(Double(max(0, -swipeProgress)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 40)
                .padding(.trailing, 36)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Background Card Placeholder

    private enum SwipeDirection { case left, right }

    private func swipeOffCard(direction: SwipeDirection) {
        isAnimating = true
        let screenWidth = UIScreen.main.bounds.width

        withAnimation(.easeIn(duration: 0.3)) {
            swipeOffset = direction == .left ? -screenWidth * 1.5 : screenWidth * 1.5
            swipeRotation = direction == .left ? -12 : 12
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if direction == .left {
                feedVM.passUser()
            } else {
                feedVM.likeUser()
            }
            // Reset instantly (no animation) before next card appears
            withAnimation(.none) {
                swipeOffset = 0
                swipeRotation = 0
            }
            isAnimating = false
        }
    }

    private func activeCard(card: FeedCard) -> some View {
        let photoURL = card.user.photos.first?.url ?? ""

        return Color.clear
            .overlay(
                AsyncImage(url: URL(string: photoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        ZStack {
                            LinearGradient(
                                colors: [AppTheme.rose.opacity(0.35), AppTheme.roseDark.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Text(card.user.displayName.initials)
                                .font(.system(size: 64, weight: .bold))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    case .empty:
                        ZStack {
                            LinearGradient(
                                colors: [AppTheme.rose.opacity(0.2), AppTheme.roseDark.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                        }
                    @unknown default:
                        Color.gray
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                LinearGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
            )
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(card.user.displayName)
                            .font(.system(size: 24, weight: .bold))
                        Text("\(card.user.age)")
                            .font(.system(size: 20, weight: .medium))
                            .opacity(0.85)
                        if card.user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.info)
                        }
                    }
                    if let city = card.user.city {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11))
                            Text(city)
                                .font(.system(size: 13))
                        }
                        .opacity(0.8)
                    }

                    // Hinge-style prompt teaser (first prompt Q&A)
                    if let prompt = card.user.prompts.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.question)
                                .font(.system(size: 11, weight: .semibold))
                                .opacity(0.7)
                                .lineLimit(1)
                            Text("“\(prompt.answer)”")
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.35))
                        )
                        .padding(.top, 6)
                    }
                }
                .foregroundColor(.white)
                .padding(20)
                .padding(.bottom, 40)
            }
            .shadow(color: colors.elevatedShadowColor, radius: 16, x: 0, y: 8)
            .onTapGesture {
                feedVM.selectedCard = card
                showProfileDetail = true
            }
    }

    // MARK: - Completeness Banner

    private var completeBanner: some View {
        Button { showEditProfile = true } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(AppTheme.rose)
                    .frame(width: 8, height: 8)

                Group {
                    Text("Complete your profile")
                        .font(.system(size: 13, weight: .semibold))
                    + Text(" — Sindhi Identity & Chatti details get 3x more matches!")
                        .font(.system(size: 13))
                }
                .foregroundColor(colors.textSecondary)
                .lineLimit(2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colors.textMuted)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.cardDark)
                    .shadow(color: colors.cardShadowColor, radius: 4, x: 0, y: 2)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

// MARK: - Profile Detail Sheet (tap card to see full profile)

private struct ProfileDetailSheet: View {
    let card: FeedCard
    @ObservedObject var feedVM: FeedViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    private let localization = LocalizationManager.shared

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Photo header
                    AsyncImage(url: URL(string: card.user.photos.first?.url ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            ZStack {
                                LinearGradient(colors: [AppTheme.rose.opacity(0.4), AppTheme.roseDark.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text(card.user.displayName.initials).font(.system(size: 60, weight: .bold)).foregroundColor(.white.opacity(0.25))
                            }
                        case .empty:
                            ZStack {
                                Color.gray.opacity(0.1)
                                ProgressView().tint(AppTheme.rose)
                            }
                        @unknown default: Color.gray
                        }
                    }
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Name + age
                    HStack(spacing: 8) {
                        Text(card.user.displayName)
                            .font(.system(size: 26, weight: .bold))
                        Text("\(card.user.age)")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                        if card.user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(AppTheme.info)
                        }
                    }
                    .foregroundColor(colors.textPrimary)

                    // Location
                    if let city = card.user.city {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 13))
                            Text(city)
                                .font(.system(size: 14))
                        }
                        .foregroundColor(colors.textSecondary)
                    }

                    // Intent
                    if let intent = card.user.intent {
                        HStack(spacing: 4) {
                            Image(systemName: intent.icon)
                                .font(.system(size: 11))
                            Text(intent.display)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(AppTheme.roseLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.rose.opacity(0.15)))
                    }

                    // Scores
                    HStack(spacing: 8) {
                        ScoreTag(label: "Cultural", value: "\(card.culturalScore.overallScore)%", color: AppTheme.scoreGold, icon: "sparkles")
                        if let k = card.kundliScore {
                            ScoreTag(label: "Kundli", value: "\(k.totalScore)/\(k.maxScore)", color: AppTheme.gold, icon: "star.fill")
                        }
                    }
                    .padding(.top, 4)

                    // Bio
                    if let bio = card.user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 15))
                            .foregroundColor(colors.textSecondary)
                            .lineSpacing(4)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colors.surfaceMedium)
                            )
                    }

                    // Prompts
                    ForEach(card.user.prompts) { prompt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(prompt.question)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.gold)
                            Text(prompt.answer)
                                .font(.system(size: 15))
                                .foregroundColor(colors.textPrimary)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colors.surfaceMedium)
                        )
                    }

                    // Interests
                    if !card.user.interests.isEmpty {
                        Text("Interests")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                            .padding(.top, 4)

                        FlowLayout(spacing: 8) {
                            ForEach(card.user.interests, id: \.self) { interest in
                                Text(interest)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colors.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(colors.surfaceMedium)
                                    )
                            }
                        }
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                feedVM.passUser()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Pass")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(colors.surfaceMedium)
                            .clipShape(Capsule())
                        }

                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                feedVM.likeUser()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Like")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppTheme.rose)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .appBackground()
            .navigationTitle(card.user.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.rose)
                }
            }
        }
    }
}
// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Prompt Card

private struct PromptCard: View {
    let prompt: UserPrompt
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.question)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.gold)

                Text(prompt.answer)
                    .font(.system(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .lineSpacing(3)
            }
            .padding(AppTheme.spacingMD)
        }
    }
}

// MARK: - Interest Capsule

private struct InterestCapsule: View {
    let text: String
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(colors.surfaceMedium)
                    .overlay(
                        Capsule()
                            .stroke(colors.border, lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - About Row

private struct AboutRow: View {
    let icon: String
    let label: String
    let value: String
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.rose)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(colors.textMuted)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textPrimary)
        }
    }
}

// MARK: - Action Circle Button

struct ActionCircleButton: View {
    let icon: String
    let size: CGFloat
    var fillColor: Color?
    var iconColor: Color = .white
    var useRoseGradient: Bool = false
    let action: () -> Void

    @Environment(\.adaptiveColors) private var colors
    @State private var tapTrigger = false

    var body: some View {
        Button {
            tapTrigger.toggle()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(iconColor)
                .frame(width: size, height: size)
                .background(circleBackground)
        }
        .sensoryFeedback(.impact, trigger: tapTrigger)
    }

    @ViewBuilder
    private var circleBackground: some View {
        if useRoseGradient {
            Circle()
                .fill(AppTheme.roseGradient)
                .shadow(color: AppTheme.rose.opacity(0.4), radius: 10, x: 0, y: 4)
        } else if let fill = fillColor {
            Circle()
                .fill(fill)
                .overlay(
                    Circle()
                        .stroke(colors.borderSubtle, lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Score Breakdown Sheet

struct ScoreBreakdownSheet: View {
    let card: FeedCard
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    private let localization = LocalizationManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    culturalSection
                    kundliSection
                }
                .padding(AppTheme.spacingMD)
            }
            .appBackground()
            .navigationTitle(localization.t("discover.compatibility"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localization.t("common.done")) { dismiss() }
                        .foregroundColor(AppTheme.rose)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Cultural Section

    private var culturalSection: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(localization.t("discover.culturalCompatibility"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Spacer()
                    Text("\(card.culturalScore.overallScore)%")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.scoreGold)
                }

                ForEach(card.culturalScore.dimensions) { dim in
                    DimensionProgressRow(name: dim.name, score: dim.score, maxScore: dim.maxScore, color: AppTheme.rose)
                }
            }
            .padding(AppTheme.spacingMD)
        }
    }

    // MARK: - Kundli Section

    @ViewBuilder
    private var kundliSection: some View {
        if let kundli = card.kundliScore {
            ContentCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(localization.t("discover.kundliMatch"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(kundli.totalScore)/\(kundli.maxScore)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppTheme.gold)
                            Text(kundli.tier.display)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.gold)
                        }
                    }

                    ForEach(kundli.gunas) { guna in
                        DimensionProgressRow(name: guna.name, score: guna.score, maxScore: guna.maxScore, color: AppTheme.gold)
                    }
                }
                .padding(AppTheme.spacingMD)
            }
        }
    }
}

// MARK: - Dimension Progress Row

private struct DimensionProgressRow: View {
    let name: String
    let score: Int
    let maxScore: Int
    let color: Color
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                Text("\(score)/\(maxScore)")
                    .font(.system(size: 12))
                    .foregroundColor(colors.textSecondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colors.border)
                        .frame(height: 6)

                    let fraction = maxScore > 0 ? CGFloat(score) / CGFloat(maxScore) : 0
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Filter Sheet

struct FilterSheetView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.adaptiveColors) private var colors
    @EnvironmentObject var feedVM: FeedViewModel

    // MARK: - Tab
    @State private var selectedTab: Int = 0

    // MARK: - Essentials
    @State private var ageMin: Double = 21
    @State private var ageMax: Double = 35
    @State private var expandAgeRange: Bool = false

    @State private var heightMin: Double = 140
    @State private var heightMax: Double = 200
    @State private var flexibleHeight: Bool = false

    @State private var selectedIntents: Set<String> = []
    @State private var includeOtherIntents: Bool = false

    @State private var selectedInterests: Set<String> = []

    @State private var verifiedOnly: Bool = false

    // MARK: - Lifestyle / Culture
    @State private var selectedFluency: Set<String> = []
    @State private var selectedReligion: Set<String> = []
    @State private var selectedDietary: Set<String> = []
    @State private var selectedGotra: Set<String> = []

    // MARK: - Education
    @State private var selectedEducation: Set<String> = []

    // MARK: - Habits
    @State private var selectedSmoking: Set<String> = []
    @State private var selectedDrinking: Set<String> = []
    @State private var selectedExercise: Set<String> = []

    // MARK: - Family Plans
    @State private var selectedFamilyPlans: Set<String> = []

    // MARK: - Static option lists
    private let intentOptions = ["Marriage", "Open to anything", "Something casual"]
    private let interestOptions = ["Travel", "Cooking", "Cricket", "Music", "Fitness", "Reading",
                                   "Photography", "Dancing", "Art", "Movies", "Yoga", "Hiking",
                                   "Coffee", "Food", "Gaming"]
    private let fluencyOptions = ["Fluent", "Conversational", "Basic", "Learning"]
    private let religionOptions = ["Hindu", "Sikh", "Muslim", "Other"]
    private let dietaryOptions = ["Veg", "Non-Veg", "Vegan", "Jain"]
    private let gotraOptions = ["Lohana", "Amil", "Bhatia", "Sahiti", "Chhapru"]
    private let educationOptions = ["Bachelors", "Masters", "PhD", "Professional"]
    private let smokingOptions = ["Never", "Social", "Regular"]
    private let drinkingOptions = ["Never", "Social", "Regular"]
    private let exerciseOptions = ["Daily", "Often", "Sometimes", "Never"]
    private let familyPlanOptions = ["Yes", "No", "Open to it", "Already has"]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Tab bar
            tabBar
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            Divider().overlay(colors.border)

            // Tab content
            ScrollView {
                if selectedTab == 0 {
                    essentialsTab
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                } else {
                    lifestyleTab
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                }
            }

            Divider().overlay(colors.border)

            // Show Results button
            showResultsButton
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .appBackground()
        .presentationDetents([.large])
    }

    // MARK: - Header

    private var headerBar: some View {
        ZStack {
            // Left: X button
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(colors.surfaceMedium)
                        )
                }
                Spacer()
            }

            // Center: Title
            Text("Refine Discovery")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(colors.textPrimary)

            // Right: Reset button
            HStack {
                Spacer()
                Button {
                    resetAllFilters()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reset")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.rose)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(AppTheme.rose.opacity(0.1))
                    )
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Essentials", index: 0)
            tabButton(title: "Lifestyle", index: 1)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colors.surfaceMedium)
        )
    }

    private func tabButton(title: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(AppTheme.rose)
                        } else {
                            Capsule().fill(Color.clear)
                        }
                    }
                )
        }
    }

    // MARK: - Essentials Tab

    private var essentialsTab: some View {
        VStack(spacing: 16) {
            // Age Range card
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardHeader(title: "Age range", subtitle: "Between \(Int(ageMin)) and \(Int(ageMax))")

                    VStack(spacing: 4) {
                        HStack {
                            Text("Min: \(Int(ageMin))")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textMuted)
                            Spacer()
                            Text("Max: \(Int(ageMax))")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textMuted)
                        }
                        Slider(value: $ageMin, in: 18...60, step: 1)
                            .tint(AppTheme.rose)
                        Slider(value: $ageMax, in: 18...60, step: 1)
                            .tint(AppTheme.rose)
                    }

                    Divider().overlay(colors.border)

                    toggleRow(label: "Expand range if few results", isOn: $expandAgeRange)
                }
                .padding(16)
            }

            // Height card
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardHeader(title: "Height", subtitle: "\(Int(heightMin)) cm — \(Int(heightMax)) cm")

                    VStack(spacing: 4) {
                        HStack {
                            Text("Min: \(Int(heightMin)) cm")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textMuted)
                            Spacer()
                            Text("Max: \(Int(heightMax)) cm")
                                .font(.system(size: 12))
                                .foregroundColor(colors.textMuted)
                        }
                        Slider(value: $heightMin, in: 100...220, step: 1)
                            .tint(AppTheme.rose)
                        Slider(value: $heightMax, in: 100...220, step: 1)
                            .tint(AppTheme.rose)
                    }

                    Divider().overlay(colors.border)

                    toggleRow(label: "Flexible on height", isOn: $flexibleHeight)
                }
                .padding(16)
            }

            // Looking for card
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardHeader(title: "Looking for", subtitle: nil)

                    FlowLayout(spacing: 8) {
                        ForEach(intentOptions, id: \.self) { option in
                            FilterChip(
                                label: option,
                                isSelected: selectedIntents.contains(option)
                            ) {
                                toggleSet(&selectedIntents, value: option)
                            }
                        }
                    }

                    Divider().overlay(colors.border)

                    toggleRow(label: "Include others if few results", isOn: $includeOtherIntents)
                }
                .padding(16)
            }

            // Shared interests card
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardHeader(title: "Shared interests",
                               subtitle: "Tap to prioritize people who share these")

                    FlowLayout(spacing: 8) {
                        ForEach(interestOptions, id: \.self) { interest in
                            FilterChip(
                                label: interest,
                                isSelected: selectedInterests.contains(interest)
                            ) {
                                toggleSet(&selectedInterests, value: interest)
                            }
                        }
                    }
                }
                .padding(16)
            }

            // Verified profiles only card
            ContentCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verified profiles only")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text("Photo-verified members")
                            .font(.system(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $verifiedOnly)
                        .tint(AppTheme.rose)
                        .labelsHidden()
                }
                .padding(16)
            }
        }
    }

    // MARK: - Lifestyle Tab

    private var lifestyleTab: some View {
        VStack(spacing: 16) {
            // Culture card
            ContentCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Culture")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    chipSubSection(label: "SINDHI FLUENCY", options: fluencyOptions, selection: $selectedFluency)
                    Divider().overlay(colors.border)
                    chipSubSection(label: "RELIGION", options: religionOptions, selection: $selectedReligion)
                    Divider().overlay(colors.border)
                    chipSubSection(label: "DIETARY PREFERENCE", options: dietaryOptions, selection: $selectedDietary)
                    Divider().overlay(colors.border)
                    chipSubSection(label: "GOTRA", options: gotraOptions, selection: $selectedGotra)
                }
                .padding(16)
            }

            // Education card
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Education")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    FlowLayout(spacing: 8) {
                        ForEach(educationOptions, id: \.self) { option in
                            FilterChip(
                                label: option,
                                isSelected: selectedEducation.contains(option)
                            ) {
                                toggleSet(&selectedEducation, value: option)
                            }
                        }
                    }
                }
                .padding(16)
            }

            // Habits card
            ContentCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Habits")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    chipSubSection(label: "SMOKING", options: smokingOptions, selection: $selectedSmoking)
                    Divider().overlay(colors.border)
                    chipSubSection(label: "DRINKING", options: drinkingOptions, selection: $selectedDrinking)
                    Divider().overlay(colors.border)
                    chipSubSection(label: "EXERCISE", options: exerciseOptions, selection: $selectedExercise)
                }
                .padding(16)
            }

            // Family Plans card
            ContentCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Family Plans")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(colors.textPrimary)

                    FlowLayout(spacing: 8) {
                        ForEach(familyPlanOptions, id: \.self) { option in
                            FilterChip(
                                label: option,
                                isSelected: selectedFamilyPlans.contains(option)
                            ) {
                                toggleSet(&selectedFamilyPlans, value: option)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Show Results Button

    private var showResultsButton: some View {
        Button {
            applyFilters()
            dismiss()
        } label: {
            Text("Show Results")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(AppTheme.rose)
                )
        }
    }

    /// Persist the chosen filters to the backend and reload the deck. The
    /// backend filters are single-valued, so multi-select chips send their
    /// first selection (NSNull clears a filter).
    private func applyFilters() {
        func single(_ set: Set<String>, transform: (String) -> String = { $0 }) -> Any {
            set.first.map(transform) ?? NSNull()
        }

        let intentMap = [
            "Marriage": "marriage",
            "Open to anything": "open",
            "Something casual": "casual",
            "Something serious": "serious",
        ]
        let dietaryMap = [
            "Veg": "vegetarian",
            "Non-Veg": "non_vegetarian",
            "Vegan": "vegan",
            "Jain": "jain",
        ]

        let settings: [String: Any] = [
            "age_min": Int(ageMin),
            "age_max": Int(ageMax),
            "height_min": Int(heightMin),
            "height_max": Int(heightMax),
            "verified_only": verifiedOnly,
            "intent_filter": selectedIntents.first.flatMap { intentMap[$0] } ?? NSNull(),
            "religion_filter": single(selectedReligion),
            "dietary_filter": selectedDietary.first.flatMap { dietaryMap[$0] } ?? NSNull(),
            "gotra_filter": single(selectedGotra),
            "fluency_filter": single(selectedFluency) { $0.lowercased() },
            "education_filter": single(selectedEducation),
            "smoking_filter": single(selectedSmoking),
            "drinking_filter": single(selectedDrinking),
        ]
        feedVM.applyFilters(settings)
    }

    // MARK: - Reusable sub-views

    private func cardHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textSecondary)
            }
        }
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.textSecondary)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(AppTheme.rose)
                .labelsHidden()
        }
    }

    private func chipSubSection(label: String, options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colors.textMuted)
                .kerning(0.5)

            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    FilterChip(
                        label: option,
                        isSelected: selection.wrappedValue.contains(option)
                    ) {
                        var updated = selection.wrappedValue
                        if updated.contains(option) {
                            updated.remove(option)
                        } else {
                            updated.insert(option)
                        }
                        selection.wrappedValue = updated
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func toggleSet(_ set: inout Set<String>, value: String) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func resetAllFilters() {
        selectedTab = 0

        ageMin = 21
        ageMax = 35
        expandAgeRange = false

        heightMin = 140
        heightMax = 200
        flexibleHeight = false

        selectedIntents = []
        includeOtherIntents = false
        selectedInterests = []
        verifiedOnly = false

        selectedFluency = []
        selectedReligion = []
        selectedDietary = []
        selectedGotra = []

        selectedEducation = []
        selectedSmoking = []
        selectedDrinking = []
        selectedExercise = []
        selectedFamilyPlans = []
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : colors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? AppTheme.rose : colors.surfaceMedium)
                    .overlay(
                        Capsule()
                            .stroke(
                                isSelected ? AppTheme.rose.opacity(0.6) : colors.border,
                                lineWidth: 0.5
                            )
                    )
            )
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            let point = CGPoint(
                x: bounds.minX + position.x,
                y: bounds.minY + position.y
            )
            subviews[index].place(at: point, proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxRowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += maxRowHeight + spacing
                maxRowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxRowHeight = max(maxRowHeight, size.height)
            x += size.width + spacing
        }

        let totalSize = CGSize(width: maxWidth, height: y + maxRowHeight)
        return LayoutResult(positions: positions, size: totalSize)
    }

    private struct LayoutResult {
        let positions: [CGPoint]
        let size: CGSize
    }
}

// MARK: - Share Sheet (UIKit wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
