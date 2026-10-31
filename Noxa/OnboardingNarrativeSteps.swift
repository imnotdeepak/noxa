import Charts
import SwiftUI

// MARK: Step 2 — Daily distracting screen-time estimate

struct OnboardingEstimateStep: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var minutes: Double
    let onContinue: () -> Void

    init(initialMinutes: Int?, onContinue: @escaping () -> Void) {
        _minutes = State(initialValue: Double(initialMinutes ?? 120))
        self.onContinue = onContinue
    }

    private var wholeMinutes: Int { Int(minutes) }

    var body: some View {
        OnboardingScaffold(eyebrow: "01 / Your time") {
            OnboardingHeading(
                title: "How much time do distractions take each day?",
                subtitle: "Think social feeds, videos, games, or browsing you wish you'd spent differently."
            )

            VStack(spacing: 4) {
                Text(TimeProjection.label(minutes: wholeMinutes))
                    .font(NoxaType.display(80))
                    .tracking(-2.5)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .noxaAnimation(NoxaMotion.snappy, value: wholeMinutes)
                Text("a day")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Slider(
                    value: $minutes,
                    in: 0...Double(TimeProjection.maximumMinutesPerDay),
                    step: Double(TimeProjection.sliderStep)
                ) {
                    Text("Time a day")
                }
                .tint(NoxaTheme.accent)
                .accessibilityValue("\(TimeProjection.spokenLabel(minutes: wholeMinutes)) a day")
                .onChange(of: wholeMinutes) { _ in NoxaHaptics.selection() }

                HStack {
                    Text("0m")
                    Spacer()
                    Text("3h")
                    Spacer()
                    Text("6h+")
                }
                .font(NoxaType.caption)
                .foregroundStyle(NoxaTheme.tertiaryText)
                .accessibilityHidden(true)
            }
            .padding(.top, 8)
        } actions: {
            OnboardingPrimaryButton("See my time") {
                if onboarding.saveEstimate(minutesPerDay: wholeMinutes) { onContinue() }
            }
        }
    }
}

// MARK: Step 3 — Personalized time projection

struct OnboardingProjectionStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var reveal: Double = 0
    let onBack: () -> Void
    let onContinue: () -> Void

    private var projection: TimeProjection {
        TimeProjection(
            minutesPerDay: onboarding.progress.estimatedDistractingMinutesPerDay
                ?? TimeProjection.exampleMinutesPerDay
        )
    }

    /// Cumulative full days at the user's pace and at half of it, month by month.
    private var points: [(month: Int, series: String, days: Double)] {
        (0...12).flatMap { month -> [(month: Int, series: String, days: Double)] in
            let now = projection.annualFullDays * Double(month) / 12 * reveal
            return [
                (month, Self.whereYouAre, now),
                (month, Self.whereYouCouldBe, now / 2)
            ]
        }
    }

    private static let whereYouAre = "Where you are"
    private static let whereYouCouldBe = "Where you could be"

    var body: some View {
        OnboardingScaffold(eyebrow: "Your time, visualized", onBack: onBack) {
            OnboardingHeading(title: "Small moments add up.")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RollingNumber(value: projection.annualFullDays * reveal, fractionDigits: 1)
                    .font(NoxaType.display(84))
                    .tracking(-2.5)
                    .foregroundStyle(NoxaTheme.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("days a year")
                    .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(NoxaTheme.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("About \(TimeProjection.format(projection.annualFullDays)) full days a year at \(TimeProjection.spokenLabel(minutes: projection.minutesPerDay)) a day")

            chart
                .frame(height: 230)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Over a year: \(TimeProjection.format(projection.annualFullDays)) days at your pace, or \(TimeProjection.format(projection.annualFullDays / 2)) days at half of it.")

            HStack(spacing: 18) {
                legend("At your pace", color: NoxaTheme.accent, dashed: false)
                legend("At half the time", color: NoxaTheme.secondaryText, dashed: true)
            }
            .font(NoxaType.caption)
            .foregroundStyle(NoxaTheme.secondaryText)

            VStack(alignment: .leading, spacing: 14) {
                Text("You spend \(TimeProjection.format(projection.annualFullDays)) days a year on distracting apps. That's time gone, never to come back.")
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Let's change that.")
                    .font(NoxaTheme.font(30, weight: .bold, relativeTo: .title))
                    .tracking(-0.6)
            }
            .padding(.top, 8)
        } actions: {
            OnboardingPrimaryButton("Continue") {
                if onboarding.completeProjection() { onContinue() }
            }
        }
        .onAppear {
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.easeOut(duration: 1.1)) { reveal = 1 }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Month", point.month),
                    y: .value("Days", point.days),
                    series: .value("Series", point.series)
                )
                .foregroundStyle(point.series == Self.whereYouAre ? NoxaTheme.accent : NoxaTheme.secondaryText)
                .lineStyle(point.series == Self.whereYouAre
                    ? StrokeStyle(lineWidth: 3, lineCap: .round)
                    : StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                .interpolationMethod(.linear)
            }
            ForEach(Array(points.filter { $0.series == Self.whereYouAre }.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Month", point.month),
                    yStart: .value("Could be", point.days / 2),
                    yEnd: .value("Days", point.days)
                )
                .foregroundStyle(NoxaTheme.accent.opacity(0.14))
            }
            PointMark(x: .value("Month", 12), y: .value("Days", projection.annualFullDays * reveal))
                .foregroundStyle(NoxaTheme.accent)
                .symbolSize(70)
                .annotation(position: .top, alignment: .trailing) {
                    Text("\(TimeProjection.format(projection.annualFullDays))d")
                        .font(NoxaType.captionSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                }
            PointMark(x: .value("Month", 12), y: .value("Days", projection.annualFullDays / 2 * reveal))
                .foregroundStyle(NoxaTheme.secondaryText)
                .symbolSize(50)
                .annotation(position: .bottom, alignment: .trailing) {
                    Text("\(TimeProjection.format(projection.annualFullDays / 2))d")
                        .font(NoxaType.captionSemibold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
        }
        .chartXScale(domain: 0...12)
        .chartYScale(domain: 0...max(projection.annualFullDays * 1.15, 1))
        .chartXAxis {
            AxisMarks(values: [0, 6, 12]) { value in
                let month = value.as(Int.self) ?? 0
                // Edge labels hang inward so "1 year" isn't clipped.
                AxisValueLabel(anchor: month == 0 ? .topLeading : month == 12 ? .topTrailing : .top) {
                    Text(month == 0 ? "Today" : month == 6 ? "6 months" : "1 year")
                }
                .font(NoxaType.caption)
                .foregroundStyle(NoxaTheme.tertiaryText)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(NoxaTheme.border)
                AxisValueLabel().font(NoxaType.caption).foregroundStyle(NoxaTheme.tertiaryText)
            }
        }
    }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [3, 3] : []))
                .frame(width: 16, height: 1)
            Text(title)
        }
    }
}

// MARK: Step 4 — Goals

struct OnboardingGoalsStep: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var selected: Set<OnboardingGoal>
    let onBack: () -> Void
    let onContinue: () -> Void

    init(initial: Set<OnboardingGoal>, onBack: @escaping () -> Void, onContinue: @escaping () -> Void) {
        _selected = State(initialValue: initial)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        OnboardingScaffold(eyebrow: "02 / Your why", onBack: onBack) {
            OnboardingHeading(
                title: "What would you make more time for?",
                subtitle: "Noxa helps you protect your attention so you can focus on the things you care about."
            )
            OnboardingOptionList(
                options: OnboardingGoal.allCases,
                title: \.rawValue,
                isSelected: { selected.contains($0) },
                toggle: { goal in
                    selected.formSymmetricDifference([goal])
                    onboarding.saveGoals(selected, complete: false)
                }
            )
        } actions: {
            OnboardingPrimaryButton("Continue", isEnabled: !selected.isEmpty) { save() }
        }
    }

    private func save() {
        if onboarding.saveGoals(selected) { onContinue() }
    }
}

// MARK: Step 5 — Distraction categories

struct OnboardingCategoriesStep: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var selected: Set<OnboardingDistraction>
    let onBack: () -> Void
    let onContinue: () -> Void

    init(initial: Set<OnboardingDistraction>, onBack: @escaping () -> Void, onContinue: @escaping () -> Void) {
        _selected = State(initialValue: initial)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        OnboardingScaffold(eyebrow: "03 / What pulls you in", onBack: onBack) {
            OnboardingHeading(
                title: "What pulls you in the most?",
                subtitle: "Choose any that fit. You'll choose the actual apps to block later."
            )
            OnboardingOptionList(
                options: OnboardingDistraction.allCases,
                title: \.rawValue,
                isSelected: { selected.contains($0) },
                toggle: { distraction in
                    selected.formSymmetricDifference([distraction])
                    onboarding.saveDistractions(selected, complete: false)
                }
            )
        } actions: {
            OnboardingPrimaryButton("Continue", isEnabled: !selected.isEmpty) { save() }
        }
    }

    private func save() {
        if onboarding.saveDistractions(selected) { onContinue() }
    }
}

// MARK: Step 6 — Research insight

struct OnboardingInsightStep: View {
    static let sourceURL = URL(string: "https://www.pewresearch.org/short-reads/2026/09/01/about-half-of-americans-say-they-spend-too-much-time-on-their-smartphone/")!

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var shownPercent: Double = 0
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(eyebrow: "A common feeling", centered: true, onBack: onBack) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                RollingNumber(value: shownPercent)
                Text("%")
            }
            .font(NoxaType.display(112))
            .tracking(-4)
            .foregroundStyle(NoxaTheme.accent)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("53 percent")

            Text("of U.S. adults say they spend too much time on their smartphone.")
                .font(NoxaTheme.font(26, weight: .semibold, relativeTo: .title2))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)

            Text("You're not alone. Wanting more control over your time is a good place to start.")
                .foregroundStyle(NoxaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: Self.sourceURL) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Pew Research Center · U.S. adults, May 26–June 1, 2026 survey; published September 1, 2026")
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.up.right")
                }
                .font(NoxaType.caption)
                .foregroundStyle(NoxaTheme.tertiaryText)
            }
            .accessibilityHint("Opens the original survey in Safari")
        } actions: {
            OnboardingPrimaryButton("Continue") {
                if onboarding.completeInsight() { onContinue() }
            }
        }
        .onAppear {
            if reduceMotion {
                shownPercent = 53
            } else {
                withAnimation(.easeOut(duration: 0.8)) { shownPercent = 53 }
            }
        }
    }
}

// MARK: Step 7 — How Noxa helps

struct OnboardingProductDemoStep: View {
    @EnvironmentObject private var onboarding: OnboardingService
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(onBack: onBack) {
            OnboardingHeading(
                title: "Here's how Noxa helps you take control.",
                subtitle: "Simple tools for the moments when distractions get in the way."
            )

            VStack(spacing: 0) {
                feature("hand.raised.slash", "Block distractions", "Choose what to restrict during Focus.")
                Divider().overlay(NoxaTheme.border)
                feature("play.slash", "Hide Reels and Shorts", "Hide Instagram Reels and YouTube Shorts in Safari, and keep the rest.")
                Divider().overlay(NoxaTheme.border)
                feature("timer", "Focus intentionally", "Start a session and give yourself space to work.")
                Divider().overlay(NoxaTheme.border)
                feature("hourglass", "Set healthy limits", "Create app limits and schedules.")
                Divider().overlay(NoxaTheme.border)
                feature("chart.xyaxis.line", "See your progress", "Understand completed sessions and focus patterns.")
            }
            .padding(.top, 8)
        } actions: {
            OnboardingPrimaryButton("Continue") {
                if onboarding.completeProductDemo() { onContinue() }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NoxaTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(NoxaTheme.font(20, weight: .semibold, relativeTo: .title3))
                Text(detail)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}
