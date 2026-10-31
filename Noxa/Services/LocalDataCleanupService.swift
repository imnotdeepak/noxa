//
//  LocalDataCleanupService.swift
//  Noxa
//

import Foundation

/// Clears Noxa-owned device state after the server confirms account deletion.
/// Apple-managed selection tokens are removed locally; no token is sent to the
/// server as part of account deletion.
@MainActor
enum LocalDataCleanupService {
    static func clear(
        accountID: UUID,
        focusSession: FocusSessionService,
        restrictions: ScreenTimeRestrictionService,
        monitoring: DeviceActivityMonitoringService,
        dailyLimits: DailyLimitService,
        schedules: RestrictionScheduleService,
        websites: WebsiteBlocklistService,
        cloudSync: CloudSyncService,
        onboarding: OnboardingService,
        store: AppGroupStore? = nil
    ) {
        let store = store ?? AppGroupStore.shared
        monitoring.stop()
        dailyLimits.removeConfigurations(ownedBy: accountID)
        schedules.removeConfigurations(ownedBy: accountID)
        restrictions.removeShield(force: true)
        store.removeEditableConfiguration(for: accountID)
        restrictions.reloadSelectionForAccount()
        websites.reloadForAccount()
        focusSession.replaceHistory([])
        store.clearScreenTimeAccessPauses()
        store.clearLegacyStrictModePreference()
        cloudSync.clearState()
        _ = onboarding.reset()
        store.clearCloudSyncState()
        store.removeCloudAccountCache(userID: accountID)
        store.setSafariFilterAllowedUntil(nil)
        InstagramSiteProtectionService.reconcile(store: store)
        YouTubeShortsProtectionService.reconcile(store: store)
    }
}
