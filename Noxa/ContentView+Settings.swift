import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                settingsSectionTitle("Account")

                VStack(alignment: .leading, spacing: 12) {
                    NoxaCardHeader(
                        title: "Signed in",
                        systemImage: "checkmark.shield.fill",
                        info: "Screen Time selections and active shields stay on this device. Focus history and website domains sync securely when you're online."
                    )
                    if let displayName = authentication.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                    }
                    Text(authentication.userEmail ?? "Apple account")
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .accessibilityLabel("Signed in as \(authentication.userEmail ?? "Apple account")")
                }
                .noxaCard()

                Button("Preview Onboarding") {
                    isOnboardingReplayPresented = true
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .accessibilityHint("View setup, pricing, and the Pact without changing your account")

                VStack(alignment: .leading, spacing: 12) {
                    Label("Noxa subscription", systemImage: subscriptions.hasAccess ? "checkmark.seal.fill" : "creditcard")
                        .font(NoxaType.headline)
                    Text(subscriptions.hasAccess
                         ? "\(subscriptions.activePlanDisplayName) is active."
                         : "A subscription is required to use Noxa.")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Button(subscriptions.hasAccess ? "View Subscription" : "See Subscription Plans") {
                        isPaywallPresented = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }
                .noxaCard()

                settingsSectionTitle("Preferences")

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $analytics.isEnabled) {
                        HStack(spacing: 4) {
                            Text("Share usage analytics")
                            NoxaInfoButton(
                                title: "Usage analytics",
                                message: "Helps improve Noxa with feature events and rough counts. Noxa never sends your email, name, selected apps or websites, typed intentions, or screen recordings."
                            )
                        }
                    }
                    .font(NoxaType.headline)
                    .tint(NoxaTheme.accent)
                    Text("Never includes your apps, sites or name.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaCard()

                settingsSectionTitle("Support & Legal")

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(
                        title: "Blocking looks wrong?",
                        systemImage: "arrow.clockwise",
                        info: "Refresh if something stays blocked after its rule ends, or a selected app isn't blocked."
                    )
                    Button("Refresh Blocking") {
                        authorization.refresh()
                        focusSession.reconcile()
                        restrictions.reconcile()
                        websites.reconcile()
                        dailyLimits.reconcileDayBoundary()
                        schedules.reconcile()
                        InstagramSiteProtectionService.reconcile()
                        YouTubeShortsProtectionService.reconcile()
                        didRepairRestrictions = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    if didRepairRestrictions {
                        Text("Refreshed. Still wrong? Contact support.")
                            .font(NoxaType.footnote)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                }
                .noxaCard()

                SettingsSupportLinksView()

                settingsSectionTitle("Data & Sync")

                cloudSyncStatusCard

                Button("Sign Out") {
                    Task {
                        await authentication.signOut()
                        if !authentication.isAuthenticated {
                            focusSession.discardScheduleSuggestion()
                        }
                    }
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(authentication.isBusy || focusSession.isActive || focusSession.hasPomodoroCycle)

                Button("Delete Account", role: .destructive) {
                    isDeleteAccountConfirmationPresented = true
                }
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .disabled(authentication.isBusy || focusSession.isActive || focusSession.hasPomodoroCycle)

                if focusSession.isActive || focusSession.hasPomodoroCycle {
                    Text("Available after your Focus session ends.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }

                if let message = authentication.message {
                    Text(message)
                        .font(NoxaType.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView()
                .environmentObject(subscriptions)
        }
        .fullScreenCover(isPresented: $isOnboardingReplayPresented) {
            OnboardingReplayView()
        }
    }

    func settingsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(NoxaTheme.font(18, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }

    var cloudSyncStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: cloudSync.status.iconName)
                .foregroundStyle(cloudSync.status == .failed ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(cloudSync.status.title)
                    .font(NoxaType.subheadlineSemibold)
                if let lastSync = cloudSync.lastSuccessfulSyncAt {
                    Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                } else if let errorMessage = cloudSync.errorMessage {
                    Text(errorMessage)
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                if cloudSync.hasPendingWork {
                    Button("Retry now") {
                        Task { @MainActor in
                            if let result = await cloudSync.sync(
                                history: focusSession.history,
                                websiteDomains: websites.domains
                            ) {
                                websites.replaceDomains(result.websiteDomains)
                                focusSession.replaceHistory(result.focusHistory)
                            }
                        }
                    }
                    .font(NoxaType.footnoteSemibold)
                    .foregroundStyle(.white)
                }
            }
            Spacer()
        }
        .noxaCard()
    }

    func deleteAccountAndLocalData() async {
        guard !focusSession.isActive && !focusSession.hasPomodoroCycle else { return }
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
