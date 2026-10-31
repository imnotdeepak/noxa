import FamilyControls
import SwiftUI
import UIKit

// MARK: Step 9 — Screen Time permission

struct OnboardingScreenTimeStep: View {
    @ObservedObject var authorization: FamilyControlsAuthorizationService
    var isPreview = false
    @State private var isRequesting = false
    @State private var showsHelp = false
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(centered: true) {
            setupIcon(isApproved ? "checkmark.shield.fill" : "lock.shield")
                .frame(maxWidth: .infinity)

            OnboardingHeading(
                title: "Allow Screen Time access.",
                subtitle: "Noxa uses Apple's Screen Time system to restrict the apps and websites you choose. Apple keeps your choices private.",
                alignment: .center
            )

            statusView

            if !isApproved {
                VStack(spacing: 12) {
                    Button {
                        withAnimation(NoxaMotion.spring) { showsHelp.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("How to enable access")
                            Image(systemName: showsHelp ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.primaryText)
                        .frame(minHeight: 44)
                    }
                    .accessibilityValue(showsHelp ? "Expanded" : "Collapsed")
                    if showsHelp {
                        VStack(alignment: .leading, spacing: 10) {
                            helpRow("1", "Apple asks you to confirm with Face ID, Touch ID or your passcode.")
                            helpRow("2", "If this iPhone is managed through Family Sharing, Screen Time access may need approval there.")
                            helpRow("3", "If you said no before, tap Try Again. If nothing appears, check that Screen Time is available in Settings.")
                        }
                        .noxaCard()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } actions: {
            if isPreview {
                OnboardingPrimaryButton("Continue preview", action: onContinue)
            } else if isApproved {
                OnboardingPrimaryButton("Continue", action: onContinue)
            } else {
                OnboardingPrimaryButton(
                    isRequesting ? "Requesting…" : (hasAsked ? "Try Again" : "Allow Screen Time Access"),
                    isEnabled: !isRequesting
                ) {
                    request()
                }
                if authorization.state == .denied {
                    OnboardingTextButton("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var isApproved: Bool { authorization.state.isApproved }

    private var hasAsked: Bool {
        authorization.state == .denied || authorization.state == .unknown || authorization.errorMessage != nil
    }

    @ViewBuilder
    private var statusView: some View {
        if isApproved {
            OnboardingStatusLabel(text: "Screen Time access is on", symbol: "checkmark.circle.fill", isCentered: true)
        } else if authorization.state == .denied || authorization.errorMessage != nil {
            OnboardingStatusLabel(
                text: "Screen Time access isn't enabled yet. Noxa needs permission to block the distractions you select. Your answers are saved — you can try again.",
                symbol: "exclamationmark.triangle.fill",
                color: NoxaTheme.warning,
                isCentered: true
            )
        } else if authorization.state == .unknown {
            OnboardingStatusLabel(
                text: "Screen Time isn't available right now. Your answers are saved — try again in a moment.",
                symbol: "exclamationmark.triangle.fill",
                color: NoxaTheme.warning,
                isCentered: true
            )
        }
    }

    private func request() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            await authorization.requestAuthorization()
            isRequesting = false
            AnalyticsService.shared.capture(.onboardingScreenTimeResult(authorization.state.rawValue))
            if authorization.state.isApproved {
                NoxaHaptics.success()
            }
        }
    }

    private func helpRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(NoxaType.captionBold)
                .foregroundStyle(NoxaTheme.accent)
            Text(text)
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Step 10 — Choose actual apps and websites

struct OnboardingSelectionStep: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    var isPreview = false
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(centered: true, onBack: onBack) {
            setupIcon("hand.raised.slash.fill")
                .frame(maxWidth: .infinity)

            OnboardingHeading(
                title: "Choose what Noxa should block.",
                subtitle: "Select the apps, categories, and websites you want to avoid during Focus.",
                alignment: .center
            )

            VStack(spacing: 14) {
                if restrictions.hasSelection {
                    OnboardingStatusLabel(text: selectionSummary, symbol: "checkmark.circle.fill", isCentered: true)
                } else {
                    OnboardingStatusLabel(
                        text: "Nothing selected yet",
                        symbol: "circle.dashed",
                        color: NoxaTheme.secondaryText,
                        isCentered: true
                    )
                }
                Button(restrictions.hasSelection ? "Edit Selection" : "Choose Distractions") {
                    restrictions.isPickerPresented = true
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(isPreview)
            }
            .noxaCard()

            if let hint {
                Text(hint)
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage = restrictions.errorMessage {
                OnboardingStatusLabel(text: errorMessage, symbol: "exclamationmark.triangle.fill", color: NoxaTheme.warning, isCentered: true)
            }

            Text("Nothing is blocked until you start a Focus. You can change this anytime in your Blocklist.")
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        } actions: {
            OnboardingPrimaryButton(isPreview ? "Continue preview" : "Continue", isEnabled: isPreview || restrictions.hasSelection) {
                if isPreview {
                    onContinue()
                } else {
                    restrictions.persistSelection()
                    guard restrictions.hasSelection, restrictions.errorMessage == nil else { return }
                    onContinue()
                }
            }
        }
    }

    /// Real token counts from Apple's picker.
    private var selectionSummary: String {
        let selection = restrictions.selection
        var parts = [count(selection.applicationTokens.count, "app")]
        if !selection.categoryTokens.isEmpty {
            parts.append(count(selection.categoryTokens.count, "category", plural: "categories"))
        }
        parts.append(count(selection.webDomainTokens.count, "website"))
        return parts.joined(separator: " · ") + " selected"
    }

    private func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Echoes step 5's answers as a reminder only; nothing is preselected.
    private var hint: String? {
        let chosen = OnboardingDistraction.allCases
            .filter { onboarding.progress.selectedDistractions.contains($0) && $0 != .other }
            .map { $0.rawValue.lowercased() }
        guard !chosen.isEmpty else { return nil }
        let list = ListFormatter.localizedString(byJoining: chosen)
        return "You said \(list) pull you in. You can include those here."
    }
}

// MARK: Step 11 — Notifications

struct OnboardingNotificationsStep: View {
    @EnvironmentObject private var notifications: FocusNotificationService
    var isPreview = false
    @State private var isRequesting = false
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(centered: true, onBack: onBack) {
            setupIcon("bell.badge")
                .frame(maxWidth: .infinity)

            OnboardingHeading(
                title: "Stay informed about your Focus.",
                subtitle: "Get a reminder when a session ends, and before a Pomodoro break finishes. Blocking still works without notifications.",
                alignment: .center
            )

            if notifications.canSchedule {
                OnboardingStatusLabel(text: "Notifications are on", symbol: "checkmark.circle.fill", isCentered: true)
            } else if notifications.authorizationStatus == .denied {
                OnboardingStatusLabel(
                    text: "Notifications are off. You can turn them on later in Settings.",
                    symbol: "bell.slash",
                    color: NoxaTheme.secondaryText,
                    isCentered: true
                )
            }
        } actions: {
            if isPreview {
                OnboardingPrimaryButton("Continue preview", action: onContinue)
            } else if notifications.authorizationStatus == .notDetermined {
                OnboardingPrimaryButton(isRequesting ? "Requesting…" : "Enable Notifications", isEnabled: !isRequesting) {
                    isRequesting = true
                    Task { @MainActor in
                        _ = await notifications.requestAuthorization()
                        isRequesting = false
                        onContinue()
                    }
                }
                OnboardingTextButton("Not Now", action: onContinue)
            } else {
                OnboardingPrimaryButton("Continue", action: onContinue)
            }
        }
        .task { await notifications.refreshAuthorizationStatus() }
    }
}

// MARK: Step 11b — Usage analytics

/// Asks once, everywhere. Analytics stays off unless the user agrees here
/// or later in Settings.
struct OnboardingAnalyticsStep: View {
    @EnvironmentObject private var analytics: AnalyticsService
    var isPreview = false
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingScaffold(centered: true, onBack: onBack) {
            setupIcon("chart.bar.xaxis")
                .frame(maxWidth: .infinity)

            OnboardingHeading(
                title: "Help improve Noxa.",
                subtitle: "Share optional usage data, like which screens you use and what you set up. It's linked to your Noxa account, but never includes your name or selected apps and websites. Change this anytime in Settings.",
                alignment: .center
            )
        } actions: {
            OnboardingPrimaryButton("Share Usage Data") {
                if !isPreview { analytics.isEnabled = true }
                onContinue()
            }
            // Same size as Share, so skipping is just as easy to choose.
            Button {
                if !isPreview { analytics.isEnabled = false }
                onContinue()
            } label: {
                Text("Skip").frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(NoxaPrimaryButtonStyle(fill: .white))
            .padding(.top, 4)
        }
    }
}

// MARK: Step 12 — Subscription

struct OnboardingSubscriptionStep: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var subscriptions: SubscriptionService
    @State private var selectedPlanID = SubscriptionService.annualProductID
    @State private var hasConfirmed = false
    @State private var isRetrying = false
    var isPreview = false
    let onConfirmed: () -> Void

    var body: some View {
        OnboardingScaffold {
            OnboardingHeading(
                title: "Simple pricing. Full focus.",
                subtitle: "Every plan includes the complete Noxa experience."
            )

            if subscriptions.hasAccess && !isPreview {
                OnboardingStatusLabel(text: "Your subscription is active", symbol: "checkmark.seal.fill")
                ProgressView("Finishing your setup…")
                    .tint(NoxaTheme.accent)
                    .frame(maxWidth: .infinity)
            } else if !subscriptions.hasLoaded || (subscriptions.isLoading && subscriptions.plans.isEmpty) || isRetrying {
                ProgressView("Loading plans…")
                    .tint(NoxaTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if subscriptions.plans.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingStatusLabel(
                        text: "We couldn't load plans right now.",
                        symbol: "wifi.exclamationmark",
                        color: NoxaTheme.warning
                    )
                    Text("Your setup is saved. Try again or restore an existing purchase.")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .noxaCard()
                .onAppear { AnalyticsService.shared.capture(.onboardingPaywallLoadFailed()) }
            } else {
                VStack(spacing: 10) {
                    ForEach(orderedPlans) { plan in
                        planRow(plan)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    OnboardingStatusLabel(text: "Both plans include every Noxa feature.", symbol: "checkmark.circle")
                    OnboardingStatusLabel(
                        text: "Your price is locked in. If prices go up, you keep paying what you pay today unless you cancel.",
                        symbol: "lock"
                    )
                }
            }

            if subscriptions.isPurchasePending && !subscriptions.hasAccess {
                OnboardingStatusLabel(
                    text: "Waiting for approval. Noxa continues once Apple confirms the purchase.",
                    symbol: "hourglass",
                    color: NoxaTheme.warning
                )
            } else if let message = subscriptions.message, !subscriptions.hasAccess {
                Text(message)
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Noxa uses Screen Time permission to block your selected distractions.")
                if let plan = selectedPlan {
                    Text("\(plan.displayPrice) is charged to your Apple Account \(plan.isAnnual ? "every year" : "every month"). It renews automatically unless you cancel at least 24 hours before the end of the current period. Manage or cancel anytime in Settings.")
                } else {
                    Text("Subscriptions are billed by Apple and renew automatically until canceled.")
                }
            }
            .font(NoxaType.caption)
            .foregroundStyle(NoxaTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)

            LegalLinksView()
        } actions: {
            if isPreview {
                OnboardingPrimaryButton("Continue preview to Pact", action: onConfirmed)
                Text("Preview only — no purchase will be made.")
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else if !subscriptions.hasAccess {
                if subscriptions.plans.isEmpty {
                    OnboardingPrimaryButton(isRetrying ? "Retrying…" : "Try Again", isEnabled: !isRetrying && subscriptions.hasLoaded) {
                        retry()
                    }
                } else if let plan = selectedPlan {
                    OnboardingPrimaryButton(
                        subscriptions.purchasingProductID == nil
                            ? "Continue with \(plan.isAnnual ? "Yearly" : "Monthly") · \(plan.displayPrice)\(plan.isAnnual ? "/year" : "/month")"
                            : "Processing…",
                        isEnabled: !subscriptions.isLoading
                    ) {
                        purchase(plan)
                    }
                }
                OnboardingTextButton("Restore Purchases") {
                    Task { @MainActor in
                        await subscriptions.restorePurchases()
                        confirmIfActive()
                    }
                }
                .disabled(subscriptions.isLoading)
            }
        }
        .task {
            guard !isPreview else { return }
            AnalyticsService.shared.capture(.paywallViewed(context: "onboarding"))
            // An existing subscriber never sees a second purchase prompt.
            await subscriptions.refreshEntitlements()
            confirmIfActive()
        }
        .onChange(of: subscriptions.hasAccess) { _ in
            if !isPreview { confirmIfActive() }
        }
    }

    private var orderedPlans: [SubscriptionPlan] {
        subscriptions.plans.sorted { left, _ in left.isAnnual }
    }

    private var selectedPlan: SubscriptionPlan? {
        subscriptions.plans.first { $0.id == selectedPlanID } ?? orderedPlans.first
    }

    private func planRow(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan?.id == plan.id
        return Button {
            NoxaHaptics.selection()
            selectedPlanID = plan.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? NoxaTheme.accent : NoxaTheme.border)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.isAnnual ? "Yearly" : "Monthly")
                        .font(NoxaType.headline)
                    Text(plan.periodDescription)
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                Spacer()
                Text(plan.displayPrice)
                    .font(NoxaTheme.font(22, weight: .bold, relativeTo: .title2))
                    .monospacedDigit()
            }
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(16)
            .background(
                isSelected ? NoxaTheme.accent.opacity(0.10) : NoxaTheme.elevated,
                in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous)
                    .stroke(isSelected ? NoxaTheme.accent : NoxaTheme.border, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(plan.isAnnual ? "Yearly" : "Monthly"), \(plan.displayPrice), \(plan.periodDescription)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func purchase(_ plan: SubscriptionPlan) {
        Task { @MainActor in
            let accountID = authentication.userID
            let purchased = await subscriptions.purchase(plan)
            guard purchased, authentication.userID == accountID else { return }
            confirmIfActive()
        }
    }

    private func retry() {
        isRetrying = true
        Task { @MainActor in
            await subscriptions.load()
            isRetrying = false
            confirmIfActive()
        }
    }

    /// Only a verified entitlement moves on; a button tap alone never does.
    private func confirmIfActive() {
        guard subscriptions.hasAccess, !hasConfirmed else { return }
        hasConfirmed = true
        onConfirmed()
    }
}

/// The quiet icon at the top of each setup step.
func setupIcon(_ symbol: String) -> some View {
    Image(systemName: symbol)
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(NoxaTheme.accent)
        .frame(width: 64, height: 64)
        .background(NoxaTheme.olive.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
}
