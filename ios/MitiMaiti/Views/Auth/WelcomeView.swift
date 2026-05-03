import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    private let localization = LocalizationManager.shared
    @Environment(\.adaptiveColors) private var colors
    @State private var animateSteps = false

    private var steps: [(number: String, titleKey: String, subtitleKey: String)] {
        [
            ("1", "welcome.step1Title", "welcome.step1Sub"),
            ("2", "welcome.step2Title", "welcome.step2Sub"),
            ("3", "welcome.step3Title", "welcome.step3Sub")
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer().frame(height: 60)
                    heroSection
                    ctaButtons
                    howItWorksSection
                    Spacer().frame(height: 40)
                }
            }
            .appBackground()
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                    animateSteps = true
                }
            }
        }
    }

    // MARK: - Hero (title + gold subtitle + tagline)

    private var heroSection: some View {
        VStack(spacing: 16) {
            Text(localization.t("welcome.title"))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.roseGradient)

            Text(localization.t("welcome.subtitle"))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.gold, AppTheme.goldLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)

            Text(localization.t("welcome.tagline"))
                .font(.system(size: 15))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.top, 4)
        }
        .padding(.horizontal, AppTheme.spacingMD)
    }

    // MARK: - CTA Buttons (rounded rectangle, full width)

    private var ctaButtons: some View {
        VStack(spacing: 12) {
            NavigationLink {
                PhoneAuthView().environmentObject(authVM)
            } label: {
                Text(localization.t("welcome.getStarted"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .fill(AppTheme.roseGradient)
                    )
            }

            NavigationLink {
                PhoneAuthView().environmentObject(authVM)
            } label: {
                Text(localization.t("welcome.haveAccount"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.rose)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(AppTheme.rose, lineWidth: 1.5)
                    )
            }
        }
        .padding(.horizontal, AppTheme.spacingMD)
    }

    // MARK: - How It Works

    private var howItWorksSection: some View {
        VStack(spacing: 16) {
            Text(localization.t("welcome.howItWorks"))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(colors.textPrimary)
                .padding(.bottom, 4)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                stepCard(step: step, index: index)
            }
        }
        .padding(.horizontal, AppTheme.spacingMD)
    }

    private func stepCard(
        step: (number: String, titleKey: String, subtitleKey: String),
        index: Int
    ) -> some View {
        ContentCard {
            HStack(spacing: 14) {
                Text(step.number)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.roseGradient)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.t(step.titleKey))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)

                    Text(localization.t(step.subtitleKey))
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .opacity(animateSteps ? 1 : 0)
        .offset(x: animateSteps ? 0 : -20)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.8)
                .delay(Double(index) * 0.12),
            value: animateSteps
        )
    }

}
