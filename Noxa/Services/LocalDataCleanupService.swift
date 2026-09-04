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
        focusSession: FocusSessionService,
        restrictions: ScreenTimeRestrictionService,
        monitoring: DeviceActivityMonitoringService,
        dailyLimits: DailyLimitService,
        websites: WebsiteBlocklistService,
        cloudSync: CloudSyncService,
        store: AppGroupStore? = nil
    ) {
        let store = store ?? AppGroupStore.shared
        monitoring.stop()
        dailyLimits.clearConfigurations()
        restrictions.clearSelection(force: true)
        websites.removeAllDomains(force: true)
        focusSession.clearAllLocalData()
        cloudSync.clearState()
        store.clearCloudSyncState()
        store.clearCloudAccountCaches()
    }
}
