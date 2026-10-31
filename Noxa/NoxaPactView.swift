import CoreHaptics
import SwiftUI
import UIKit

/// Step 13. A promise made by holding the center for five seconds while lime
/// rises to fill the whole screen and the phone vibrates. Releasing early
/// resets it and records nothing.
struct NoxaPactView: View {
    static let holdDuration: TimeInterval = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Set while the finger is down; the fill is read from the clock each
    /// frame, so no re-render or animation transaction can stall it.
    @State private var holdStart: Date?
    /// The fill when not holding: animated back to 0 on release, 1 when done.
    @State private var settledFill: CGFloat = 0
    @State private var isComplete = false
    @State private var wasInterrupted = false
    @State private var holdTask: Task<Void, Never>?
    @State private var haptics = PactHaptics()
    let onFinish: (PactStatus) -> Void

    private let buttonDiameter: CGFloat = 132

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: holdStart == nil)) { context in
            let fill = fill(at: context.date)
            ZStack {
                NoxaTheme.background.ignoresSafeArea()

                // The whole screen turns lime: rising from the bottom, or
                // fading in when Reduce Motion is on.
                NoxaTheme.accent
                    .ignoresSafeArea()
                    .scaleEffect(x: 1, y: reduceMotion ? 1 : max(fill, 0.001), anchor: .bottom)
                    .opacity(reduceMotion ? fill : (fill > 0 ? 1 : 0))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                content(fill: fill)
            }
        }
        // Fixed: changing the color scheme mid-hold cancels the touch.
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            if phase != .active { cancelHold() }
        }
        .onDisappear {
            holdTask?.cancel()
            haptics.stop()
        }
    }

    private var isHolding: Bool { holdStart != nil }

    private func fill(at date: Date) -> CGFloat {
        guard let holdStart else { return settledFill }
        return CGFloat(min(max(date.timeIntervalSince(holdStart) / Self.holdDuration, 0), 1))
    }

    private func content(fill: CGFloat) -> some View {
        // How far each area has turned dark, 0...1, so text fades to black
        // as the lime passes behind it instead of switching at once.
        let top = fade(fill, from: reduceMotion ? 0.3 : 0.62, to: reduceMotion ? 0.7 : 0.86)
        let bottom = fade(fill, from: reduceMotion ? 0.3 : 0.04, to: reduceMotion ? 0.7 : 0.2)
        return VStack(spacing: 0) {
            VStack(spacing: 14) {
                Text("THE NOXA PACT")
                    .font(OnboardingType.label)
                    .tracking(1.4)
                    .foregroundStyle(blend(NoxaTheme.accent, Color.black.opacity(0.7), top))
                Text(isComplete ? "Your time is yours to protect." : "A promise to yourself.")
                    .font(OnboardingType.hero)
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(blend(NoxaTheme.primaryText, .black, top))
                    .accessibilityAddTraits(.isHeader)
                if !isComplete {
                    Text("I choose to protect my attention, build healthier habits, and make more room for the life I want to live.")
                        .font(NoxaTheme.font(19, relativeTo: .body))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(blend(NoxaTheme.secondaryText, Color.black.opacity(0.8), top))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)

            Spacer(minLength: 24)

            holdButton(fill: fill)

            Spacer(minLength: 24)

            Text(instruction)
                .font(NoxaType.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(blend(NoxaTheme.secondaryText, Color.black.opacity(0.75), bottom))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isComplete ? 0 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
    }

    private func holdButton(fill: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(NoxaTheme.elevated)
            Circle()
                .stroke(Color.white, lineWidth: 2)
            Image(systemName: isComplete ? "checkmark" : "hand.point.up.left.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(isComplete ? NoxaTheme.accent : NoxaTheme.primaryText)
        }
        .frame(width: buttonDiameter, height: buttonDiameter)
        .scaleEffect(isHolding && !reduceMotion ? 0.94 : 1)
        .animation(NoxaMotion.snappy, value: isHolding)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in cancelHold() }
        )
        .allowsHitTesting(!isComplete)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isComplete ? "Pact made" : "Make your pact")
        .accessibilityHint("Press and hold for five seconds.")
        .accessibilityAddTraits(.isButton)
        // VoiceOver and Switch Control users can't always hold, so the
        // same result stays available as an accessibility action.
        .accessibilityAction(named: "Make my pact") { complete() }
    }

    private func fade(_ fill: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        min(max((fill - start) / (end - start), 0), 1)
    }

    /// Mixes two colors, opacity included; `Color.mix` needs iOS 18.
    private func blend(_ from: Color, _ to: Color, _ amount: CGFloat) -> Color {
        var a = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), o: CGFloat(0))
        var b = a
        UIColor(from).getRed(&a.r, green: &a.g, blue: &a.b, alpha: &a.o)
        UIColor(to).getRed(&b.r, green: &b.g, blue: &b.b, alpha: &b.o)
        let mix = { (x: CGFloat, y: CGFloat) in x + (y - x) * amount }
        return Color(red: mix(a.r, b.r), green: mix(a.g, b.g), blue: mix(a.b, b.b), opacity: mix(a.o, b.o))
    }

    private var instruction: String {
        wasInterrupted
            ? "Whenever you're ready. Hold to make your pact."
            : "Press and hold for five seconds to make your pact."
    }

    private func beginHold() {
        guard !isHolding, !isComplete else { return }
        holdStart = Date()
        haptics.start(duration: Self.holdDuration)
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.holdDuration * 1_000_000_000))
            guard !Task.isCancelled, isHolding else { return }
            finishHold()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        haptics.stop()
        guard isHolding, !isComplete else { return }
        // Freeze at the current level, then ease back to empty.
        settledFill = fill(at: Date())
        holdStart = nil
        wasInterrupted = true
        withAnimation(.easeOut(duration: 0.4)) { settledFill = 0 }
    }

    private func complete() {
        guard !isComplete else { return }
        holdTask?.cancel()
        holdTask = nil
        settledFill = fill(at: Date())
        holdStart = nil
        withAnimation(.easeInOut(duration: 0.6)) { settledFill = 1 }
        finishHold()
    }

    private func finishHold() {
        haptics.stop()
        holdStart = nil
        settledFill = 1
        isComplete = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Pact made. Your time is yours to protect.")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            onFinish(.completed)
        }
    }
}

/// A continuous vibration that builds over the hold. Uses Core Haptics where
/// the phone supports it, and quick taps where it doesn't. Stops instantly.
@MainActor
private final class PactHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var fallbackTask: Task<Void, Never>?

    func start(duration: TimeInterval) {
        stop()
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics, startContinuous(duration: duration) {
            return
        }
        fallbackTask = Task { @MainActor in
            let steps = Int(duration / 0.15)
            for step in 0..<steps {
                let intensity = 0.3 + 0.7 * CGFloat(step) / CGFloat(max(steps - 1, 1))
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return }
            }
        }
    }

    func stop() {
        fallbackTask?.cancel()
        fallbackTask = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private func startContinuous(duration: TimeInterval) -> Bool {
        do {
            if engine == nil {
                let engine = try CHHapticEngine()
                engine.isAutoShutdownEnabled = true
                engine.resetHandler = { [weak engine] in try? engine?.start() }
                self.engine = engine
            }
            try engine?.start()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
                ],
                relativeTime: 0,
                duration: duration
            )
            // Starts soft and builds toward the end of the hold.
            let curve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: 0.3),
                    .init(relativeTime: duration * 0.6, value: 0.6),
                    .init(relativeTime: duration, value: 1)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [curve])
            let player = try engine?.makeAdvancedPlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
            self.player = player
            return player != nil
        } catch {
            return false
        }
    }
}
