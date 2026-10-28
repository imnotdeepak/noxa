import SwiftUI

enum NoxaWebLinks {
    static let support = URL(string: "https://noxaapp.com/support")!
    static let privacy = URL(string: "https://noxaapp.com/privacy")!
    static let terms = URL(string: "https://noxaapp.com/terms")!
}

struct LegalLinksView: View {
    var body: some View {
        HStack(spacing: 12) {
            Link("Privacy Policy", destination: NoxaWebLinks.privacy)
            Text("·")
                .accessibilityHidden(true)
            Link("Terms of Use", destination: NoxaWebLinks.terms)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

struct SettingsSupportLinksView: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsExternalLink(
                title: "Support",
                icon: "questionmark.bubble.fill",
                color: .blue,
                destination: NoxaWebLinks.support
            )

            settingsDivider

            SettingsExternalLink(
                title: "Terms of Use",
                icon: "doc.text.fill",
                color: Color(red: 0.40, green: 0.62, blue: 1.0),
                destination: NoxaWebLinks.terms
            )

            settingsDivider

            SettingsExternalLink(
                title: "Privacy Policy",
                icon: "hand.raised.fill",
                color: NoxaTheme.accent,
                destination: NoxaWebLinks.privacy
            )
        }
        .noxaStatsCard(padding: 0)
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(NoxaTheme.subtleBorder)
            .padding(.leading, 62)
    }
}

private struct SettingsExternalLink: View {
    let title: String
    let icon: String
    let color: Color
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)

                Text(title)
                    .font(NoxaTheme.font(17, weight: .semibold))
                    .foregroundStyle(NoxaTheme.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
