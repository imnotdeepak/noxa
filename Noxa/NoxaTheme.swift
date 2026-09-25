import SwiftUI

enum NoxaTheme {
    static let background = Color(red: 0.025, green: 0.027, blue: 0.032)
    static let elevated = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.13)
    static let subtleBorder = Color.white.opacity(0.075)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.58)
    static let accent = Color(red: 0.56, green: 0.95, blue: 0.72)
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

            RadialGradient(
                colors: [NoxaTheme.accent.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 430
            )

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.42)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

/// A quieter, edge-lit variation used only throughout account creation and
/// onboarding. The soft olive outline is drawn in SwiftUI so it stays crisp at
/// every iPhone size and never includes branding from a visual reference.
struct NoxaOnboardingBackground: View {
    var body: some View {
        ZStack {
            NoxaTheme.background

            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .stroke(
                    Color(red: 0.55, green: 0.68, blue: 0.36).opacity(0.42),
                    lineWidth: 8
                )
                .blur(radius: 14)
                .padding(10)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct NoxaLoadingView: View {
    let message: String
    @State private var rotation = 0.0
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            NoxaBackground()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 2)
                    Circle()
                        .trim(from: 0.08, to: 0.7)
                        .stroke(
                            NoxaTheme.accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(rotation))

                    Text("N")
                        .font(NoxaTheme.font(24, weight: .medium, relativeTo: .title2))
                        .foregroundStyle(NoxaTheme.primaryText)
                        .scaleEffect(isPulsing ? 1.04 : 0.96)
                }
                .frame(width: 72, height: 72)

                Text(message)
                    .font(NoxaTheme.font(15, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaTheme.font(17, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .overlay { Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1) }
            .shadow(color: .white.opacity(configuration.isPressed ? 0.08 : 0.16), radius: 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
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
