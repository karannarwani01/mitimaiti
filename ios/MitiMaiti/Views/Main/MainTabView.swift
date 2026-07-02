import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var tabBounce: [Int: CGFloat] = [:]
    @StateObject private var feedVM = FeedViewModel()
    @StateObject private var inboxVM = InboxViewModel()
    @StateObject private var profileVM = ProfileViewModel()
    @StateObject private var familyVM = FamilyViewModel()
    @ObservedObject private var notificationManager = NotificationManager.shared

    var body: some View {
        TabView(selection: tabSelection) {
            DiscoverView()
                .environmentObject(feedVM)
                .environmentObject(profileVM)
                .environmentObject(inboxVM)
                .tabItem {
                    Label("Discover", systemImage: "sparkle.magnifyingglass")
                }
                .tag(0)

            LikedYouView()
                .environmentObject(inboxVM)
                .tabItem {
                    Label("Liked You", systemImage: "heart.fill")
                }
                .tag(1)
                .badge(likeBadgeCount)

            MatchesView()
                .environmentObject(inboxVM)
                .tabItem {
                    Label("Matches", systemImage: "message.fill")
                }
                .tag(2)
                .badge(matchBadgeCount)

            FamilyView()
                .tabItem {
                    Label("Family", systemImage: "person.3.fill")
                }
                .tag(3)
                .badge(familyBadgeCount)

            ProfileView()
                .environmentObject(profileVM)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(4)
        }
        .tint(AppTheme.rose)
        .onAppear {
            configureTabBarAppearance()
            feedVM.loadFeed()
            inboxVM.loadInbox()
            profileVM.loadProfile()
            notificationManager.initialize()
        }
        .onChange(of: notificationManager.selectedTab) { _, newTab in
            selectedTab = newTab
        }
    }

    // MARK: - Tab Selection Binding (with haptic + bounce)

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                guard newTab != selectedTab else { return }
                // Haptic feedback
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Bounce animation on selected icon
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 12)) {
                    tabBounce[newTab] = 1.15
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 12)) {
                        tabBounce[newTab] = 1.0
                    }
                }
                selectedTab = newTab
            }
        )
    }

    // MARK: - Tab Bar Appearance

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        // Subtle top border shadow
        appearance.shadowImage = UIImage()
        appearance.shadowColor = nil
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)

        // Larger icons for better touch targets
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium)
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]

        let normalItemAppearance = UITabBarItemAppearance()
        normalItemAppearance.normal.titleTextAttributes = normalAttrs
        normalItemAppearance.selected.titleTextAttributes = selectedAttrs

        normalItemAppearance.normal.iconColor = UIColor.secondaryLabel
        normalItemAppearance.selected.iconColor = UIColor(AppTheme.rose)

        appearance.stackedLayoutAppearance = normalItemAppearance
        appearance.inlineLayoutAppearance = normalItemAppearance
        appearance.compactInlineLayoutAppearance = normalItemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        // Top shadow for depth
        UITabBar.appearance().layer.shadowColor = UIColor.black.cgColor
        UITabBar.appearance().layer.shadowOffset = CGSize(width: 0, height: -2)
        UITabBar.appearance().layer.shadowRadius = 8
        UITabBar.appearance().layer.shadowOpacity = 0.06
        UITabBar.appearance().clipsToBounds = false
    }

    // MARK: - Badge Counts

    private var likeBadgeCount: Int {
        let inboxLikes = inboxVM.totalLikes
        let notifLikes = notificationManager.unreadCount(for: [.like, .profileView])
        return max(inboxLikes, notifLikes)
    }

    private var matchBadgeCount: Int {
        let unread = inboxVM.unreadMessages
        let notifMatches = notificationManager.unreadCount(for: [.match, .message, .expiry, .icebreaker])
        return max(unread, notifMatches)
    }

    private var familyBadgeCount: Int {
        notificationManager.unreadCount(for: [.family, .familySuggestion])
    }
}
