import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var subscriptions: SubscriptionService
    @EnvironmentObject private var focusSession: FocusSessionService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var monitoring: DeviceActivityMonitoringService
    @EnvironmentObject private var dailyLimits: DailyLimitService
    @EnvironmentObject private var schedules: RestrictionScheduleService
    @EnvironmentObject private var websites: WebsiteBlocklistService
    @EnvironmentObject private var cloudSync: CloudSyncService
    @EnvironmentObject private var onboarding: OnboardingService
    let allowsDismissal: Bool
    let onAccessConfirmed: (() -> Void)?
    @State private var isDeleteAccountConfirmationPresented = false
    @State private var hasCompletedOnboardingTransition = false
    @State private var hasTrackedAppearance = false

    init(allowsDismissal: Bool = true, onAccessConfirmed: (() -> Void)? = nil) {
        self.allowsDismissal = allowsDismissal
        self.onAccessConfirmed = onAccessConfirmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text(paywallTitle)
                            .font(NoxaTheme.font(38, weight: .bold, relativeTo: .largeTitle))
                            .tracking(-1)
                            .multilineTextAlignment(.center)
                        Text(paywallSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    if subscriptions.purchasingProductID != nil {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Processing your purchase…")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .noxaCard()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Processing your purchase")
                    }

                    if subscriptions.hasAccess {
                        if isOnboarding {
                            ProgressView("Finishing your setup…")
                                .tint(NoxaTheme.accent)
                                .frame(maxWidth: .infinity)
                        } else {
                            activeSubscriptionSection
                        }
                    } else if subscriptions.plans.isEmpty {
                        VStack(spacing: 10) {
                            if subscriptions.isLoading {
                                ProgressView("Loading plans…")
                            } else {
                                Text("Plans are not available yet.")
                                    .font(.headline)
                                Text("Please check your connection and try again. You can also restore a purchase below.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .noxaCard()
                    } else {
                        ForEach(orderedPlans) { plan in
                            Button {
                                Task {
                                    let accountID = authentication.userID
                                    let purchased = await subscriptions.purchase(plan)
                                    guard purchased, authentication.userID == accountID else { return }
                                    confirmAccess()
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text(plan.title)
                                        .font(NoxaTheme.font(18, weight: .semibold, relativeTo: .headline))
                                    if subscriptions.purchasingProductID == plan.id {
                                        ProgressView()
                                            .tint(.white)
                                            .accessibilityLabel("Processing")
                                    } else {
                                        Text(plan.displayPrice)
                                            .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                                            .monospacedDigit()
                                    }
                                    Text(plan.periodDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if plan.isAnnual {
                                        Text("BEST VALUE")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .background(NoxaTheme.accent, in: Capsule())
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NoxaPaywallPlanButtonStyle())
                            .disabled(subscriptions.isLoading)
                            .accessibilityValue(
                                subscriptions.purchasingProductID == plan.id
                                    ? "Processing purchase"
                                    : plan.displayPrice
                            )
                        }

                        Text("Tap a plan to confirm your purchase securely with the App Store.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    LegalLinksView()

                    Button("Restore Purchases") {
                        Task {
                            await subscriptions.restorePurchases()
                            if subscriptions.hasAccess {
                                confirmAccess()
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .disabled(subscriptions.isLoading)

                    if !isOnboarding {
                        if !allowsDismissal {
                            Button("Sign Out") {
                                Task { await authentication.signOut() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .disabled(authentication.isBusy)
                        }

                        Button("Delete Account", role: .destructive) {
                            isDeleteAccountConfirmationPresented = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .disabled(authentication.isBusy)

                        Link("Manage subscriptions in Apple settings", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let message = subscriptions.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(subscriptions.hasAccess ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text(isOnboarding
                         ? "Subscriptions are billed by Apple and renew automatically until canceled."
                         : "Subscriptions are billed by Apple and renew automatically until canceled. Manage or cancel them in your Apple Account settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .font(NoxaTheme.font(17))
            .background(NoxaBackground())
            .preferredColorScheme(.dark)
            .task {
                if !hasTrackedAppearance {
                    hasTrackedAppearance = true
                    AnalyticsService.shared.capture(.paywallViewed(
                        context: isOnboarding ? "onboarding" : "account"
                    ))
                }
                if isOnboarding, subscriptions.hasAccess {
                    confirmAccess()
                } else if !isOnboarding {
                    await subscriptions.refreshEntitlements()
                }
            }
            .onChange(of: subscriptions.hasAccess) { hasAccess in
                if isOnboarding, hasAccess {
                    confirmAccess()
                }
            }
            .alert("Delete your Noxa account?", isPresented: $isDeleteAccountConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) {
                    Task { @MainActor in
                        guard await authentication.deleteAccount() else { return }
                        LocalDataCleanupService.clear(
                            focusSession: focusSession,
                            restrictions: restrictions,
                            monitoring: monitoring,
                            dailyLimits: dailyLimits,
                            schedules: schedules,
                            websites: websites,
                            cloudSync: cloudSync,
                            onboarding: onboarding
                        )
                    }
                }
            } message: {
                Text("This permanently deletes your cloud account and Noxa data. Your App Store subscription must be cancelled separately in Apple settings.")
            }
            .toolbar {
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private var isOnboarding: Bool {
        onAccessConfirmed != nil
    }

    private var paywallTitle: String {
        if subscriptions.hasAccess {
            return isOnboarding ? "Purchase successful" : "Your Noxa subscription"
        }
        return "Simple pricing. Full focus."
    }

    private var paywallSubtitle: String {
        if subscriptions.hasAccess {
            return isOnboarding
                ? "Getting your distraction setup ready."
                : "An active subscription was found on this Apple Account. Continue to use it with this Noxa account."
        }
        return "Every plan includes the complete Noxa experience."
    }

    private var orderedPlans: [SubscriptionPlan] {
        subscriptions.plans.sorted { left, right in
            if left.id == SubscriptionService.annualProductID { return true }
            if right.id == SubscriptionService.annualProductID { return false }
            return left.id < right.id
        }
    }

    @ViewBuilder
    private var activeSubscriptionSection: some View {
        VStack(spacing: 12) {
            Label("Your subscription is active", systemImage: "checkmark.seal.fill")
                .foregroundStyle(NoxaTheme.accent)
                .font(.headline)

            VStack(spacing: 8) {
                Text("CURRENT PLAN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(NoxaTheme.accent)

                Text(activePlanTitle)
                    .font(NoxaTheme.font(22, weight: .bold, relativeTo: .title2))

                if let currentPlan {
                    Text(currentPlan.displayPrice)
                        .font(NoxaTheme.font(32, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                    Text(currentPlan.periodDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                NoxaTheme.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(NoxaTheme.accent.opacity(0.55), lineWidth: 1)
            }
        }

        if !alternativePlans.isEmpty {
            VStack(spacing: 12) {
                Text("Switch plans")
                    .font(NoxaTheme.font(20, weight: .semibold, relativeTo: .title3))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(alternativePlans) { plan in
                    Button {
                        Task {
                            _ = await subscriptions.purchase(plan)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text("Switch to \(plan.title)")
                                .font(NoxaTheme.font(18, weight: .semibold, relativeTo: .headline))
                            if subscriptions.purchasingProductID == plan.id {
                                ProgressView()
                                    .tint(.white)
                                    .accessibilityLabel("Processing")
                            } else {
                                Text(plan.displayPrice)
                                    .font(NoxaTheme.font(30, weight: .bold, relativeTo: .largeTitle))
                                    .monospacedDigit()
                            }
                            Text(plan.periodDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NoxaPaywallPlanButtonStyle())
                    .disabled(subscriptions.isLoading)
                }

                Text("Apple confirms all plan changes. A downgrade may begin at your next renewal date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }

        if !allowsDismissal {
            Button("Continue with Current Subscription") {
                confirmAccess()
            }
            .buttonStyle(NoxaPrimaryButtonStyle())
        }
    }

    private var currentPlan: SubscriptionPlan? {
        guard let activeProductID = subscriptions.activeProductID else { return nil }
        return subscriptions.plans.first { $0.id == activeProductID }
    }

    private var alternativePlans: [SubscriptionPlan] {
        guard let activeProductID = subscriptions.activeProductID else { return [] }
        return orderedPlans.filter { $0.id != activeProductID }
    }

    private var activePlanTitle: String {
        if let currentPlan {
            return currentPlan.title
        }
        return subscriptions.activePlanDisplayName
    }

    private func confirmAccess() {
        guard subscriptions.hasAccess else { return }
        if isOnboarding {
            guard !hasCompletedOnboardingTransition else { return }
            hasCompletedOnboardingTransition = true
        }
        onAccessConfirmed?()
    }
}

private struct NoxaPaywallPlanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                Color.black.opacity(configuration.isPressed ? 0.75 : 0.45),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.55 : 0.9), lineWidth: 1.25)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
