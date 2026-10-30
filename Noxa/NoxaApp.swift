//
//  NoxaApp.swift
//  Noxa
//
//  Created by Deepak on 9/2/26.
//

import SwiftUI
import UIKit

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
    @StateObject private var focusLaunchRouter = FocusLaunchRouter.shared

    private var hasActiveRestrictions: Bool {
        focusSession.isActive
            || focusSession.hasPomodoroCycle
            || restrictions.isShieldActive
            || websites.isBlocklistActive
            || monitoring.isMonitoring
            || dailyLimits.isMonitoring
            || dailyLimits.isShieldActive
            || schedules.enabledCount > 0
            || InstagramSiteProtectionService.isAppBlockApplied
            || YouTubeShortsProtectionService.isAppBlockApplied
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
                                : "",
                            onBack: leaveAuthentication
                        )
                    } else if onboarding.isPersonalizationRequested
                                || onboarding.hasUnfinishedNewUserDraft {
                        // A relaunch quietly returns to an unfinished setup.
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
                    // Setup, the paywall and the Pact all live in the flow.
                    OnboardingView()
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
            .environmentObject(focusLaunchRouter)
            .task {
                RestrictionStoreMigration.migrateIfNeeded()
                InstagramSiteProtectionService.reconcile()
                YouTubeShortsProtectionService.reconcile()
                restrictions.reconcile()
                websites.reconcile()
                analytics.configure()
                await authentication.bootstrap()
                await bindAccountServices()
                await reconcileOnboardingAccount()
                reconcileFocusAndNotifications()
                await restoreFocusNotificationsAfterLaunch()
                await FocusPresentationCoordinator.reconcile(session: focusSession.activeSession)
                restrictions.reconcile()
                websites.reconcile()
                dailyLimits.rescheduleActiveMonitoring()
                schedules.reconcile()
                await syncCloudDataIfAuthenticated()
            }
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                InstagramSiteProtectionService.reconcile()
                YouTubeShortsProtectionService.reconcile()
                reconcileFocusAndNotifications()
                Task { await FocusPresentationCoordinator.reconcile(session: focusSession.activeSession) }
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
                schedules.reconcile()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                // Local schedule windows and elapsed session deadlines may
                // have changed while this process remained in the foreground.
                reconcileFocusAndNotifications()
                dailyLimits.reconcileDayBoundary()
                schedules.reconcile()
                Task {
                    await FocusPresentationCoordinator.reconcile(session: focusSession.activeSession)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                // Reevaluate local weekdays and clock times after travel.
                schedules.reconcile()
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
            .onChange(of: focusSession.activeSession) { session in
                Task { await FocusPresentationCoordinator.reconcile(session: session) }
            }
            .onChange(of: websites.domains) { _ in
                Task {
                    await syncCloudDataIfAuthenticated()
                }
            }
            .onOpenURL { url in
                if focusLaunchRouter.handle(url) { return }
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

    /// Back from sign-in or sign-up: to the narrative when the user came from
    /// it, otherwise to Welcome. Answers are kept either way.
    private func leaveAuthentication() {
        if onboarding.progress.hasSeenProductDemo && !onboarding.progress.isComplete {
            onboarding.returnToPersonalization()
        } else {
            onboarding.clearTransientRoute()
        }
    }

    @MainActor
    private func reconcileFocusAndNotifications() {
        let previousCycleID = focusSession.pomodoroCycle?.id
        let previousSessionID = focusSession.activeSession?.id
        focusSession.reconcile()
        if let previousCycleID,
           focusSession.pomodoroCycle?.id != previousCycleID {
            notifications.cancelPomodoroCycle(previousCycleID)
        }
        if let previousSessionID,
           focusSession.activeSession?.id != previousSessionID {
            notifications.cancel(for: previousSessionID)
        }
    }

    @MainActor
    private func restoreFocusNotificationsAfterLaunch() async {
        await notifications.refreshAuthorizationStatus()
        guard notifications.canSchedule else { return }
        if let cycle = focusSession.pomodoroCycle {
            await notifications.schedulePomodoroCycle(cycle)
        } else if let session = focusSession.activeSession {
            await notifications.schedule(for: session)
        }
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
    @EnvironmentObject private var notifications: FocusNotificationService
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
                    if let cycle = focusSession.pomodoroCycle {
                        notifications.cancelPomodoroCycle(cycle.id)
                    }
                    focusSession.endEarly()
                }
            }

            if focusSession.pomodoroBreakEndsAt != nil {
                RecoveryActionButton(title: "Stop Pomodoro During Break") {
                    if let cycle = focusSession.pomodoroCycle {
                        notifications.cancelPomodoroCycle(cycle.id)
                    }
                    focusSession.stopPomodoroDuringBreak()
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

            if InstagramSiteProtectionService.isAppBlockApplied && !focusSession.isActive {
                RecoveryActionButton(title: "Remove Instagram App Block") {
                    AppGroupStore.shared.setInstagramAppBlockEnabled(false)
                    InstagramSiteProtectionService.reconcile()
                }
            }

            if YouTubeShortsProtectionService.isAppBlockApplied && !focusSession.isActive {
                RecoveryActionButton(title: "Remove YouTube App Block") {
                    AppGroupStore.shared.setYouTubeAppBlockEnabled(false)
                    YouTubeShortsProtectionService.reconcile()
                }
            }

            if monitoring.isMonitoring {
                RecoveryActionButton(title: "Stop Usage Monitor") {
                    monitoring.stop()
                }
            }

            if dailyLimits.isMonitoring || dailyLimits.isShieldActive {
                RecoveryActionButton(title: "Stop Daily Limits") {
                    if authentication.isAuthenticated {
                        dailyLimits.stopMonitoring()
                    } else {
                        dailyLimits.requestStop()
                    }
                }
                if !authentication.isAuthenticated, let message = dailyLimits.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if schedules.enabledCount > 0 {
                RecoveryActionButton(title: "Stop Schedules") {
                    schedules.requestDisableAll()
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
