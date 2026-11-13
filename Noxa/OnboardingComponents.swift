import SwiftUI
import UIKit

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
    /// Space between the top bar and the first item.
    var topSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .onboardingFadeUp()
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Top text first, then whatever follows it (options,
                        // cards), one after another, then the actions.
                        _VariadicView.Tree(OnboardingStaggerRoot()) {
                            if let eyebrow {
                                OnboardingEyebrow(text: eyebrow)
                            }
                            content()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, topSpacing)
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
            .onboardingFadeUp(delay: OnboardingReveal.actionsDelay)
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
        // Transparent: OnboardingView draws the step-aware backdrop behind.
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
            // The setup progress bar is drawn here by OnboardingView.
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

/// Full-width choices stacked in bordered rows, each with an optional
/// symbol. A chosen row turns green and gains a checkmark, and VoiceOver
/// hears "Selected", so it never relies on color alone.
struct OnboardingOptionList<Option: Hashable>: View {
    @Environment(\.onboardingRevealDelay) private var revealDelay
    let options: [Option]
    let title: (Option) -> String
    var symbol: ((Option) -> String)? = nil
    let isSelected: (Option) -> Bool
    let toggle: (Option) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                let selected = isSelected(option)
                let row = Double(options.firstIndex(of: option) ?? 0)
                let shape = RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
                Button {
                    NoxaHaptics.selection()
                    toggle(option)
                } label: {
                    HStack(spacing: 14) {
                        if let symbol {
                            OnboardingOptionIcon(symbol: symbol(option), isSelected: selected)
                        }
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
                    .padding(.leading, symbol == nil ? 18 : 12)
                    .padding(.trailing, 18)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(selected ? NoxaTheme.accent.opacity(0.12) : Color.clear, in: shape)
                    .overlay {
                        shape.stroke(selected ? NoxaTheme.accent : NoxaTheme.border, lineWidth: selected ? 1.5 : 1)
                    }
                    .overlay {
                        if selected {
                            OnboardingSelectionOrbit(cornerRadius: NoxaTheme.Radius.control)
                        }
                    }
                    .contentShape(shape)
                }
                .buttonStyle(OnboardingOptionButtonStyle())
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .noxaAnimation(NoxaMotion.snappy, value: selected)
                .onboardingFadeUp(delay: revealDelay + row * OnboardingReveal.rowStep)
            }
        }
    }
}

/// The small symbol tile at the start of an option row. It fills green and
/// gives a quick bounce when chosen.
struct OnboardingOptionIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let symbol: String
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? Color.black.opacity(0.85) : NoxaTheme.accent)
            .modifier(OnboardingSymbolBounce(trigger: isSelected, isEnabled: !reduceMotion))
            .frame(width: 34, height: 34)
            .background(
                isSelected ? NoxaTheme.accent : NoxaTheme.olive.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private struct OnboardingSymbolBounce: ViewModifier {
    let trigger: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), isEnabled {
            content.symbolEffect(.bounce, value: trigger)
        } else {
            content
        }
    }
}

/// A quick press response for option rows: a slight shrink and brighten
/// while the finger is down, or just the brighten with Reduce Motion.
struct OnboardingOptionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(reduceMotion ? nil : NoxaMotion.snappy, value: configuration.isPressed)
    }
}

/// The onboarding canvas: Noxa's plain near-black.
struct OnboardingBackdrop: View {
    var body: some View {
        NoxaBackground()
            .accessibilityHidden(true)
    }
}

/// A slim bar showing how far through setup the user is.
struct OnboardingProgressBar: View {
    static let height: CGFloat = 6
    static let width: CGFloat = 190

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(NoxaTheme.border)
                Capsule()
                    .fill(NoxaTheme.accent)
                    .frame(width: max(geometry.size.width * min(max(fraction, 0), 1), OnboardingProgressBar.height))
            }
        }
        .frame(height: OnboardingProgressBar.height)
        .animation(reduceMotion ? nil : NoxaMotion.spring, value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Timing for the page entrance: top text, then content, then actions.
enum OnboardingReveal {
    /// How long each item takes to fade up.
    static let duration: TimeInterval = 0.8
    /// How far each item rises as it fades in, in points.
    static let distance: CGFloat = 22
    /// Stretches every entrance delay below, and the ones passed to
    /// `onboardingFadeUp(delay:)`, so the whole sequence slows evenly.
    static let pace: TimeInterval = 1.6
    /// Delay before the first item (the eyebrow or heading).
    static let start: TimeInterval = 0.05
    /// Gap between consecutive top-level items on a page.
    static let step: TimeInterval = 0.15
    /// Items after this many share its delay, so long pages don't drag.
    static let maxStaggeredIndex = 4
    /// Gap between consecutive option rows.
    static let rowStep: TimeInterval = 0.06
    /// The actions come in while the content is still arriving, so the
    /// button is ready without waiting for the whole entrance.
    static let actionsDelay: TimeInterval = 0.55
    /// Kept just above zero so items can be tapped while still fading in;
    /// SwiftUI skips fully transparent views when hit-testing.
    static let hiddenOpacity: Double = 0.001
}

private struct OnboardingRevealDelayKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 0
}

extension EnvironmentValues {
    /// When the enclosing page item starts to appear, so nested rows can
    /// cascade after it.
    var onboardingRevealDelay: TimeInterval {
        get { self[OnboardingRevealDelayKey.self] }
        set { self[OnboardingRevealDelayKey.self] = newValue }
    }
}

/// Fades up each top-level child of a page in turn.
struct OnboardingStaggerRoot: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        ForEach(children) { child in
            let index = children.firstIndex { $0.id == child.id } ?? 0
            let delay = OnboardingReveal.start
                + Double(min(index, OnboardingReveal.maxStaggeredIndex)) * OnboardingReveal.step
            child
                .onboardingFadeUp(delay: delay)
                .environment(\.onboardingRevealDelay, delay)
        }
    }
}

private struct OnboardingFadeUpModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    let delay: TimeInterval

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isVisible ? 1 : OnboardingReveal.hiddenOpacity)
            .offset(y: reduceMotion || isVisible ? 0 : OnboardingReveal.distance)
            .onAppear {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(
                        .easeOut(duration: OnboardingReveal.duration)
                            .delay(delay * OnboardingReveal.pace)
                    ) {
                        isVisible = true
                    }
                }
            }
            .onChange(of: reduceMotion) { enabled in
                if enabled { isVisible = true }
            }
    }
}

extension View {
    func onboardingFadeUp(delay: TimeInterval = 0) -> some View {
        modifier(OnboardingFadeUpModifier(delay: delay))
    }
}

/// A smooth swell in the green border that travels around the whole
/// outline of a selected card. Driven by Core Animation in the render
/// server, so it keeps moving without SwiftUI timers or main-thread ticks.
/// With Reduce Motion on it draws nothing, leaving the static border.
struct OnboardingSelectionOrbit: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cornerRadius: CGFloat

    var body: some View {
        OnboardingOrbitLayer(cornerRadius: cornerRadius, isAnimated: !reduceMotion)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct OnboardingOrbitLayer: UIViewRepresentable {
    var cornerRadius: CGFloat
    var isAnimated: Bool

    func makeUIView(context: Context) -> OnboardingOrbitView {
        OnboardingOrbitView()
    }

    func updateUIView(_ view: OnboardingOrbitView, context: Context) {
        view.configure(cornerRadius: cornerRadius, isAnimated: isAnimated)
    }
}

final class OnboardingOrbitView: UIView {
    /// The card's own border width; the swell tapers back down to this.
    static let baseWidth: CGFloat = 1.5
    /// The border's width at the middle of the swell.
    static let peakWidth: CGFloat = 4.5
    /// Spread of the bell-shaped swell along the outline, in points.
    static let spread: CGFloat = 16
    /// Stacked strokes that build the taper; more makes it smoother.
    static let layerCount = 10
    /// Travel speed along the outline, in points per second.
    static let speed: CGFloat = 200
    static let animationKey = "noxa.orbit"

    /// Strokes on the same line as the card's border, all centered on one
    /// moving point: each is shorter and thicker than the last, so together
    /// they make the border swell smoothly from its normal width and back,
    /// instead of reading as a separate line sliding along it.
    private let strokes: [CAShapeLayer]
    private var cornerRadius: CGFloat = 0
    private var isAnimated = true
    private var animatedSize: CGSize = .zero
    private var foregroundObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        strokes = (0..<Self.layerCount).map { _ in CAShapeLayer() }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false
        let accent = UIColor(NoxaTheme.accent).cgColor
        for stroke in strokes {
            stroke.fillColor = UIColor.clear.cgColor
            stroke.strokeColor = accent
            stroke.lineCap = .round
            stroke.lineJoin = .round
            stroke.strokeStart = 0
            stroke.strokeEnd = 0
            layer.addSublayer(stroke)
        }
        // Animations are dropped when the app is backgrounded; re-add them.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartAnimation()
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    func configure(cornerRadius: CGFloat, isAnimated: Bool) {
        let changed = cornerRadius != self.cornerRadius || isAnimated != self.isAnimated
        self.cornerRadius = cornerRadius
        self.isAnimated = isAnimated
        if changed { restartAnimation() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restartAnimation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != animatedSize { restartAnimation() }
    }

    /// Rebuilds the path and animation for the current size and settings.
    private func restartAnimation() {
        for stroke in strokes { stroke.removeAnimation(forKey: Self.animationKey) }
        animatedSize = bounds.size
        guard isAnimated, window != nil, bounds.width > 1, bounds.height > 1 else {
            for stroke in strokes { stroke.isHidden = true }
            return
        }

        // The outline sits exactly on the card's border, drawn twice in a
        // row: sliding over the first lap loops seamlessly, with no jump
        // where the path starts and ends.
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        let outline = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        let doubled = CGMutablePath()
        doubled.addPath(outline)
        doubled.addPath(outline)

        let perimeter = 2 * (bounds.width + bounds.height) - (8 - 2 * .pi) * radius
        let duration = CFTimeInterval(perimeter / Self.speed)

        // Each stroke covers the stretch where a bell curve of the border's
        // width is at least that stroke's width, less its round caps.
        let rise = Self.peakWidth - Self.baseWidth
        let halfLengths: [(width: CGFloat, half: CGFloat)] = (1...Self.layerCount).map { step in
            let width = Self.baseWidth + rise * CGFloat(step) / CGFloat(Self.layerCount)
            let reach = Self.spread * sqrt(2 * log(rise / max(width - Self.baseWidth, 0.01)))
            let half = max(reach - width / 2, 0.5)
            // As a fraction of the doubled path.
            return (width, half / (2 * perimeter))
        }
        let lead = halfLengths.map(\.half).max() ?? 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (stroke, profile) in zip(strokes, halfLengths) {
            stroke.frame = bounds
            stroke.path = doubled
            stroke.lineWidth = profile.width
            stroke.isHidden = false
            stroke.strokeStart = lead - profile.half
            stroke.strokeEnd = lead + profile.half

            // Every stroke shares the same center, moving one full lap.
            let start = CABasicAnimation(keyPath: "strokeStart")
            start.fromValue = lead - profile.half
            start.toValue = lead + 0.5 - profile.half
            let end = CABasicAnimation(keyPath: "strokeEnd")
            end.fromValue = lead + profile.half
            end.toValue = lead + 0.5 + profile.half
            let group = CAAnimationGroup()
            group.animations = [start, end]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            stroke.add(group, forKey: Self.animationKey)
        }
        CATransaction.commit()
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
