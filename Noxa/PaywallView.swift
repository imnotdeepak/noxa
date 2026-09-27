import StoreKit
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

    init(allowsDismissal: Bool = true, onAccessConfirmed: (() -> Void)? = nil) {
        self.allowsDismissal = allowsDismissal
        self.onAccessConfirmed = onAccessConfirmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text(subscriptions.hasAccess ? "Your Noxa subscription" : "Simple pricing. Full focus.")
                            .font(NoxaTheme.font(38, weight: .bold, relativeTo: .largeTitle))
                            .tracking(-1)
                            .multilineTextAlignment(.center)
                        Text(subscriptions.hasAccess
                             ? "An active subscription was found on this Apple Account. Continue to use it with this Noxa account."
                             : "Every plan includes the complete Noxa experience.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    if !subscriptions.hasAccess {
                        VStack(alignment: .leading, spacing: 12) {
                            paywallFeature("Focused app and website blocking")
                            paywallFeature("Timed focus sessions and daily limits")
                            paywallFeature("Focus history")
                            paywallFeature("Future Noxa improvements")
                        }
                        .noxaCard()
                    }

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
                        VStack(spacing: 16) {
                            Label("Your Noxa subscription is active", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.headline)
                            if !allowsDismissal || onAccessConfirmed != nil {
                                Button(onAccessConfirmed == nil ? "Continue with Current Subscription" : "Start with Noxa") {
                                    confirmAccess()
                                }
                                .buttonStyle(NoxaPrimaryButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else if subscriptions.products.isEmpty {
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
                        ForEach(orderedProducts) { product in
                            Button {
                                Task {
                                    let accountID = authentication.userID
                                    let purchased = await subscriptions.purchase(product)
                                    guard purchased, authentication.userID == accountID else { return }
                                    subscriptions.continueWithCurrentSubscription(for: accountID)
                                    onAccessConfirmed?()
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Text(product.displayName)
                                        .font(NoxaTheme.font(18, weight: .semibold, relativeTo: .headline))
                                    if subscriptions.purchasingProductID == product.id {
                                        ProgressView()
                                            .tint(.white)
                                            .accessibilityLabel("Processing")
                                    } else {
                                        Text(product.displayPrice)
                                            .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                                            .monospacedDigit()
                                    }
                                    Text(subscriptionPeriodText(for: product))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if product.id == SubscriptionService.annualProductID {
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
                                subscriptions.purchasingProductID == product.id
                                    ? "Processing purchase"
                                    : product.displayPrice
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

                    if let message = subscriptions.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(subscriptions.hasAccess ? .green : .secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Subscriptions are billed by Apple and renew automatically until canceled. Manage or cancel them in your Apple Account settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .font(NoxaTheme.font(17))
            .background(NoxaBackground())
            .preferredColorScheme(.dark)
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

    private var orderedProducts: [Product] {
        subscriptions.products.sorted { left, right in
            if left.id == SubscriptionService.annualProductID { return true }
            if right.id == SubscriptionService.annualProductID { return false }
            return left.id < right.id
        }
    }

    private func paywallFeature(_ title: String) -> some View {
        Label(title, systemImage: "checkmark")
            .font(NoxaTheme.font(15, weight: .medium, relativeTo: .subheadline))
    }

    private func confirmAccess() {
        guard subscriptions.hasAccess else { return }
        subscriptions.continueWithCurrentSubscription(for: authentication.userID)
        onAccessConfirmed?()
    }

    private func subscriptionPeriodText(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return "Auto-renewing subscription"
        }

        switch period.unit {
        case .day: return period.value == 1 ? "Billed daily" : "Billed every \(period.value) days"
        case .week: return period.value == 1 ? "Billed weekly" : "Billed every \(period.value) weeks"
        case .month: return period.value == 1 ? "Billed monthly" : "Billed every \(period.value) months"
        case .year: return period.value == 1 ? "Billed annually" : "Billed every \(period.value) years"
        @unknown default: return "Auto-renewing subscription"
        }
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
