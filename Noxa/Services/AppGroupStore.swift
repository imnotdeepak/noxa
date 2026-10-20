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
        static let focusMonitorReceipt = "noxa.focusMonitorReceipt"
        static let safariFilterEnabled = "noxa.safariFilterEnabled"
        static let safariFilterAllowedUntil = "noxa.safariFilterAllowedUntil"
        static let instagramSiteMode = "noxa.instagramSiteMode"
        static let manualShield = "noxa.manualShield"
        static let websiteShieldActive = "noxa.websiteShieldActive"
        static let restrictionStoresMigrated = "noxa.restrictionStoresMigrated"
        static let strictModeEnabled = "noxa.strictModeEnabled"
        static let hasOfferedStrictMode = "noxa.hasOfferedStrictMode"
        static let hasOfferedScheduleSuggestion = "noxa.hasOfferedScheduleSuggestion"
        static let pendingScheduleSuggestion = "noxa.pendingScheduleSuggestion"
        static let websiteBlocklist = "noxa.websiteBlocklist"
        static let dailyLimits = "noxa.dailyLimits"
        static let restrictionSchedules = "noxa.restrictionSchedules"
        static let scheduleRules = "noxa.scheduleRules.v2"
        static let pomodoroCycle = "noxa.pomodoroCycle"
        static let pendingPomodoroCompletion = "noxa.pendingPomodoroCompletion"
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
        defaults.removeObject(forKey: Key.focusMonitorReceipt)
    }

    func loadFocusMonitorReceipt() throws -> FocusMonitorReceipt? {
        guard let data = defaults.data(forKey: Key.focusMonitorReceipt) else { return nil }
        return try JSONDecoder().decode(FocusMonitorReceipt.self, from: data)
    }

    func clearFocusMonitorReceipt() {
        defaults.removeObject(forKey: Key.focusMonitorReceipt)
    }

    var isSafariFilterEnabled: Bool {
        defaults.bool(forKey: Key.safariFilterEnabled)
    }

    func setSafariFilterEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.safariFilterEnabled)
    }

    var instagramSiteMode: InstagramSiteMode {
        if let raw = defaults.string(forKey: Key.instagramSiteMode),
           let mode = InstagramSiteMode(rawValue: raw) {
            return mode
        }
        return isSafariFilterEnabled ? .distractionFree : .off
    }

    func setInstagramSiteMode(_ mode: InstagramSiteMode) {
        defaults.set(mode.rawValue, forKey: Key.instagramSiteMode)
        // The existing Safari native handler uses this boolean; only the
        // selective mode may change Instagram pages.
        defaults.set(mode == .distractionFree, forKey: Key.safariFilterEnabled)
    }

    func clearInstagramSiteMode() {
        defaults.removeObject(forKey: Key.instagramSiteMode)
        defaults.set(false, forKey: Key.safariFilterEnabled)
    }

    var safariFilterAllowedUntil: Date? {
        defaults.object(forKey: Key.safariFilterAllowedUntil) as? Date
    }

    func setSafariFilterAllowedUntil(_ date: Date?) {
        if let date {
            defaults.set(date, forKey: Key.safariFilterAllowedUntil)
        } else {
            defaults.removeObject(forKey: Key.safariFilterAllowedUntil)
        }
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

    var isStrictModeEnabled: Bool {
        get { defaults.bool(forKey: Key.strictModeEnabled) }
        set { defaults.set(newValue, forKey: Key.strictModeEnabled) }
    }

    var hasOfferedStrictMode: Bool {
        get { defaults.bool(forKey: Key.hasOfferedStrictMode) }
        set { defaults.set(newValue, forKey: Key.hasOfferedStrictMode) }
    }

    var hasOfferedScheduleSuggestion: Bool {
        get { defaults.bool(forKey: Key.hasOfferedScheduleSuggestion) }
        set { defaults.set(newValue, forKey: Key.hasOfferedScheduleSuggestion) }
    }

    func loadPendingScheduleSuggestion() throws -> PendingScheduleSuggestion? {
        guard let data = defaults.data(forKey: Key.pendingScheduleSuggestion) else { return nil }
        return try JSONDecoder().decode(PendingScheduleSuggestion.self, from: data)
    }

    func savePendingScheduleSuggestion(_ suggestion: PendingScheduleSuggestion) throws {
        defaults.set(try JSONEncoder().encode(suggestion), forKey: Key.pendingScheduleSuggestion)
    }

    func clearPendingScheduleSuggestion() {
        defaults.removeObject(forKey: Key.pendingScheduleSuggestion)
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
        defaults.removeObject(forKey: Key.scheduleRules)
    }

    func clearLegacyRestrictionSchedules() {
        defaults.removeObject(forKey: Key.restrictionSchedules)
    }

    @MainActor func loadScheduleRules() throws -> [ScheduleRule] {
        if let data = defaults.data(forKey: Key.scheduleRules) {
            let archive = try JSONDecoder().decode(ScheduleRuleArchive.self, from: data)
            guard archive.version == 2 else { throw ScheduleRuleArchiveError.unsupportedVersion }
            return archive.rules
        }
        return try loadRestrictionSchedules().map(ScheduleRule.init(legacy:))
    }

    func saveScheduleRules(_ rules: [ScheduleRule]) throws {
        let archive = ScheduleRuleArchive(version: 2, rules: rules)
        defaults.set(try JSONEncoder().encode(archive), forKey: Key.scheduleRules)
    }

    func clearScheduleRules() {
        defaults.removeObject(forKey: Key.scheduleRules)
    }

    func loadPomodoroCycle() throws -> PomodoroCycleRecord? {
        guard let data = defaults.data(forKey: Key.pomodoroCycle) else { return nil }
        return try JSONDecoder().decode(PomodoroCycleRecord.self, from: data)
    }

    func savePomodoroCycle(_ cycle: PomodoroCycleRecord) throws {
        defaults.set(try JSONEncoder().encode(cycle), forKey: Key.pomodoroCycle)
    }

    func clearPomodoroCycle() {
        defaults.removeObject(forKey: Key.pomodoroCycle)
    }

    func hasActivePomodoroCycle() -> Bool {
        (try? loadPomodoroCycle()) != nil
    }

    func pomodoroRoundEnforcedAt(cycleID: UUID, round: Int) -> Date? {
        defaults.object(forKey: pomodoroRoundEnforcementKey(cycleID: cycleID, round: round)) as? Date
    }

    func markPomodoroRoundEnforced(cycleID: UUID, round: Int, at date: Date = Date()) {
        let key = pomodoroRoundEnforcementKey(cycleID: cycleID, round: round)
        if defaults.object(forKey: key) == nil {
            defaults.set(date, forKey: key)
        }
    }

    func clearPomodoroRoundEnforcement(cycleID: UUID) {
        for round in 1...PomodoroCyclePlan.roundCount {
            defaults.removeObject(forKey: pomodoroRoundEnforcementKey(cycleID: cycleID, round: round))
        }
    }

    private func pomodoroRoundEnforcementKey(cycleID: UUID, round: Int) -> String {
        "noxa.pomodoro.enforced.\(cycleID.uuidString.lowercased()).\(round)"
    }

    var pendingPomodoroCompletionID: UUID? {
        get {
            guard let value = defaults.string(forKey: Key.pendingPomodoroCompletion) else { return nil }
            return UUID(uuidString: value)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Key.pendingPomodoroCompletion)
            } else {
                defaults.removeObject(forKey: Key.pendingPomodoroCompletion)
            }
        }
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
