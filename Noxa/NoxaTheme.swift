import SwiftUI

enum NoxaTheme {
    static let background = Color(red: 7.0 / 255.0, green: 21.0 / 255.0, blue: 15.0 / 255.0)
    static let elevated = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.13)
    static let subtleBorder = Color.white.opacity(0.075)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.58)
    static let accent = Color(red: 138.0 / 255.0, green: 206.0 / 255.0, blue: 0)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.36)

    static func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom("Helvetica Neue", size: size, relativeTo: style)
            .weight(weight)
    }
}

struct NoxaBackground: View {
    var body: some View {
        ZStack {
            NoxaTheme.background

            LinearGradient(
                colors: [
                    Color(red: 11.0 / 255.0, green: 31.0 / 255.0, blue: 22.0 / 255.0),
                    NoxaTheme.background,
                    Color(red: 5.0 / 255.0, green: 16.0 / 255.0, blue: 11.0 / 255.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// A top-lit variation used throughout account creation and onboarding. The
/// green wash fades into the dark background near the primary input area.
struct NoxaOnboardingBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                NoxaTheme.background

                LinearGradient(
                    colors: [
                        NoxaTheme.accent.opacity(0.25),
                        NoxaTheme.accent.opacity(0.12),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.height * 0.58)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct NoxaLoadingView: View {
    let message: String

    var body: some View {
        ZStack {
            NoxaBackground()

            VStack(spacing: 22) {
                ThinkingOrb(
                    state: .searching,
                    size: .px64,
                    theme: .dark,
                    displaySize: 76
                )
                .accessibilityHidden(true)

                Text(message)
                    .font(NoxaTheme.font(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

struct NoxaGlassCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), NoxaTheme.subtleBorder],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.24), radius: 24, y: 14)
    }
}

struct NoxaStatsCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.075), lineWidth: 1)
            }
    }
}

struct NoxaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaTheme.font(17, weight: .semibold))
            .foregroundStyle(.black.opacity(0.9))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                LinearGradient(
                    colors: isEnabled
                        ? [NoxaTheme.accent, NoxaTheme.accent.opacity(0.86)]
                        : [NoxaTheme.accent.opacity(0.34), NoxaTheme.accent.opacity(0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NoxaTheme.accent.opacity(0.75), lineWidth: 1)
            }
            .shadow(
                color: NoxaTheme.accent.opacity(configuration.isPressed ? 0.08 : 0.22),
                radius: 14,
                y: 5
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.62)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct NoxaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaTheme.font(16, weight: .semibold))
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(configuration.isPressed ? Color.white.opacity(0.24) : NoxaTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    func noxaCard(padding: CGFloat = 18) -> some View {
        modifier(NoxaGlassCardModifier(padding: padding))
    }

    func noxaStatsCard(padding: CGFloat = 18) -> some View {
        modifier(NoxaStatsCardModifier(padding: padding))
    }

    func noxaScreenBackground() -> some View {
        background(NoxaBackground())
    }
}
