import SwiftUI

/// Static legal / policy pages (Community Guidelines, Privacy Policy, Terms of
/// Service). Content is kept in sync with the Android screens in
/// `ui/pages/{Guidelines,Privacy,Terms}Screen.kt`. Pushed onto the existing
/// NavigationStack from the Welcome footer (and Settings), so the system
/// back button handles dismissal.
enum LegalPage {
    case guidelines
    case privacy
    case terms

    var navTitle: String {
        switch self {
        case .guidelines: return "Community Guidelines"
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Service"
        }
    }

    var lastUpdated: String { "Last Updated: March 15, 2026" }

    /// (heading, body) pairs, mirroring the Android LegalSection calls.
    var sections: [(title: String, body: String)] {
        switch self {
        case .guidelines:
            return [
                ("1. Be Authentic",
                 "Use your real name and recent photos. Represent yourself honestly — your age, occupation, and intentions. Fake profiles undermine trust in our community."),
                ("2. Be Respectful",
                 "Treat every member with dignity. No harassment, hate speech, or discrimination based on gender, religion, caste, or background. Respect boundaries — if someone isn't interested, move on gracefully."),
                ("3. Keep It Safe",
                 "Never share personal financial information. Don't ask for money or make financial requests. Report suspicious behavior immediately. Meet in public places for first dates."),
                ("4. Zero Tolerance",
                 "The following result in permanent removal:\n• Sexual harassment or unsolicited explicit content\n• Threats of violence or intimidation\n• Impersonation or catfishing\n• Scams or financial exploitation\n• Sharing others' private information\n• Underage users"),
                ("5. Photo Guidelines",
                 "All photos must be of you. No group photos as your primary photo. No explicit or suggestive content. No photos of minors. Selfie verification may be required."),
                ("6. Family Mode Etiquette",
                 "Family members must respect the user's privacy. Messages are never visible to family. Suggestions should be made respectfully. The primary user has full control over permissions."),
                ("7. Strike System",
                 "• First violation: Warning\n• Second violation: 7-day suspension\n• Third violation: Permanent ban\n\nSevere violations may result in immediate permanent removal."),
                ("8. Report a Concern",
                 "Use the in-app report feature on any profile or message. Reports are reviewed within 24 hours. Your identity is kept confidential. False reports may result in action against your account."),
            ]
        case .privacy:
            return [
                ("1. Introduction",
                 "MitiMaiti (\"we\", \"our\", \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and share information when you use our mobile application and services."),
                ("2. Information We Collect",
                 "2.1 Information You Provide:\n• Phone number for authentication\n• Profile information (name, age, gender, photos, bio)\n• Cultural data (Sindhi fluency, dialect, community, gotra)\n• Kundli details (if provided)\n• Messages and chat content\n• Reports and feedback\n\n2.2 Information Collected Automatically:\n• Device information (model, OS version)\n• Usage data (features used, time spent)\n• IP address and approximate location\n• Notification interaction data"),
                ("3. How We Use Your Information",
                 "• To create and maintain your account\n• To match you with compatible users based on cultural and personal preferences\n• To facilitate messaging and connections\n• To verify your identity and ensure safety\n• To improve our services and algorithms\n• To send notifications about matches, messages, and app updates"),
                ("4. Data Sharing",
                 "We share data only with essential service providers:\n• Supabase (database and authentication)\n• AWS Rekognition (photo verification)\n• Firebase (push notifications)\n• Twilio (SMS verification)\n\nWe never sell your personal data to third parties."),
                ("5. Data Retention",
                 "We retain your data while your account is active. Upon account deletion, your data is permanently removed within 30 days. Anonymized usage data may be retained for analytics."),
                ("6. Your Rights (GDPR / DPDP)",
                 "You have the right to:\n• Access your personal data\n• Correct inaccurate data\n• Request deletion of your data\n• Export your data in a portable format\n• Withdraw consent for data processing\n• Object to automated decision-making"),
                ("7. Security",
                 "We implement industry-standard security measures including encryption in transit (TLS) and at rest, secure authentication tokens, and regular security audits."),
                ("8. Children's Privacy",
                 "MitiMaiti is not intended for users under 18. We do not knowingly collect information from minors. If we discover an underage user, we will immediately delete their account."),
                ("9. Contact Us",
                 "For privacy-related inquiries, contact us at privacy@mitimaiti.com or through the in-app support feature."),
            ]
        case .terms:
            return [
                ("1. Acceptance of Terms",
                 "By accessing or using MitiMaiti, you agree to be bound by these Terms of Service. If you do not agree, do not use our services."),
                ("2. Eligibility",
                 "You must be at least 18 years old to use MitiMaiti. By creating an account, you represent and warrant that you meet this age requirement and have the legal capacity to enter into this agreement."),
                ("3. The MitiMaiti Service",
                 "3.1 Respect-First Messaging\nOur messaging system is designed for meaningful conversations. When you match with someone, one person sends the first message. The other has 24 hours to reply before the match expires. This encourages genuine engagement.\n\n3.2 Family Mode\nYou may invite up to 3 family members to your circle. Family members can view permitted profile sections and suggest matches based on your permission settings. Messages are never visible to family members."),
                ("4. User Conduct",
                 "You agree to:\n• Provide accurate information\n• Use the service for its intended purpose\n• Respect other users' boundaries\n• Not engage in harassment, spam, or fraudulent activity\n• Not use automated tools or bots\n• Not share explicit or inappropriate content"),
                ("5. Content Moderation",
                 "We employ a 3-layer moderation system:\n• Automated content scanning for explicit material\n• AI-assisted review of reported content\n• Human review for escalated cases\n\nViolations follow our strike system: Warning → 7-day suspension → Permanent ban."),
                ("6. Daily Limits",
                 "Free accounts are subject to daily limits:\n• 50 likes per day\n• 10 rewinds per day\n• Up to 3 family members\nThese limits reset at midnight in your local timezone."),
                ("7. Account Termination",
                 "You may delete your account at any time through Settings. Your account will be deactivated immediately and permanently deleted after 30 days. You can reactivate by logging in within the 30-day window.\n\nWe reserve the right to suspend or terminate accounts that violate these terms."),
                ("8. Disclaimer",
                 "MitiMaiti is provided \"as is\" without warranties of any kind. We do not guarantee matches, compatibility, or outcomes. Cultural and kundli scores are based on self-reported data and are for reference only."),
                ("9. Contact",
                 "For questions about these Terms, contact us at legal@mitimaiti.com or through the in-app support feature."),
            ]
        }
    }
}

struct LegalView: View {
    let page: LegalPage
    @Environment(\.adaptiveColors) private var colors

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text(page.lastUpdated)
                    .font(.system(size: 13))
                    .foregroundColor(colors.textMuted)

                ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text(section.body)
                            .font(.system(size: 15))
                            .foregroundColor(colors.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer().frame(height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .appBackground()
        .navigationTitle(page.navTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
