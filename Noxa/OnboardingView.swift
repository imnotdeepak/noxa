import FamilyControls
import SwiftUI
import UIKit

/// Step 1. The brand promise, then either a new setup or sign-in. Signing in
/// never clears an unowned draft; it is adopted by the account.
struct OnboardingWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var revealsDetails = false
    var onGetStarted: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image("NoxaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 110)
                    .accessibilityHidden(true)

                Text("noxa")
                    .font(NoxaTheme.font(40, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-1)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 14) {
                Text("Your attention belongs to you.")
                    .font(OnboardingType.hero)
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Block distractions. Build focus. Make more time for what matters.")
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .opacity(revealsDetails ? 1 : 0)
            .offset(y: revealsDetails ? 0 : 16)

            Spacer()

            VStack(spacing: 6) {
                OnboardingPrimaryButton("Get Started") {
                    if let onGetStarted { onGetStarted() }
                    else { _ = onboarding.beginNewAccountPersonalization() }
                }
                if onGetStarted == nil {
                    OnboardingTextButton("I already have an account") {
                        _ = onboarding.beginAuthentication(
                            mode: AuthenticationView.Mode.signIn.rawValue
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .font(OnboardingType.body)
        .foregroundStyle(NoxaTheme.primaryText)
        .background(NoxaOnboardingBackground())
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                revealsDetails = true
            } else {
                withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                    revealsDetails = true
                }
            }
        }
    }
}

struct ReturningUserView: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var onboarding: OnboardingService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("NoxaLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 112)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(welcomeTitle)
                    .font(NoxaTheme.font(38, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-0.9)
                    .multilineTextAlignment(.center)

                Text("Sign in to continue where you left off. You won’t need to repeat onboarding.")
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let email = authentication.rememberedUserEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(NoxaTheme.accent)
                }
            }
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 12) {
                Button("Continue") {
                    _ = onboarding.beginAuthentication(
                        mode: AuthenticationView.Mode.signIn.rawValue
                    )
                }
                .buttonStyle(NoxaPrimaryButtonStyle())

                Button("Use a different account") {
                    authentication.forgetRememberedAccount()
                    _ = onboarding.reset()
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .font(NoxaTheme.font(17))
        .background(NoxaOnboardingBackground())
        .preferredColorScheme(.dark)
    }

    private var welcomeTitle: String {
        guard let name = authentication.rememberedDisplayName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Welcome back."
        }
        return "Welcome back, \(name)."
    }

}

/// Steps 2–13. One owner for routing: the step to show is resumed from saved
/// milestones and then guarded by live account, Screen Time, selection and
/// subscription state, so a revoked permission or a lost entitlement sends
/// the user back to the step that repairs it rather than past it.
struct OnboardingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var onboarding: OnboardingService
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var subscriptions: SubscriptionService
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var step: OnboardingStep?
    private let previewStep: OnboardingStep?
    private let isReplay: Bool
    private let onReplayFinished: (() -> Void)?

    init(previewStep: OnboardingStep? = nil, isReplay: Bool = false, onReplayFinished: (() -> Void)? = nil) {
        self.previewStep = previewStep
        self.isReplay = isReplay
        self.onReplayFinished = onReplayFinished
    }

    var body: some View {
        ZStack {
            NoxaBackground()
            if let current = guardedStep {
                stepView(current)
                    .id(current)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: guardedStep)
        .preferredColorScheme(.dark)
        .onAppear {
            guard step == nil else { return }
            step = previewStep ?? onboarding.consumeResumeOverride() ?? resumeStep
        }
        .onChange(of: guardedStep) { current in
            if let current, !isReplay {
                AnalyticsService.shared.capture(.onboardingStepViewed(String(describing: current)))
            }
        }
        .onChange(of: scenePhase) { phase in
            // Permission can change in Settings while Noxa is in the background.
            if phase == .active { authorization.refresh() }
        }
        .sheet(isPresented: $restrictions.isPickerPresented) {
            NavigationStack {
                FamilyActivityPicker(selection: $restrictions.selection)
                    .navigationTitle("Choose distractions")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                restrictions.persistSelection()
                                restrictions.isPickerPresented = false
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var hasSubscription: Bool {
        onboarding.progress.hasSeenPricingPreview || subscriptions.hasAccess
    }

    private var resumeStep: OnboardingStep {
        OnboardingStep.resume(
            progress: onboarding.progress,
            isAuthenticated: authentication.isAuthenticated,
            isScreenTimeApproved: authorization.state.isApproved,
            hasSelection: restrictions.hasSelection,
            hasSubscription: hasSubscription
        )
    }

    /// The saved step, moved back to the first unmet prerequisite.
    private var guardedStep: OnboardingStep? {
        guard let step else { return nil }
        if previewStep != nil || isReplay { return step }
        if step.rawValue > OnboardingStep.account.rawValue, !authentication.isAuthenticated { return .account }
        if step.rawValue > OnboardingStep.screenTime.rawValue, !authorization.state.isApproved { return .screenTime }
        if step.rawValue > OnboardingStep.selection.rawValue, !restrictions.hasSelection { return .selection }
        if step == .pact, !onboarding.progress.hasSeenPricingPreview { return .subscription }
        return step
    }

    private func go(_ next: OnboardingStep) {
        step = next
    }

    /// Leaves the narrative for sign-up, or skips it when already signed in.
    private func continueAfterProductDemo() {
        if isReplay {
            go(.account)
        } else if authentication.isAuthenticated {
            go(.screenTime)
        } else {
            _ = onboarding.beginAuthentication(mode: AuthenticationView.Mode.createAccount.rawValue)
        }
    }

    private func back(from current: OnboardingStep) -> () -> Void {
        { if let previous = current.previous { go(previous) } }
    }

    /// Each step is type-erased so the flow's view value stays small.
    private func stepView(_ current: OnboardingStep) -> AnyView {
        switch current {
        case .estimate:
            return AnyView(OnboardingEstimateStep(
                initialMinutes: onboarding.progress.estimatedDistractingMinutesPerDay
            ) { go(.projection) })
        case .projection:
            return AnyView(OnboardingProjectionStep(onBack: back(from: .projection)) { go(.goals) })
        case .goals:
            return AnyView(OnboardingGoalsStep(
                initial: onboarding.progress.selectedGoals,
                onBack: back(from: .goals),
                onContinue: { go(.categories) }
            ))
        case .categories:
            return AnyView(OnboardingCategoriesStep(
                initial: onboarding.progress.selectedDistractions,
                onBack: back(from: .categories),
                onContinue: { go(.insight) }
            ))
        case .insight:
            return AnyView(OnboardingInsightStep(onBack: back(from: .insight)) { go(.productDemo) })
        case .productDemo:
            return AnyView(OnboardingProductDemoStep(onBack: back(from: .productDemo)) {
                continueAfterProductDemo()
            })
        case .account:
            if isReplay {
                return AnyView(AuthenticationView(
                    initialMode: .createAccount,
                    onBack: back(from: .account),
                    isPreview: true,
                    onPreviewContinue: { go(.screenTime) }
                ))
            }
            // Sign-up is its own screen; arriving here hands off to it.
            return AnyView(NoxaLoadingView(message: "Opening account setup…").task {
                if authentication.isAuthenticated {
                    go(.screenTime)
                } else {
                    _ = onboarding.beginAuthentication(mode: AuthenticationView.Mode.createAccount.rawValue)
                }
            })
        case .screenTime:
            return AnyView(OnboardingScreenTimeStep(authorization: authorization, isPreview: isReplay) { go(.selection) })
        case .selection:
            return AnyView(OnboardingSelectionStep(isPreview: isReplay, onBack: back(from: .selection)) { go(.notifications) })
        case .notifications:
            return AnyView(OnboardingNotificationsStep(isPreview: isReplay, onBack: back(from: .notifications)) {
                if isReplay || onboarding.completeNotificationExplainer() { go(.analyticsConsent) }
            })
        case .analyticsConsent:
            return AnyView(OnboardingAnalyticsStep(isPreview: isReplay, onBack: back(from: .analyticsConsent)) {
                // An existing subscriber passes straight through the paywall.
                if isReplay || onboarding.completeAnalyticsConsent() { go(.subscription) }
            })
        case .subscription:
            return AnyView(OnboardingSubscriptionStep(isPreview: isReplay) {
                if isReplay || onboarding.confirmSubscription(hasVerifiedAccess: subscriptions.hasAccess) {
                    go(.pact)
                }
            })
        case .pact:
            return AnyView(NoxaPactView { status in
                if isReplay {
                    onReplayFinished?()
                } else {
                    AnalyticsService.shared.capture(.onboardingPactFinished(status.rawValue))
                    _ = onboarding.finishPact(status)
                }
            })
        }
    }
}
