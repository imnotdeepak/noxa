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
    @EnvironmentObject private var websites: WebsiteBlocklistService
    @EnvironmentObject private var cloudSync: CloudSyncService
    let allowsDismissal: Bool
    @State private var isDeleteAccountConfirmationPresented = false

    init(allowsDismissal: Bool = true) {
        self.allowsDismissal = allowsDismissal
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your Noxa plan")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .tracking(-1)
                        Text("A subscription is required to use Noxa and its focus tools.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        featureRow("Focused app and website blocking")
                        featureRow("Timed focus sessions and daily limits")
                        featureRow("Focus history and future improvements")
                    }
                    .noxaCard()

                    if subscriptions.hasAccess {
                        Label("Your Noxa subscription is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                    } else if subscriptions.products.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            if subscriptions.isLoading {
                                ProgressView("Loading plans…")
                            } else {
                                Text("Plans are not available yet.")
                                    .font(.headline)
                                Text("The app is ready for StoreKit testing. Add the product IDs shown in SubscriptionService.swift to App Store Connect or an Xcode StoreKit configuration file.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .noxaCard()
                    } else {
                        ForEach(subscriptions.products) { product in
                            Button {
                                Task {
                                    await subscriptions.purchase(product)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Text(product.description)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.headline.monospacedDigit())
                                }
                            }
                            .buttonStyle(NoxaPaywallPlanButtonStyle())
                            .disabled(subscriptions.isLoading)
                        }
                    }

                    Button("Restore Purchases") {
                        Task {
                            await subscriptions.restorePurchases()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .disabled(subscriptions.isLoading)

                    if !allowsDismissal {
                        Button("Sign Out") {
                            Task {
                                await authentication.signOut()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .disabled(authentication.isBusy)
                    }

                    Button("Delete Account", role: .destructive) {
                        isDeleteAccountConfirmationPresented = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .disabled(authentication.isBusy)

                    Link("Manage subscriptions in Apple settings", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let message = subscriptions.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(subscriptions.hasAccess ? .green : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Subscriptions are billed by Apple. You can manage or cancel them from your Apple Account settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
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
                            websites: websites,
                            cloudSync: cloudSync
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

    private func featureRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark")
            .font(.subheadline)
    }
}

private struct NoxaPaywallPlanButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
