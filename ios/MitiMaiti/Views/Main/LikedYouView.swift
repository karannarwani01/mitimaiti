import SwiftUI

struct LikedYouView: View {
    @EnvironmentObject var inboxVM: InboxViewModel
    private let localization = LocalizationManager.shared
    @Environment(\.adaptiveColors) private var colors

    // Swipe & animation state
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeRotation: Double = 0
    @State private var isAnimating: Bool = false
    @State private var cardOpacity: Double = 1
    @State private var cardScale: CGFloat = 1
    @State private var showEntrance: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                likedYouHeader
                likedYouContent
            }
            .appBackground()
            .onAppear {
                inboxVM.loadInbox()
            }
        }
    }

    // MARK: - Header

    private var likedYouHeader: some View {
        HStack {
            Text(localization.t("inbox.likedYou"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colors.textPrimary)

            if inboxVM.totalLikes > 0 {
                Text("\(inboxVM.totalLikes)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.rose))
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var likedYouContent: some View {
        if inboxVM.isLoading {
            Spacer()
            ProgressView()
                .tint(AppTheme.rose)
            Spacer()
        } else if inboxVM.likes.isEmpty {
            EmptyStateView(
                icon: "heart",
                title: localization.t("inbox.noLikesYet"),
                message: localization.t("inbox.noLikesMessage")
            )
        } else {
            ScrollView {
                VStack(spacing: 20) {
                    // Main featured card (first like)
                    if let firstLike = inboxVM.likes.first {
                        featuredCardSection(for: firstLike)
                    }

                    // Up Next section
                    if inboxVM.likes.count > 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Up Next")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(colors.textPrimary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(inboxVM.likes.dropFirst().prefix(3))) { like in
                                        LikedYouThumbnailCard(like: like)
                                            .onTapGesture {
                                                skipToProfile(like: like)
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Remaining likes as grid
                    if inboxVM.likes.count > 4 {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(inboxVM.likes.dropFirst(4))) { like in
                                LikedYouCardView(like: like)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Featured Card Section (with swipe, badge, animations)

    @ViewBuilder
    private func featuredCardSection(for like: LikedYouCard) -> some View {
        VStack(spacing: 12) {
            // "What they liked" badge (server-backed label)
            likedBadge(label: like.likeLabel)

            // Their note (like-with-comment) — the reason this card is up top
            if let note = like.likeComment {
                Text("“\(note)”")
                    .font(.system(size: 14))
                    .foregroundColor(colors.textPrimary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppTheme.rose.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.rose.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)
            }

            // Swipeable featured card wrapper
            ZStack {
                LikedYouFeaturedCard(
                    like: like,
                    onLike: { animateSwipe(direction: .right, likeId: like.id) },
                    onPass: { animateSwipe(direction: .left, likeId: like.id) }
                )
                .offset(x: swipeOffset)
                .rotationEffect(.degrees(swipeRotation))
                .opacity(cardOpacity)
                .scaleEffect(cardScale)

                // LIKE / NOPE overlay text
                if swipeOffset > 30 {
                    swipeOverlayText("LIKE", color: .green)
                        .opacity(Double(min(abs(swipeOffset) / 100, 1)))
                } else if swipeOffset < -30 {
                    swipeOverlayText("NOPE", color: .red)
                        .opacity(Double(min(abs(swipeOffset) / 100, 1)))
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isAnimating else { return }
                        swipeOffset = value.translation.width
                        swipeRotation = Double(value.translation.width / 25)
                    }
                    .onEnded { value in
                        guard !isAnimating else { return }
                        if value.translation.width > 100 {
                            animateSwipe(direction: .right, likeId: like.id)
                        } else if value.translation.width < -100 {
                            animateSwipe(direction: .left, likeId: like.id)
                        } else {
                            // Snap back
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                swipeOffset = 0
                                swipeRotation = 0
                            }
                        }
                    }
            )
        }
        .onAppear {
            // Entrance animation for first load
            cardScale = 0.95
            cardOpacity = 0
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                cardScale = 1
                cardOpacity = 1
            }
        }
    }

    // MARK: - "What they liked" Badge

    private func likedBadge(label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11))
            Text(label)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(AppTheme.rose)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(AppTheme.rose.opacity(0.1))
        )
    }

    // MARK: - Swipe Overlay Text

    private func swipeOverlayText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 48, weight: .heavy))
            .foregroundColor(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 4)
            )
            .rotationEffect(.degrees(text == "LIKE" ? -15 : 15))
            .allowsHitTesting(false)
    }

    // MARK: - Swipe Animation Logic

    private enum SwipeDirection {
        case left, right
    }

    private func animateSwipe(direction: SwipeDirection, likeId: String) {
        guard !isAnimating else { return }
        isAnimating = true

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        let targetOffset: CGFloat = direction == .right ? 300 : -300
        let targetRotation: Double = direction == .right ? 12 : -12

        // Exit animation
        withAnimation(.easeInOut(duration: 0.35)) {
            swipeOffset = targetOffset
            swipeRotation = targetRotation
            cardOpacity = 0
        }

        // After exit, commit the action and reset for next card entrance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            // Commit the swipe
            if direction == .right {
                inboxVM.likeBack(likeId: likeId)
            } else {
                inboxVM.passLike(likeId: likeId)
            }

            // Reset position instantly (invisible, scaled down for entrance)
            swipeOffset = 0
            swipeRotation = 0
            cardOpacity = 0
            cardScale = 0.95

            // Entrance animation for next card
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                cardOpacity = 1
                cardScale = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = false
            }
        }
    }

    // MARK: - Skip to Profile (Up Next tap)

    private func skipToProfile(like: LikedYouCard) {
        guard !isAnimating else { return }
        guard let index = inboxVM.likes.firstIndex(where: { $0.id == like.id }) else { return }

        isAnimating = true

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Fade out current card
        withAnimation(.easeInOut(duration: 0.25)) {
            cardOpacity = 0
            cardScale = 0.95
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            // Move the tapped profile to front
            let tapped = inboxVM.likes.remove(at: index)
            inboxVM.likes.insert(tapped, at: 0)

            // Entrance animation
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                cardOpacity = 1
                cardScale = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Liked You Card

struct LikedYouCardView: View {
    let like: LikedYouCard
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        Button {
            print("Tapped profile: \(like.user.displayName)")
        } label: {
            likeCardBody
        }
        .buttonStyle(.plain)
    }

    private var likeCardBody: some View {
        ContentCard {
            VStack(spacing: 10) {
                ProfileAvatar(
                    url: nil,
                    name: like.user.displayName,
                    size: 60,
                    isOnline: like.user.isOnline,
                    showBorder: true
                )

                VStack(spacing: 2) {
                    Text(like.user.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)

                    Text("\(like.user.age)")
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                }

                culturalBadge

                if let note = like.likeComment {
                    Text("💬 “\(note)”")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(like.likeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(colors.textMuted)
                        .lineLimit(1)
                }

                Text(like.likedAt.timeAgoShort)
                    .font(.system(size: 10))
                    .foregroundColor(colors.textMuted)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
    }

    private var culturalBadge: some View {
        let badgeColor: Color = {
            switch like.culturalBadge {
            case .gold: return AppTheme.scoreGold
            case .green: return AppTheme.scoreGreen
            case .orange: return AppTheme.scoreOrange
            case .none: return colors.textMuted
            }
        }()

        return ScoreTag(
            label: LocalizationManager.shared.t("common.cultural"),
            value: "\(like.culturalScore)%",
            color: badgeColor
        )
    }
}

// MARK: - Featured Card (Large, like Discover card)

struct LikedYouFeaturedCard: View {
    let like: LikedYouCard
    let onLike: () -> Void
    let onPass: () -> Void
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        VStack(spacing: 16) {
            // Large photo card with gradient and name overlay
            ZStack(alignment: .bottomLeading) {
                // Photo or gradient fallback
                if let photoURL = like.user.photos.first?.url, let url = URL(string: photoURL), photoURL.hasPrefix("http") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 380)
                                .clipped()
                        default:
                            featuredCardPlaceholder
                        }
                    }
                } else {
                    featuredCardPlaceholder
                }

                // Bottom gradient -- smoother multi-stop fade
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.black.opacity(0.05), location: 0.35),
                        .init(color: Color.black.opacity(0.25), location: 0.6),
                        .init(color: Color.black.opacity(0.65), location: 0.85),
                        .init(color: Color.black.opacity(0.8), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                // Name overlay
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(like.user.displayName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("\(like.user.age)")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    if let city = like.user.city {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 12))
                            Text(city)
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }

                    Text(like.likeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.2)))

                    // Their note (like-with-comment)
                    if let note = like.likeComment {
                        Text("“\(note)”")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.45))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                            )
                    }
                }
                .padding(20)
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)

            // Action buttons
            HStack(spacing: 20) {
                // Pass button
                Button {
                    onPass()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(colors.surfaceMedium)
                                .overlay(
                                    Circle()
                                        .stroke(colors.border, lineWidth: 0.5)
                                )
                        )
                }

                // Like button
                Button {
                    onLike()
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            Circle()
                                .fill(AppTheme.roseGradient)
                                .shadow(color: AppTheme.rose.opacity(0.4), radius: 10, x: 0, y: 4)
                        )
                }
            }
        }
        .padding(.horizontal)
    }

    private var featuredCardPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [AppTheme.rose.opacity(0.35), AppTheme.roseDark.opacity(0.5), AppTheme.roseDark.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 380)
            .overlay(
                Text(like.user.displayName.initials)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white.opacity(0.2))
            )
    }
}

// MARK: - Thumbnail Card (Up Next)

struct LikedYouThumbnailCard: View {
    let like: LikedYouCard
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // Photo or gradient fallback
                if let photoURL = like.user.photos.first?.url, let url = URL(string: photoURL), photoURL.hasPrefix("http") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 150)
                                .clipped()
                        default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(like.user.displayName.components(separatedBy: " ").first ?? like.user.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text("\(like.user.age)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(8)
            }
            .frame(width: 120, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .contentShape(Rectangle())
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [AppTheme.rose.opacity(0.3), AppTheme.roseDark.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 150)
            .overlay(
                Text(like.user.displayName.initials)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            )
    }
}
