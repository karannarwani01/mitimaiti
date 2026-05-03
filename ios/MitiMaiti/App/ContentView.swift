import SwiftUI

// MARK: - Content View (Root Router)

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else if !authVM.isAuthenticated {
                WelcomeView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if !authVM.hasCompletedOnboarding {
                OnboardingContainerView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .onAppear {
                        NotificationManager.shared.requestPermission()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: showSplash)
        .animation(.easeInOut(duration: 0.5), value: authVM.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: authVM.hasCompletedOnboarding)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.6)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var heartBeat = false
    @State private var titleOffset: CGFloat = 20

    var body: some View {
        ZStack {
            // Pulsing rose circles
            pulsingCircles

            // Content
            VStack(spacing: 24) {
                heartIcon
                titleGroup
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .appBackground()
        .onAppear {
            heartBeat = true
            withAnimation(.spring(response: 0.9, dampingFraction: 0.65)) {
                scale = 1
                titleOffset = 0
            }
            withAnimation(.easeIn(duration: 0.7)) {
                opacity = 1
            }
        }
    }

    // MARK: - Pulsing Circles

    private var pulsingCircles: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.rose.opacity(0.05))
                    .frame(
                        width: CGFloat(200 + i * 100),
                        height: CGFloat(200 + i * 100)
                    )
                    .scaleEffect(heartBeat ? 1.15 : 0.85)
                    .animation(
                        .easeInOut(duration: 1.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.25),
                        value: heartBeat
                    )
            }
        }
    }

    // MARK: - Heart Icon

    private var heartIcon: some View {
        ZStack {
            Circle()
                .fill(AppTheme.rose.opacity(0.12))
                .frame(width: 120, height: 120)
                .blur(radius: 18)
                .scaleEffect(heartBeat ? 1.2 : 0.9)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: heartBeat
                )

            Image(systemName: "heart.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.roseGradient)
                .shadow(color: AppTheme.rose.opacity(0.5), radius: 20, x: 0, y: 8)
                .scaleEffect(heartBeat ? 1.08 : 0.96)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: heartBeat
                )
        }
    }

    // MARK: - Title

    private var titleGroup: some View {
        VStack(spacing: 10) {
            Text("MitiMaiti")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Where Sindhi Hearts Meet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.gold, AppTheme.goldLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .offset(y: titleOffset)
    }
}
