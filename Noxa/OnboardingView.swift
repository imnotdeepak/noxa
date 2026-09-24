import FamilyControls
import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var page: Page
    @State private var goals: Set<String>
    @State private var distractions: Set<String>
    @State private var isRequestingAuthorization = false

    private enum Page: Int, CaseIterable {
        case welcome
        case goals
        case goalInsight
        case distractions
        case distractionInsight
        case capabilities
        case pricing
    }

    private let goalOptions = ["Studying", "Work", "Sleep", "Reduce screen time", "Deep focus", "Better habits"]
    private let distractionOptions = [
        "Short-form media",
        "Long-form media",
        "Web browsing",
        "Playing games",
        "Social media",
        "Other"
    ]

    init() {
        _page = State(initialValue: .welcome)
        _goals = State(initialValue: [])
        _distractions = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page != .welcome {
                    Button {
                        moveBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Back")
                }

                Spacer()

                Text("noxa")
                    .font(NoxaTheme.font(17, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(NoxaTheme.primaryText)

                Spacer()

                if page != .welcome {
                    Color.clear
                        .frame(width: 17, height: 17)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Group {
                switch page {
                case .welcome:
                    welcomePage
                case .goals:
                    goalsPage
                case .goalInsight:
                    goalInsightPage
                case .distractions:
                    distractionsPage
                case .distractionInsight:
                    distractionInsightPage
                case .capabilities:
                    capabilitiesPage
                case .pricing:
                    pricingPage
                }
            }
            .transition(.opacity)
        }
        .font(NoxaTheme.font(17))
        .background(NoxaBackground())
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: page)
        .onAppear(perform: restoreDraft)
    }

    private var welcomePage: some View {
        pageLayout {
            Spacer()

            Text("Take back your\nattention.")
                .font(NoxaTheme.font(44, weight: .bold, relativeTo: .largeTitle))
                .tracking(-1.2)

            Text("Block distractions, build better screen habits, and focus when you need to.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            onboardingErrorView

            onboardingButton("Get Started") {
                if onboarding.markWelcomeSeen() {
                    page = .goals
                }
            }
        }
    }

    private var goalsPage: some View {
        pageLayout {
            pageHeader("What do you want help with?", subtitle: "Choose any that fit. You can change your mind later.")
            selectionGrid(options: goalOptions, selected: $goals)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveGoals(Array(goals).sorted()) {
                    page = .goalInsight
                }
            }
            .disabled(goals.isEmpty)
        }
    }

    private var goalInsightPage: some View {
        insightPage(
            statistic: "53%",
            title: "You’re not alone.",
            message: "More than half of U.S. adults say they spend too much time on their smartphone.",
            source: "Pew Research Center, 2026"
        ) {
            page = .distractions
        }
    }

    private var distractionsPage: some View {
        pageLayout {
            pageHeader("What distracts you the most?", subtitle: "This helps us explain the right Noxa tools before setup.")
            selectionGrid(options: distractionOptions, selected: $distractions)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveDistractions(Array(distractions).sorted()) {
                    page = .distractionInsight
                }
            }
            .disabled(distractions.isEmpty)
        }
    }

    private var distractionInsightPage: some View {
        insightPage(
            statistic: "Small changes add up",
            title: "Less screen time can help.",
            message: "In a randomized trial of healthy students, reducing smartphone use for three weeks improved well-being, stress, sleep, and depressive symptoms.",
            source: "Pieh et al., BMC Medicine, 2025"
        ) {
            page = .capabilities
        }
    }

    private var capabilitiesPage: some View {
        pageLayout {
            Spacer()

            Image(systemName: authorization.state.isApproved ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(authorization.state.isApproved ? .white : .secondary)
                .frame(maxWidth: .infinity)

            Text("Noxa needs Screen Time access")
                .font(NoxaTheme.font(32, weight: .bold, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Apple keeps your app and website selections private. Noxa uses that permission to block only what you choose.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            if authorization.state.isApproved {
                Label("Screen Time access is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            } else if authorization.state == .denied {
                Text("Permission is currently denied. Enable Screen Time access in Settings, then try again.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage = authorization.errorMessage ?? onboarding.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            if authorization.state.isApproved {
                onboardingButton("See plans") {
                    if onboarding.completeCapabilitiesExplainer() {
                        page = .pricing
                    }
                }
            } else {
                onboardingButton(isRequestingAuthorization ? "Requesting…" : "Allow Screen Time Access") {
                    guard !isRequestingAuthorization else { return }
                    isRequestingAuthorization = true
                    Task { @MainActor in
                        await authorization.requestAuthorization()
                        isRequestingAuthorization = false
                    }
                }
                .disabled(isRequestingAuthorization)

                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }

    private var pricingPage: some View {
        pageLayout {
            pageHeader("Simple pricing. Full focus.", subtitle: "Choose a plan after you create your account. Both plans include every Noxa feature.")

            VStack(alignment: .leading, spacing: 14) {
                featureRow("Focused app and website blocking")
                featureRow("Timed focus sessions and daily limits")
                featureRow("Focus history and future improvements")
            }
            .noxaCard()

            VStack(spacing: 12) {
                pricingCard(
                    name: "Monthly",
                    price: "$1.99",
                    detail: "about $0.07 per day"
                )
                pricingCard(
                    name: "Annual",
                    price: "$19.99",
                    detail: "about $1.67 per month · $0.05 per day",
                    badge: "BEST VALUE"
                )
            }

            Label {
                Text("Clear pricing, always. You’ll see the current price before purchase, and Apple will notify you before any future renewal price change.")
            } icon: {
                Image(systemName: "shield.checkered")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 6)
            onboardingErrorView
            onboardingButton("Create your account") {
                _ = onboarding.completePricingPreview()
            }

            Text("The App Store confirms your exact local price and handles payment securely. Subscriptions renew automatically until canceled.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func insightPage(
        statistic: String,
        title: String,
        message: String,
        source: String,
        action: @escaping () -> Void
    ) -> some View {
        pageLayout {
            Spacer()

            VStack(spacing: 16) {
                Text(statistic)
                    .font(NoxaTheme.font(statistic.count < 5 ? 68 : 38, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-1.4)
                    .multilineTextAlignment(.center)

                Text(title)
                    .font(NoxaTheme.font(30, weight: .bold, relativeTo: .title))
                    .multilineTextAlignment(.center)

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(source)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(NoxaTheme.border, lineWidth: 1)
            }

            Spacer()
            onboardingButton("Continue", action: action)
        }
    }

    private func featureRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark")
            .font(NoxaTheme.font(15, weight: .medium, relativeTo: .subheadline))
    }

    private func pricingCard(name: String, price: String, detail: String, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(NoxaTheme.font(19, weight: .semibold, relativeTo: .headline))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(NoxaTheme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
            }
            Text(price)
                .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                .monospacedDigit()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1.25)
        }
    }

    private func pageLayout<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18, content: content)
                    .padding(24)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height,
                        alignment: .leading
                    )
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(NoxaTheme.font(32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.6)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionGrid(options: [String], selected: Binding<Set<String>>) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button {
                    if selected.wrappedValue.contains(option) {
                        selected.wrappedValue.remove(option)
                    } else {
                        selected.wrappedValue.insert(option)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(option)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if selected.wrappedValue.contains(option) {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(NoxaTheme.accent)
                        }
                    }
                    .font(NoxaTheme.font(17, weight: .medium))
                    .foregroundStyle(NoxaTheme.primaryText)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                selected.wrappedValue.contains(option) ? NoxaTheme.accent : NoxaTheme.border,
                                lineWidth: selected.wrappedValue.contains(option) ? 1.5 : 1
                            )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onboardingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoxaPrimaryButtonStyle())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var onboardingErrorView: some View {
        if let errorMessage = onboarding.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moveBack() {
        switch page {
        case .welcome:
            break
        case .goals:
            page = .welcome
        case .goalInsight:
            page = .goals
        case .distractions:
            page = .goalInsight
        case .distractionInsight:
            page = .distractions
        case .capabilities:
            page = .distractionInsight
        case .pricing:
            page = .capabilities
        }
    }

    private func restoreDraft() {
        goals = Set(onboarding.progress.draftPersonalizationAnswers)
        if let savedDistractions = onboarding.progress.draftSetupConfiguration["distractions"] {
            distractions = Set(savedDistractions.split(separator: "|").map(String.init))
        }

        if onboarding.progress.hasSeenCapabilitiesExplainer {
            page = .pricing
        } else if onboarding.progress.hasCompletedDistractions {
            page = .distractionInsight
        } else if onboarding.progress.hasCompletedGoals {
            page = .goalInsight
        } else if onboarding.progress.hasSeenWelcome {
            page = .goals
        }
    }
}

private extension ScreenTimeAuthorizationState {
    var isApproved: Bool {
        self == .approved || self == .approvedWithDataAccess
    }
}
