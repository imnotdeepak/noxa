import SwiftUI

/// Type sizes for onboarding, all scaled with Dynamic Type.
enum OnboardingType {
    static let hero = NoxaTheme.font(38, weight: .bold, relativeTo: .largeTitle)
    static let question = NoxaTheme.font(31, weight: .semibold, relativeTo: .title)
    static let body = NoxaTheme.font(17, relativeTo: .body)
    static let option = NoxaTheme.font(17, weight: .medium, relativeTo: .body)
    static let label = NoxaTheme.font(13, weight: .semibold, relativeTo: .caption)
}

/// Shared frame for every onboarding step: a quiet top bar, scrolling
/// content, and actions pinned above the home indicator so they stay
/// reachable on small phones and at large text sizes.
struct OnboardingScaffold<Content: View, Actions: View>: View {
    var eyebrow: String?
    var centered = false
    var onBack: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let eyebrow {
                            OnboardingEyebrow(text: eyebrow)
                        }
                        content()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height,
                        alignment: centered ? .center : .topLeading
                    )
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                actions()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [NoxaTheme.background.opacity(0), NoxaTheme.background],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.25)
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .font(OnboardingType.body)
        .foregroundStyle(NoxaTheme.primaryText)
        .background(NoxaBackground())
    }

    private var topBar: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(NoxaTheme.primaryText)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text("noxa")
                .font(NoxaTheme.font(17, weight: .medium, relativeTo: .headline))
                .foregroundStyle(NoxaTheme.secondaryText)
                .accessibilityHidden(true)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }
}

struct OnboardingEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(OnboardingType.label)
            .tracking(1.4)
            .foregroundStyle(NoxaTheme.accent)
    }
}

/// A heading with optional supporting copy.
struct OnboardingHeading: View {
    let title: String
    var subtitle: String?
    var alignment: TextAlignment = .leading

    var body: some View {
        VStack(alignment: alignment == .center ? .center : .leading, spacing: 10) {
            Text(title)
                .font(OnboardingType.question)
                .tracking(-0.6)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .multilineTextAlignment(alignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

/// Full-width, text-only choices stacked in bordered rows. A chosen row
/// turns green and gains a checkmark, and VoiceOver hears "Selected", so
/// it never relies on color alone.
struct OnboardingOptionList<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let isSelected: (Option) -> Bool
    let toggle: (Option) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                let selected = isSelected(option)
                let shape = RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
                Button {
                    NoxaHaptics.selection()
                    toggle(option)
                } label: {
                    HStack(spacing: 12) {
                        Text(title(option))
                            .font(NoxaTheme.font(19, weight: selected ? .semibold : .regular, relativeTo: .title3))
                            .foregroundStyle(selected ? NoxaTheme.accent : NoxaTheme.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(NoxaTheme.accent)
                            .opacity(selected ? 1 : 0)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(selected ? NoxaTheme.accent.opacity(0.12) : Color.clear, in: shape)
                    .overlay {
                        shape.stroke(selected ? NoxaTheme.accent : NoxaTheme.border, lineWidth: selected ? 1.5 : 1)
                    }
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .noxaAnimation(NoxaMotion.snappy, value: selected)
            }
        }
    }
}

/// A quiet text action under the primary button.
struct OnboardingTextButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .font(NoxaType.subheadlineSemibold)
            .foregroundStyle(NoxaTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled = true
    let action: () -> Void

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoxaPrimaryButtonStyle())
        .disabled(!isEnabled)
    }
}

/// A number that counts to its value when changed inside an animation.
struct RollingNumber: View, Animatable {
    var value: Double
    var fractionDigits = 0

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(TimeProjection.format(value, maximumFractionDigits: fractionDigits))
            .monospacedDigit()
    }
}

/// A plain status line with an icon, used for permission and setup states.
struct OnboardingStatusLabel: View {
    let text: String
    let symbol: String
    var color: Color = NoxaTheme.accent
    var isCentered = false

    var body: some View {
        Label {
            Text(text)
                .multilineTextAlignment(isCentered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(NoxaType.subheadlineSemibold)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
    }
}
