import SwiftUI
import UIKit

enum NoxaTheme {
    // Tokens from the v3 design system: black UI with green light.
    static let background = Color(hex: 0x030503)
    static let backgroundSecondary = Color(hex: 0x070A07)
    static let surface = Color(hex: 0x101410)
    static let elevated = Color(hex: 0x171B17)
    static let pressed = Color(hex: 0x222922)
    static let border = Color(hex: 0x293029)
    static let subtleBorder = Color(hex: 0x293029).opacity(0.6)
    static let primaryText = Color(hex: 0xF4F7F2)
    static let secondaryText = Color(hex: 0xA8B0A5)
    static let tertiaryText = Color(hex: 0x858F82)
    static let accent = Color(hex: 0xA8F000)
    static let accentBright = Color(hex: 0xC7FF57)
    static let accentMuted = Color(hex: 0x799A50)
    static let accentSoft = Color(hex: 0x7FBF2A)
    static let olive = Color(hex: 0x32421E)
    /// Cards are lit from the top left.
    static let surfaceGradient = LinearGradient(
        colors: [Color(hex: 0x171C17), Color(hex: 0x101410), Color(hex: 0x0D110D)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.36)
    /// Light used only around the Focus Halo and chart points.
    static let glow = Color(hex: 0xA8F000).opacity(0.12)

    static func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(fontFamily, size: size, relativeTo: style)
            .weight(weight)
    }

    /// Inter once its font files are bundled and registered, else the
    /// current fallback, so adding the files is the only change needed.
    private static let fontFamily = UIFont.familyNames.contains("Inter") ? "Inter" : "Helvetica Neue"


    enum Spacing {
        /// Horizontal inset shared by every top-level screen.
        static let screen: CGFloat = 20
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
    static let title = NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle)
    static let title2 = NoxaTheme.font(24, weight: .semibold, relativeTo: .title2)
    static let headline = NoxaTheme.font(18, weight: .semibold, relativeTo: .headline)
    static let body = NoxaTheme.font(17, relativeTo: .body)
    static let subheadline = NoxaTheme.font(16, relativeTo: .subheadline)
    static let subheadlineMedium = NoxaTheme.font(16, weight: .medium, relativeTo: .subheadline)
    static let subheadlineSemibold = NoxaTheme.font(16, weight: .semibold, relativeTo: .subheadline)
    static let footnote = NoxaTheme.font(15, relativeTo: .footnote)
    static let footnoteMedium = NoxaTheme.font(15, weight: .medium, relativeTo: .footnote)
    static let footnoteSemibold = NoxaTheme.font(15, weight: .semibold, relativeTo: .footnote)
    static let caption = NoxaTheme.font(14, relativeTo: .caption)
    static let captionSemibold = NoxaTheme.font(14, weight: .semibold, relativeTo: .caption)
    static let captionBold = NoxaTheme.font(14, weight: .bold, relativeTo: .caption)
    static let caption2 = NoxaTheme.font(13, relativeTo: .caption2)
    static let caption2Bold = NoxaTheme.font(13, weight: .bold, relativeTo: .caption2)
    /// Timers and headline stats: large, tight and evenly spaced digits.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default).monospacedDigit()
    }
}

struct NoxaBackground: View {
    var body: some View {
        NoxaTheme.background
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Account creation and onboarding share the same black canvas.
typealias NoxaOnboardingBackground = NoxaBackground

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
                NoxaTheme.surfaceGradient,
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.card, style: .continuous)
            )
            .overlay {
                // A faint top-edge highlight, then a quiet border.
                RoundedRectangle(cornerRadius: NoxaTheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), NoxaTheme.subtleBorder],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
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
    var info: String?
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
            if let info {
                NoxaInfoButton(title: title, message: info)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension NoxaCardHeader where Trailing == EmptyView {
    init(title: String, systemImage: String, info: String? = nil) {
        self.init(title: title, systemImage: systemImage, info: info) { EmptyView() }
    }
}

/// A small (i) that keeps the full explanation one tap away, so cards can
/// show a short line instead of a paragraph.
struct NoxaInfoButton: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            NoxaHaptics.selection()
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(NoxaType.subheadlineMedium)
                .foregroundStyle(NoxaTheme.secondaryText)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(NoxaType.headline)
                Text(message)
                    .font(NoxaType.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(18)
            .frame(idealWidth: 300, alignment: .leading)
            .background(NoxaTheme.background)
            .presentationCompactAdaptation(.popover)
        }
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
                NoxaTheme.elevated,
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.field, style: .continuous)
            )
    }
}

struct NoxaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaType.headline)
            .foregroundStyle(isEnabled ? Color.black.opacity(0.9) : NoxaTheme.tertiaryText)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            // Opaque even when disabled, so nothing behind it shows through.
            .background(
                isEnabled
                    ? AnyShapeStyle(NoxaTheme.accent.opacity(configuration.isPressed ? 0.88 : 1))
                    : AnyShapeStyle(NoxaTheme.pressed),
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
                configuration.isPressed ? NoxaTheme.pressed : NoxaTheme.elevated,
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
            )
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

    /// For screens without a navigation bar: a black band behind the status
    /// bar so scrolled content never sits under the clock or Dynamic Island.
    func noxaStatusBarScrim() -> some View {
        overlay(alignment: .top) {
            NoxaTheme.background
                .frame(height: 0)
                .background(NoxaTheme.background.ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
        }
    }
}

extension Color {
    /// A design-token color written as 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// An app row: the app's own icon at list size, then its name.
struct NoxaAppRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.icon
                .scaleEffect(1.6)
                .frame(width: 44, height: 44)
            configuration.title
                .font(NoxaType.body)
                .foregroundStyle(NoxaTheme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}
