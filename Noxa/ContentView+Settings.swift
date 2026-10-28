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
                    NoxaCardHeader(title: "Signed in", systemImage: "checkmark.shield.fill")
                    if let displayName = authentication.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                    }
                    Text(authentication.userEmail ?? "Apple account")
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .accessibilityLabel("Signed in as \(authentication.userEmail ?? "Apple account")")
                    Text("Screen Time selections and active shields stay on this device. Focus history and website domains sync securely when you’re online.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaCard()

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
                    Toggle("Share usage analytics", isOn: $analytics.isEnabled)
                        .font(NoxaType.headline)
                        .tint(NoxaTheme.accent)
                    Text("Helps improve Noxa using feature events and coarse counts. Noxa never sends your email, name, selected apps or websites, typed intentions, or screen recordings.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaCard()

                settingsSectionTitle("Instagram website")

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Instagram website", selection: $instagramSiteMode) {
                        Text("Off").tag(InstagramSiteMode.off)
                        Text("Hide Reels and Explore").tag(InstagramSiteMode.distractionFree)
                    }
                        .font(NoxaType.headline)
                        .onChange(of: instagramSiteMode) { mode in
                            AppGroupStore.shared.setInstagramSiteMode(mode)
                            if mode != .distractionFree {
                                instagramAppBlockEnabled = false
                                instagramAppBlockMessage = nil
                            }
                            InstagramSiteProtectionService.reconcile()
                        }
                    if instagramSiteMode == .distractionFree {
                        Text("Experimental Safari filter: aims to hide Reels and Explore while keeping the feed available. Embedded Reels may still appear.")
                            .font(NoxaType.footnote)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        instagramAppBlockControls
                        Text(safariFilterStatusMessage)
                            .font(NoxaType.footnote)
                            .foregroundStyle(safariFilterRecentlyConnected ? Color.secondary : Color.orange)
                        if websites.domains.contains(where: { $0 == "instagram.com" || $0 == "www.instagram.com" }) {
                            Text("Instagram is also in your website blocklist. Remove that independent block to keep the feed available.")
                                .font(NoxaType.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    Link("Report a filter problem", destination: NoxaWebLinks.support)
                        .font(NoxaType.subheadlineSemibold)
                }
                .noxaCard()
                .task {
                    await refreshSafariExtensionStatus()
                }

                settingsSectionTitle("Support & Legal")

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(title: "Blocking looks wrong?", systemImage: "arrow.clockwise")
                    Text("Refresh your active rules if something stays blocked after its rule ends, or if a selected app is not blocked.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Button("Refresh Blocking") {
                        authorization.refresh()
                        focusSession.reconcile()
                        restrictions.reconcile()
                        websites.reconcile()
                        dailyLimits.reconcileDayBoundary()
                        schedules.reconcile()
                        InstagramSiteProtectionService.reconcile()
                        didRepairRestrictions = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    if didRepairRestrictions {
                        Text("Rules refreshed. Open the affected app or site to check its shield. If the problem remains, contact support.")
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
                    Text("Wait until the active focus session ends before signing out or deleting your account.")
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
