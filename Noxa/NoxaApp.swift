//
//  NoxaApp.swift
//  Noxa
//
//  Created by Deepak on 9/2/26.
//

import SwiftUI

@main
struct NoxaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authentication = AuthenticationService()
    @StateObject private var subscriptions = SubscriptionService()
    @StateObject private var focusSession = FocusSessionService()
    @StateObject private var onboarding = OnboardingService()
    @StateObject private var restrictions = ScreenTimeRestrictionService()
    @StateObject private var monitoring = DeviceActivityMonitoringService()
    @StateObject private var dailyLimits = DailyLimitService()
    @StateObject private var websites = WebsiteBlocklistService()
    @StateObject private var cloudSync = CloudSyncService()
    @StateObject private var notifications = FocusNotificationService()

    private var hasActiveRestrictions: Bool {
        focusSession.isActive
            || restrictions.isShieldActive
            || monitoring.isMonitoring
            || dailyLimits.isMonitoring
            || dailyLimits.isShieldActive
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authentication.isBootstrapping {
                    ProgressView("Opening Noxa…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .preferredColorScheme(.dark)
                } else if hasActiveRestrictions
                            && (!authentication.isAuthenticated
                                || (subscriptions.hasLoaded && !subscriptions.hasAccess)) {
                    RestrictionRecoveryView()
                } else if !onboarding.progress.hasSeenCapabilitiesExplainer {
                    OnboardingView()
                } else if authentication.isAuthenticated {
                    if cloudSync.boundUserID != authentication.userID {
                        ProgressView("Loading your account…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .preferredColorScheme(.dark)
                    } else if !subscriptions.hasLoaded {
                        ProgressView("Checking subscription…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .preferredColorScheme(.dark)
                    } else if subscriptions.canEnterApp(for: authentication.userID) {
                        ContentView()
                    } else {
                        PaywallView(allowsDismissal: false)
                    }
                } else {
                    AuthenticationView()
                }
            }
            .environmentObject(authentication)
            .environmentObject(subscriptions)
            .environmentObject(focusSession)
            .environmentObject(onboarding)
            .environmentObject(restrictions)
            .environmentObject(monitoring)
            .environmentObject(dailyLimits)
            .environmentObject(websites)
            .environmentObject(cloudSync)
            .environmentObject(notifications)
            .task {
                await authentication.bootstrap()
                await subscriptions.load()
                focusSession.reconcile()
                await syncCloudDataIfAuthenticated()
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                focusSession.reconcile()
                Task {
                    if subscriptions.hasLoaded {
                        await subscriptions.refreshEntitlements()
                    }
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onChange(of: authentication.isAuthenticated) { isAuthenticated in
                guard isAuthenticated else {
                    // Do not let a request started for the previous account
                    // publish data after sign-out.
                    cloudSync.invalidatePendingWork()
                    return
                }
                Task {
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onChange(of: authentication.userID) { _ in
                // A user switch can happen while `isAuthenticated` remains
                // true. Invalidate the previous account's in-flight work and
                // hydrate only the newly bound account.
                cloudSync.invalidatePendingWork()
                guard authentication.isAuthenticated else { return }
                Task {
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onChange(of: focusSession.history) { _ in
                Task {
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onChange(of: websites.domains) { _ in
                Task {
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onOpenURL { url in
                Task {
                    await authentication.handleAuthCallback(url)
                }
            }
            .sheet(isPresented: $authentication.isPasswordRecoveryPresented) {
                PasswordUpdateView()
                    .environmentObject(authentication)
            }
        }
    }

    private func syncCloudDataIfAuthenticated() async {
        guard authentication.isAuthenticated, let userID = authentication.userID else { return }
        let prepared = cloudSync.prepareLocalData(
            for: userID,
            history: focusSession.history,
            websiteDomains: websites.domains
        )
        guard authentication.isAuthenticated, authentication.userID == userID else { return }
        applyCloudResult(prepared)

        if let synchronized = await cloudSync.sync(
            history: prepared.focusHistory,
            websiteDomains: prepared.websiteDomains
        ) {
            // A sign-out or account switch may have happened while the network
            // request was suspended. Never hydrate that result into the new
            // account's local state.
            guard authentication.isAuthenticated, authentication.userID == userID else { return }
            applyCloudResult(synchronized)
        }
    }

    private func applyCloudResult(_ result: CloudSyncMergeResult) {
        websites.replaceDomains(result.websiteDomains)
        focusSession.replaceHistory(result.focusHistory)
    }
}

/// Keeps a safe cleanup path available if authentication or subscription
/// access is lost while any local restriction is still enforcing.
private struct RestrictionRecoveryView: View {
    @EnvironmentObject private var focusSession: FocusSessionService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var monitoring: DeviceActivityMonitoringService
    @EnvironmentObject private var dailyLimits: DailyLimitService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(focusSession.isActive ? "Restrictions are still active" : "Noxa restrictions are still active")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Remove the active restrictions before signing in again or renewing your subscription.")
                .foregroundStyle(.secondary)

            if focusSession.isActive, let endTime = focusSession.endTimeDescription {
                Text("Scheduled to end at \(endTime).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if focusSession.isActive {
                RecoveryActionButton(title: "End Focus Session") {
                    focusSession.endEarly()
                }
            }

            if restrictions.isShieldActive && !focusSession.isActive {
                RecoveryActionButton(title: "Remove App and Website Shield") {
                    restrictions.removeShield()
                }
            }

            if monitoring.isMonitoring {
                RecoveryActionButton(title: "Stop Usage Monitor") {
                    monitoring.stop()
                    if !focusSession.isActive {
                        restrictions.removeShield()
                    }
                }
            }

            if dailyLimits.isMonitoring || dailyLimits.isShieldActive {
                RecoveryActionButton(title: "Stop Daily Limits") {
                    dailyLimits.stopMonitoring()
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct RecoveryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
