//
//  AppGroupStore.swift
//  Noxa
//

import FamilyControls
import Foundation
import os

/// Shared persistence boundary for the main app and Screen Time extensions.
///
/// The suite identifier must match the App Group capability configured on all
/// participating targets. A standard-defaults fallback is retained only so
/// the starter app can run before capabilities are configured; production
/// builds should treat `usesSharedSuite == false` as a configuration error.
final class AppGroupStore {
    static let suiteName = "group.LycheeCorp.Noxa"
    static let shared = AppGroupStore()

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "shared-state")

    private enum Key {
        static let localSnapshot = "noxa.localSnapshot"
        static let familyActivitySelection = "noxa.familyActivitySelection"
        static let focusSessionRestrictions = "noxa.focusSessionRestrictions"
        static let manualShield = "noxa.manualShield"
        static let websiteShieldActive = "noxa.websiteShieldActive"
        static let restrictionStoresMigrated = "noxa.restrictionStoresMigrated"
        static let websiteBlocklist = "noxa.websiteBlocklist"
        static let dailyLimits = "noxa.dailyLimits"
        static let restrictionSchedules = "noxa.restrictionSchedules"
        static let cloudSyncState = "noxa.cloudSyncState"
        static let cloudAccountCaches = "noxa.cloudAccountCaches"
    }

    let usesSharedSuite: Bool

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
            self.usesSharedSuite = true
        } else if let sharedDefaults = UserDefaults(suiteName: Self.suiteName) {
            self.defaults = sharedDefaults
            self.usesSharedSuite = true
        } else {
            self.defaults = .standard
            self.usesSharedSuite = false
            logger.fault("App Group suite is unavailable; using standard defaults")
        }
    }

    func loadSnapshot() throws -> NoxaLocalSnapshot? {
        guard let data = defaults.data(forKey: Key.localSnapshot) else {
            return nil
        }

        return try JSONDecoder().decode(NoxaLocalSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: NoxaLocalSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: Key.localSnapshot)
    }

    func clearSnapshot() {
        defaults.removeObject(forKey: Key.localSnapshot)
    }

    /// Stores Apple's opaque selection tokens in the shared suite. The tokens
    /// remain device-local and are never converted into bundle identifiers.
    func loadFamilyActivitySelection() throws -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Key.familyActivitySelection) else {
            return nil
        }

        return try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    func saveFamilyActivitySelection(_ selection: FamilyActivitySelection) throws {
        let data = try JSONEncoder().encode(selection)
        defaults.set(data, forKey: Key.familyActivitySelection)
    }

    func clearFamilyActivitySelection() {
        defaults.removeObject(forKey: Key.familyActivitySelection)
    }

    /// Stores the immutable device-local restriction snapshot for the active
    /// focus session. It is intentionally separate from the editable
    /// blocklist so a session remains enforceable after the app is terminated.
    func loadFocusSessionRestrictions() throws -> FocusSessionRestrictionConfiguration? {
        guard let data = defaults.data(forKey: Key.focusSessionRestrictions) else {
            return nil
        }

        return try JSONDecoder().decode(FocusSessionRestrictionConfiguration.self, from: data)
    }

    func saveFocusSessionRestrictions(_ configuration: FocusSessionRestrictionConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        defaults.set(data, forKey: Key.focusSessionRestrictions)
    }

    func clearFocusSessionRestrictions() {
        defaults.removeObject(forKey: Key.focusSessionRestrictions)
    }

    func loadManualShield() throws -> ManualShieldConfiguration? {
        guard let data = defaults.data(forKey: Key.manualShield) else { return nil }
        return try JSONDecoder().decode(ManualShieldConfiguration.self, from: data)
    }

    func saveManualShield(_ configuration: ManualShieldConfiguration) throws {
        defaults.set(try JSONEncoder().encode(configuration), forKey: Key.manualShield)
    }

    func clearManualShield() {
        defaults.removeObject(forKey: Key.manualShield)
    }

    var isWebsiteShieldActive: Bool {
        get { defaults.bool(forKey: Key.websiteShieldActive) }
        set { defaults.set(newValue, forKey: Key.websiteShieldActive) }
    }

    var hasMigratedRestrictionStores: Bool {
        get { defaults.bool(forKey: Key.restrictionStoresMigrated) }
        set { defaults.set(newValue, forKey: Key.restrictionStoresMigrated) }
    }

    /// Returns whether a focus session is in a start-pending or active state.
    /// The check is persisted so the UI and local services can reject edits
    /// even while the app is recovering from termination.
    func hasActiveFocusSession() -> Bool {
        guard let snapshot = try? loadSnapshot() else { return false }
        return snapshot.activeSession?.outcome == .active
            || snapshot.activeSession?.outcome == .startPending
    }

    func loadWebsiteBlocklist() throws -> [String] {
        guard let data = defaults.data(forKey: Key.websiteBlocklist) else {
            return []
        }

        return try JSONDecoder().decode([String].self, from: data)
    }

    func saveWebsiteBlocklist(_ domains: [String]) throws {
        let data = try JSONEncoder().encode(domains)
        defaults.set(data, forKey: Key.websiteBlocklist)
    }

    func clearWebsiteBlocklist() {
        defaults.removeObject(forKey: Key.websiteBlocklist)
    }

    func loadDailyLimitConfigurations() throws -> [DailyLimitConfiguration] {
        guard let data = defaults.data(forKey: Key.dailyLimits) else {
            return []
        }

        return try JSONDecoder().decode([DailyLimitConfiguration].self, from: data)
    }

    func saveDailyLimitConfigurations(_ configurations: [DailyLimitConfiguration]) throws {
        let data = try JSONEncoder().encode(configurations)
        defaults.set(data, forKey: Key.dailyLimits)
    }

    func clearDailyLimitConfigurations() {
        defaults.removeObject(forKey: Key.dailyLimits)
    }

    func loadRestrictionSchedules() throws -> [RestrictionScheduleConfiguration] {
        guard let data = defaults.data(forKey: Key.restrictionSchedules) else {
            return []
        }
        return try JSONDecoder().decode([RestrictionScheduleConfiguration].self, from: data)
    }

    func saveRestrictionSchedules(_ schedules: [RestrictionScheduleConfiguration]) throws {
        defaults.set(try JSONEncoder().encode(schedules), forKey: Key.restrictionSchedules)
    }

    func clearRestrictionSchedules() {
        defaults.removeObject(forKey: Key.restrictionSchedules)
    }

    func loadCloudSyncState() throws -> CloudSyncState? {
        guard let data = defaults.data(forKey: Key.cloudSyncState) else {
            return nil
        }

        return try JSONDecoder().decode(CloudSyncState.self, from: data)
    }

    func saveCloudSyncState(_ state: CloudSyncState) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: Key.cloudSyncState)
    }

    func clearCloudSyncState() {
        defaults.removeObject(forKey: Key.cloudSyncState)
    }

    func loadCloudAccountCache(userID: UUID) throws -> CloudAccountCache? {
        guard let data = defaults.data(forKey: Key.cloudAccountCaches) else {
            return nil
        }
        let caches = try JSONDecoder().decode([String: CloudAccountCache].self, from: data)
        return caches[userID.uuidString]
    }

    func saveCloudAccountCache(_ cache: CloudAccountCache, userID: UUID) throws {
        var caches: [String: CloudAccountCache] = [:]
        if let data = defaults.data(forKey: Key.cloudAccountCaches) {
            caches = try JSONDecoder().decode([String: CloudAccountCache].self, from: data)
        }
        caches[userID.uuidString] = cache
        defaults.set(try JSONEncoder().encode(caches), forKey: Key.cloudAccountCaches)
    }

    func clearCloudAccountCaches() {
        defaults.removeObject(forKey: Key.cloudAccountCaches)
    }
}
