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
    @StateObject private var analytics = AnalyticsService.shared
    @StateObject private var authentication = AuthenticationService()
    @StateObject private var subscriptions = SubscriptionService()
    @StateObject private var focusSession = FocusSessionService()
    @StateObject private var onboarding = OnboardingService()
    @StateObject private var restrictions = ScreenTimeRestrictionService()
    @StateObject private var monitoring = DeviceActivityMonitoringService()
    @StateObject private var dailyLimits = DailyLimitService()
    @StateObject private var schedules = RestrictionScheduleService()
    @StateObject private var websites = WebsiteBlocklistService()
    @StateObject private var cloudSync = CloudSyncService()
    @StateObject private var notifications = FocusNotificationService()

    private var hasActiveRestrictions: Bool {
        focusSession.isActive
            || restrictions.isShieldActive
            || websites.isBlocklistActive
            || monitoring.isMonitoring
            || dailyLimits.isMonitoring
            || dailyLimits.isShieldActive
            || schedules.enabledCount > 0
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authentication.isBootstrapping {
                    NoxaLoadingView(message: "Opening Noxa…")
                } else if hasActiveRestrictions
                            && (!authentication.isAuthenticated
                                || (subscriptions.hasLoaded && !subscriptions.hasAccess)) {
                    RestrictionRecoveryView()
                } else if !authentication.isAuthenticated {
                    if onboarding.isAuthenticationRequested {
                        AuthenticationView(
                            initialMode: initialAuthenticationMode,
                            initialEmail: initialAuthenticationMode == .signIn
                                ? (authentication.rememberedUserEmail ?? "")
                                : ""
                        )
                    } else if onboarding.isPersonalizationRequested {
                        OnboardingView()
                    } else if authentication.hasRememberedAccount {
                        ReturningUserView()
                    } else {
                        OnboardingWelcomeView()
                    }
                } else if !onboarding.isComplete(
                    for: authentication.userID,
                    remoteCompletion: authentication.hasCompletedOnboarding
                ) {
                    if onboarding.progress.hasSeenValueOverview,
                       !onboarding.progress.hasSeenPricingPreview {
                        PaywallView(allowsDismissal: false) {
                            _ = onboarding.completePricingPreview()
                        }
                    } else {
                        OnboardingView()
                    }
                } else {
                    if cloudSync.boundUserID != authentication.userID {
                        NoxaLoadingView(message: "Loading your account…")
                    } else if !subscriptions.hasLoaded {
                        NoxaLoadingView(message: "Loading")
                    } else if subscriptions.canEnterApp(for: authentication.userID) {
                        ContentView()
                    } else {
                        PaywallView(allowsDismissal: false)
                    }
                }
            }
            .environmentObject(authentication)
            .environmentObject(analytics)
            .environmentObject(subscriptions)
            .environmentObject(focusSession)
            .environmentObject(onboarding)
            .environmentObject(restrictions)
            .environmentObject(monitoring)
            .environmentObject(dailyLimits)
            .environmentObject(schedules)
            .environmentObject(websites)
            .environmentObject(cloudSync)
            .environmentObject(notifications)
            .task {
                RestrictionStoreMigration.migrateIfNeeded()
                restrictions.reconcile()
                websites.reconcile()
                analytics.configure()
                await authentication.bootstrap()
                await bindAccountServices()
                await reconcileOnboardingAccount()
                focusSession.reconcile()
                restrictions.reconcile()
                websites.reconcile()
                dailyLimits.rescheduleActiveMonitoring()
                schedules.reconcile()
                await syncCloudDataIfAuthenticated()
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                focusSession.reconcile()
                restrictions.reconcile()
                websites.reconcile()
                dailyLimits.reconcileDayBoundary()
                schedules.reconcile()
                Task {
                    if subscriptions.boundUserID == authentication.userID {
                        await subscriptions.refreshEntitlements()
                    }
                    await reconcileOnboardingAccount()
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dailyLimits.reconcileDayBoundary()
            }
            .onChange(of: authentication.isAuthenticated) { isAuthenticated in
                guard isAuthenticated else {
                    // Do not let a request started for the previous account
                    // publish data after sign-out.
                    cloudSync.invalidatePendingWork()
                    analytics.reset()
                    onboarding.clearTransientRoute()
                    Task { await subscriptions.unbind() }
                    return
                }
                Task {
                    await bindAccountServices()
                    await reconcileOnboardingAccount()
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onChange(of: authentication.userID) { _ in
                // A user switch can happen while `isAuthenticated` remains
                // true. Invalidate the previous account's in-flight work and
                // hydrate only the newly bound account.
                cloudSync.invalidatePendingWork()
                guard authentication.isAuthenticated else {
                    analytics.reset()
                    Task { await subscriptions.unbind() }
                    return
                }
                Task {
                    await bindAccountServices()
                    await reconcileOnboardingAccount()
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onChange(of: onboarding.progress.isComplete) { isComplete in
                guard isComplete else { return }
                Task {
                    await reconcileOnboardingAccount()
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

    private var initialAuthenticationMode: AuthenticationView.Mode {
        guard !onboarding.progress.isComplete,
              let rawValue = onboarding.progress.draftSetupConfiguration["authenticationMode"],
              let mode = AuthenticationView.Mode(rawValue: rawValue) else {
            return .signIn
        }
        return mode
    }

    private func bindAccountServices() async {
        guard authentication.isAuthenticated, let userID = authentication.userID else {
            analytics.reset()
            await subscriptions.unbind()
            return
        }
        analytics.identify(userID: userID)
        await subscriptions.bind(to: userID)
    }

    private func reconcileOnboardingAccount() async {
        guard authentication.isAuthenticated, let userID = authentication.userID else { return }
        _ = onboarding.bind(
            to: userID,
            remoteCompletion: authentication.hasCompletedOnboarding
        )
        if onboarding.progress.isComplete && !authentication.hasCompletedOnboarding {
            _ = await authentication.syncOnboardingProfile(onboarding.progress)
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
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var focusSession: FocusSessionService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var websites: WebsiteBlocklistService
    @EnvironmentObject private var monitoring: DeviceActivityMonitoringService
    @EnvironmentObject private var dailyLimits: DailyLimitService
    @EnvironmentObject private var schedules: RestrictionScheduleService
    @State private var isLoginPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(focusSession.isActive ? "Restrictions are still active" : "Noxa restrictions are still active")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(authentication.isAuthenticated
                 ? "Renew your subscription to return to Noxa while these protections remain active."
                 : "Log in again to return to Noxa. Your active restrictions will stay protected.")
                .foregroundStyle(.secondary)

            if focusSession.isActive, let endTime = focusSession.endTimeDescription {
                Text("Scheduled to end at \(endTime).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !authentication.isAuthenticated {
                RecoveryActionButton(title: "Log In Again") {
                    isLoginPresented = true
                }
            }

            if focusSession.isActive && !focusSession.isActiveSessionStrict {
                RecoveryActionButton(title: "End Focus Session") {
                    focusSession.endEarly()
                }
            }

            if restrictions.isShieldActive && !focusSession.isActive {
                RecoveryActionButton(title: "Remove App and Website Shield") {
                    restrictions.removeShield()
                }
            }

            if websites.isBlocklistActive && !focusSession.isActive {
                RecoveryActionButton(title: "Remove Website Blocklist") {
                    websites.clearBlocklist()
                }
            }

            if monitoring.isMonitoring {
                RecoveryActionButton(title: "Stop Usage Monitor") {
                    monitoring.stop()
                }
            }

            if dailyLimits.isMonitoring || dailyLimits.isShieldActive {
                if dailyLimits.isHardLimitLocked {
                    Label("Hard daily limits remain active until tomorrow", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    RecoveryActionButton(title: "Stop Daily Limits") {
                        dailyLimits.stopMonitoring()
                    }
                }
            }

            if schedules.enabledCount > 0 {
                if schedules.enabledWithoutPendingRelaxationCount > 0 {
                    RecoveryActionButton(title: "Request Schedule Stop") {
                        schedules.requestDisableAll()
                    }
                }
                if let effectiveAt = schedules.nextPendingRelaxationDate {
                    Text("Schedule changes remain protected until \(effectiveAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(NoxaTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isLoginPresented) {
            AuthenticationView(
                initialMode: .signIn,
                initialEmail: authentication.rememberedUserEmail ?? ""
            )
        }
        .onChange(of: authentication.isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                isLoginPresented = false
            }
        }
    }
}

private struct RecoveryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}
