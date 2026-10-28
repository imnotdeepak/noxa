import SwiftUI
import UIKit

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

    enum Spacing {
        /// Horizontal inset shared by every top-level screen.
        static let screen: CGFloat = 16
        /// Gap between cards and between a header and the first card.
        static let section: CGFloat = 16
        static let card: CGFloat = 18
        /// Gap between rows inside a card.
        static let row: CGFloat = 12
    }

    enum Radius {
        static let card: CGFloat = 22
        static let control: CGFloat = 16
        static let field: CGFloat = 14
    }
}

/// Feedback for physical touches and meaningful outcomes. Keep it sparing:
/// selection ticks for choices, taps for confirmations, notifications for results.
enum NoxaHaptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Springs are interruptible and carry velocity, so every state change uses
/// one of these instead of a fixed-duration ease.
enum NoxaMotion {
    /// Taps, presses and small toggles.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// Cards appearing, expanding or rearranging.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.84)
}

private struct NoxaAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Animates changes to `value`, and does nothing when Reduce Motion is on.
    func noxaAnimation<Value: Equatable>(
        _ animation: Animation = NoxaMotion.spring,
        value: Value
    ) -> some View {
        modifier(NoxaAnimationModifier(animation: animation, value: value))
    }
}

/// The one type scale. Every screen picks from here so the app reads as a
/// single typeface at consistent sizes that still follow Dynamic Type.
enum NoxaType {
    static let title = NoxaTheme.font(31, weight: .bold, relativeTo: .largeTitle)
    static let title2 = NoxaTheme.font(22, weight: .semibold, relativeTo: .title2)
    static let headline = NoxaTheme.font(17, weight: .semibold, relativeTo: .headline)
    static let body = NoxaTheme.font(16, relativeTo: .body)
    static let subheadline = NoxaTheme.font(15, relativeTo: .subheadline)
    static let subheadlineMedium = NoxaTheme.font(15, weight: .medium, relativeTo: .subheadline)
    static let subheadlineSemibold = NoxaTheme.font(15, weight: .semibold, relativeTo: .subheadline)
    static let footnote = NoxaTheme.font(13, relativeTo: .footnote)
    static let footnoteMedium = NoxaTheme.font(13, weight: .medium, relativeTo: .footnote)
    static let footnoteSemibold = NoxaTheme.font(13, weight: .semibold, relativeTo: .footnote)
    static let caption = NoxaTheme.font(12, relativeTo: .caption)
    static let captionSemibold = NoxaTheme.font(12, weight: .semibold, relativeTo: .caption)
    static let captionBold = NoxaTheme.font(12, weight: .bold, relativeTo: .caption)
    static let caption2 = NoxaTheme.font(11, relativeTo: .caption2)
    static let caption2Bold = NoxaTheme.font(11, weight: .bold, relativeTo: .caption2)
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
    @State private var isOrbRotating = false

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
                .rotationEffect(.degrees(isOrbRotating ? 360 : 0))
                .animation(
                    .linear(duration: 2.2).repeatForever(autoreverses: false),
                    value: isOrbRotating
                )
                .onAppear {
                    isOrbRotating = true
                }
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
            .background(
                NoxaTheme.elevated,
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NoxaTheme.Radius.card, style: .continuous)
                    .stroke(NoxaTheme.subtleBorder, lineWidth: 1)
            }
    }
}

/// Stats tiles share the standard card surface so every screen matches.
typealias NoxaStatsCardModifier = NoxaGlassCardModifier

/// Title block shared by the top-level tabs: one headline and one supporting line.
struct NoxaScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(NoxaType.title)
                .tracking(-0.7)
                .foregroundStyle(NoxaTheme.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(NoxaType.body)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Icon, title and optional trailing detail used at the top of a card.
struct NoxaCardHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(NoxaTheme.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(NoxaType.headline)
                .foregroundStyle(NoxaTheme.primaryText)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension NoxaCardHeader where Trailing == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

struct NoxaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(NoxaType.body)
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NoxaTheme.Radius.field, style: .continuous)
                    .stroke(NoxaTheme.subtleBorder, lineWidth: 1)
            }
    }
}

struct NoxaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaType.headline)
            .foregroundStyle(.black.opacity(0.9))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                NoxaTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.3),
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .noxaAnimation(NoxaMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed && isEnabled { NoxaHaptics.tap(.medium) }
            }
    }
}

struct NoxaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaType.subheadlineSemibold)
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.13 : 0.08),
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
                    .stroke(NoxaTheme.subtleBorder, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .noxaAnimation(NoxaMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed && isEnabled { NoxaHaptics.tap(.light) }
            }
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
