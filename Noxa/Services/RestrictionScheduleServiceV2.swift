import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

/// Owns the versioned, local-time schedule rules and their independent stores.
@MainActor
final class RestrictionScheduleService: ObservableObject {
    static let maximumConfigurations = 8

    @Published private(set) var configurations: [ScheduleRule]
    @Published private(set) var activeAccountID: UUID? = nil
    @Published private(set) var commitmentEvents: [ScheduleCommitmentEvent]
    @Published private(set) var errorMessage: String?

    private let store: AppGroupStore
    private let center = DeviceActivityCenter()
    private let coordinator = ScheduleRuleMonitorCoordinator()
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "schedules-v2")

    init(store: AppGroupStore? = nil) {
        self.store = store ?? AppGroupStore.shared
        do {
            configurations = try self.store.loadScheduleRules()
        } catch {
            configurations = []
            errorMessage = "Could not load schedules: \(error.localizedDescription)"
        }
        commitmentEvents = (try? self.store.loadScheduleCommitmentEvents()) ?? []
        if commitmentEvents.isEmpty && !configurations.isEmpty {
            // Older schedules begin tracking now; past windows are not inferred.
            commitmentEvents = configurations.map { ScheduleCommitmentEvent(rule: $0) }
            try? self.store.saveScheduleCommitmentEvents(commitmentEvents)
        }
    }

    var enabledCount: Int { configurations.filter(\.isEnabled).count }

    var visibleConfigurations: [ScheduleRule] {
        guard let activeAccountID else { return configurations }
        return configurations.filter { $0.ownerUserID == activeAccountID }
    }

    func bindAccount(_ userID: UUID, claimingUnownedRulesFor legacyOwner: UUID?) {
        if let legacyOwner, configurations.contains(where: { $0.ownerUserID == nil }) {
            configurations = configurations.map { rule in
                var rule = rule
                if rule.ownerUserID == nil { rule.ownerUserID = legacyOwner }
                return rule
            }
            do {
                try store.saveScheduleRules(configurations)
            } catch {
                errorMessage = "Could not assign saved schedules to their account: \(error.localizedDescription)"
            }
        }
        activeAccountID = userID
    }

    var nextPendingRelaxationDate: Date? {
        configurations.compactMap(\.pendingLegacyRelaxation?.effectiveAt).min()
    }

    func clearError() { errorMessage = nil }

    func add(
        name: String,
        mode: ScheduleRule.Mode,
        selection: FamilyActivitySelection,
        websiteDomains: [String] = [],
        weekdays: Set<Int>,
        start: Date,
        end: Date,
        notifyAtStart: Bool = false,
        notifyAtEnd: Bool = false,
        lockWhileActive: Bool = false
    ) {
        errorMessage = nil
        guard visibleConfigurations.count < Self.maximumConfigurations else {
            errorMessage = "You can create up to \(Self.maximumConfigurations) schedules."
            return
        }
        let calendar = Calendar.autoupdatingCurrent
        let rule = ScheduleRule(
            ownerUserID: activeAccountID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            selection: selection,
            websiteDomains: websiteDomains,
            weekdays: weekdays,
            startMinutes: Self.minutesSinceMidnight(start, calendar: calendar),
            endMinutes: Self.minutesSinceMidnight(end, calendar: calendar),
            notifyAtStart: notifyAtStart,
            notifyAtEnd: notifyAtEnd,
            lockWhileActive: lockWhileActive
        )
        guard let normalized = validated(rule) else { return }
        configurations.append(normalized)
        persistAndReschedule(recording: [ScheduleCommitmentEvent(rule: normalized)])
        if errorMessage == nil {
            let length = (normalized.endMinutes - normalized.startMinutes + 1_440) % 1_440
            AnalyticsService.shared.capture(.scheduleCreated(
                blockMinutes: length == 0 ? 1_440 : length,
                dayCount: normalized.weekdays.count
            ))
        }
    }

    func update(_ configuration: ScheduleRule) {
        errorMessage = nil
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }),
              var normalized = validated(configuration) else { return }
        let previous = configurations[index]
        guard activeAccountID == nil || previous.ownerUserID == activeAccountID else { return }
        normalized.ownerUserID = previous.ownerUserID
        guard allowsChange(previous, decision: ScheduleCommitmentPolicy.update(
            from: previous, to: normalized, at: Date(), calendar: .autoupdatingCurrent
        )) else { return }
        configurations[index] = normalized
        let affectsCommitment = previous.mode != normalized.mode
            || previous.selection != normalized.selection
            || previous.websiteDomains != normalized.websiteDomains
            || previous.weekdays != normalized.weekdays
            || previous.startMinutes != normalized.startMinutes
            || previous.endMinutes != normalized.endMinutes
            || previous.isEnabled != normalized.isEnabled
        persistAndReschedule(recording: affectsCommitment
            ? [ScheduleCommitmentEvent(rule: normalized)] : [])
        if errorMessage == nil {
            AnalyticsService.shared.capture(.scheduleEdited())
        }
    }

    func rename(_ configuration: ScheduleRule, to name: String) {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Give this schedule a name."
            return
        }
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }),
              canEdit(configurations[index]) else { return }
        configurations[index].name = String(trimmed.prefix(50))
        do {
            try store.saveScheduleRules(configurations)
        } catch {
            errorMessage = "Could not rename the schedule: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool, for configuration: ScheduleRule) {
        errorMessage = nil
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }),
              canEdit(configurations[index]) else { return }
        if !enabled {
            guard allowsChange(configurations[index], decision: ScheduleCommitmentPolicy.removal(
                of: configurations[index], at: Date(), calendar: .autoupdatingCurrent
            )) else { return }
        }
        let wasEnabled = configurations[index].isEnabled
        let lockState = AnalyticsEvent.lockStateName(weeklyState(configurations[index]))
        configurations[index].isEnabled = enabled
        if enabled && !wasEnabled {
            // Turning a schedule back on starts a new locked week.
            configurations[index].lockAnchor = Date()
        }
        configurations[index].pendingLegacyRelaxation = nil
        let changed = ScheduleCommitmentEvent(rule: configurations[index])
        if !enabled {
            recordImmediateLegacyStop(for: configuration.id, remove: false)
            coordinator.stop(configuration)
            stopLegacyActivities(for: configuration.id)
        }
        persistAndReschedule(recording: wasEnabled == enabled ? [] : [changed])
        if errorMessage == nil, wasEnabled != enabled {
            AnalyticsService.shared.capture(.scheduleToggled(on: enabled, lockState: lockState))
        }
    }

    func remove(_ configuration: ScheduleRule) {
        errorMessage = nil
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }),
              canEdit(configurations[index]),
              allowsChange(configurations[index], decision: ScheduleCommitmentPolicy.removal(
                  of: configurations[index], at: Date(), calendar: .autoupdatingCurrent
              )) else { return }
        let lockState = AnalyticsEvent.lockStateName(weeklyState(configurations[index]))
        recordImmediateLegacyStop(for: configuration.id, remove: true)
        coordinator.stop(configuration)
        stopLegacyActivities(for: configuration.id)
        configurations.remove(at: index)
        persistAndReschedule(recording: [ScheduleCommitmentEvent(rule: configuration, isRemoved: true)])
        if errorMessage == nil {
            AnalyticsService.shared.capture(.scheduleRemoved(lockState: lockState))
        }
    }

    func cancelPendingRelaxation(for configuration: ScheduleRule) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }),
              canEdit(configurations[index]) else { return }
        configurations[index].pendingLegacyRelaxation = nil
        persistAndReschedule()
    }

    func requestDisableAll() {
        guard configurations.contains(where: \.isEnabled) else { return }
        if let activeAccountID,
           configurations.contains(where: { $0.isEnabled && $0.ownerUserID != activeAccountID }) {
            errorMessage = "Another account's schedules are still active on this iPhone."
            return
        }
        var changes: [ScheduleCommitmentEvent] = []
        var lockedMessage: String?
        for index in configurations.indices where configurations[index].isEnabled {
            // Locked windows end on their own; every other schedule stops now.
            if let end = ScheduleCommitmentPolicy.commitmentLockedUntil(
                configurations[index], at: Date(), calendar: .autoupdatingCurrent
            ) {
                lockedMessage = ScheduleCommitmentPolicy.lockedMessage(
                    name: configurations[index].name, until: end
                )
                continue
            }
            recordImmediateLegacyStop(for: configurations[index].id, remove: false)
            coordinator.stop(configurations[index])
            stopLegacyActivities(for: configurations[index].id)
            configurations[index].isEnabled = false
            configurations[index].pendingLegacyRelaxation = nil
            changes.append(ScheduleCommitmentEvent(rule: configurations[index]))
        }
        persistAndReschedule(recording: changes)
        if let lockedMessage { errorMessage = lockedMessage }
    }

    private func canEdit(_ rule: ScheduleRule) -> Bool {
        guard let activeAccountID, rule.ownerUserID != activeAccountID else { return true }
        errorMessage = "This schedule belongs to another Noxa account."
        return false
    }

    /// The release time of a rule's active locked window, if any.
    func lockedUntil(_ configuration: ScheduleRule, at date: Date = Date()) -> Date? {
        let saved = configurations.first { $0.id == configuration.id } ?? configuration
        return ScheduleCommitmentPolicy.lockedUntil(saved, at: date, calendar: .autoupdatingCurrent)
    }

    /// When the rule can next be changed: its active window or locked week.
    func commitmentLockedUntil(_ configuration: ScheduleRule, at date: Date = Date()) -> Date? {
        let saved = configurations.first { $0.id == configuration.id } ?? configuration
        return ScheduleCommitmentPolicy.commitmentLockedUntil(saved, at: date, calendar: .autoupdatingCurrent)
    }

    func weeklyState(_ configuration: ScheduleRule, at date: Date = Date()) -> WeeklyCommitment.State {
        let saved = configurations.first { $0.id == configuration.id } ?? configuration
        return ScheduleCommitmentPolicy.weeklyState(saved, at: date)
    }

    private func allowsChange(_ rule: ScheduleRule, decision: ScheduleCommitmentPolicy.Decision) -> Bool {
        guard case .locked(let end) = decision else { return true }
        errorMessage = ScheduleCommitmentPolicy.lockedMessage(name: rule.name, until: end)
        return false
    }

    func reconcile() {
        do {
            configurations = try store.loadScheduleRules()
            rescheduleAll()
        } catch {
            errorMessage = "Could not load schedules: \(error.localizedDescription)"
        }
    }

    func clearConfigurations() {
        configurations.forEach { coordinator.stop($0) }
        clearOrphanShields(keeping: [])
        configurations.forEach { stopLegacyActivities(for: $0.id) }
        stopAllV2Activities()
        clearLegacyActivities(expected: [])
        configurations = []
        commitmentEvents = []
        store.clearRestrictionSchedules()
        errorMessage = nil
    }

    func removeConfigurations(ownedBy userID: UUID) {
        let removed = configurations.filter { $0.ownerUserID == userID }
        guard !removed.isEmpty else { return }
        removed.forEach { coordinator.stop($0) }
        removed.forEach { stopLegacyActivities(for: $0.id) }
        let removedIDs = Set(removed.map(\.id))
        configurations.removeAll { removedIDs.contains($0.id) }
        commitmentEvents.removeAll { removedIDs.contains($0.ruleID) }
        do {
            try store.saveScheduleRules(configurations)
            try store.saveScheduleCommitmentEvents(commitmentEvents)
            rescheduleAll()
        } catch {
            errorMessage = "Could not remove this account's schedules: \(error.localizedDescription)"
        }
    }

    private func persistAndReschedule(recording changes: [ScheduleCommitmentEvent] = []) {
        do {
            try store.saveScheduleRules(configurations)
            if !changes.isEmpty { recordCommitmentChanges(changes) }
            rescheduleAll()
        } catch {
            errorMessage = "Could not save schedules: \(error.localizedDescription)"
        }
    }

    private func recordCommitmentChanges(_ changes: [ScheduleCommitmentEvent]) {
        commitmentEvents.append(contentsOf: changes)
        let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let older = Dictionary(grouping: commitmentEvents.filter { $0.changedAt < cutoff }, by: \.ruleID)
            .compactMap { $0.value.max { $0.changedAt < $1.changedAt } }
        commitmentEvents = (older + commitmentEvents.filter { $0.changedAt >= cutoff })
            .sorted { $0.changedAt < $1.changedAt }
        try? store.saveScheduleCommitmentEvents(commitmentEvents)
    }

    private func rescheduleAll() {
        applyMaturedLegacyChanges()
        do {
            // Save before registering activities so the extension can read
            // the same rules as the main app when a callback arrives.
            try store.saveScheduleRules(configurations)
        } catch {
            errorMessage = "Could not save schedules: \(error.localizedDescription)"
            return
        }

        clearOrphanShields(keeping: Set(configurations.map(\.id)))

        var expected: Set<DeviceActivityName> = []
        var failed = false
        for rule in configurations {
            guard rule.isEnabled else {
                coordinator.stop(rule)
                continue
            }
            coordinator.applyCurrentShield(for: rule)
            do {
                try coordinator.start(rule)
                expected.formUnion(ScheduleRuleActivityNames.wakes(for: rule))
                if let pending = rule.pendingLegacyRelaxation, pending.effectiveAt > Date() {
                    expected.insert(ScheduleRuleActivityNames.relaxation(ruleID: rule.id))
                }
            } catch {
                failed = true
                errorMessage = "Could not start \(rule.name): \(error.localizedDescription)"
                logger.error("Schedule registration failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Keep old stores as a fallback if an upgraded monitor did not start.
        guard !failed else { return }
        clearLegacyActivities(expected: expected)
        configurations.forEach { stopLegacyActivities(for: $0.id) }
        store.clearLegacyRestrictionSchedules()
        errorMessage = nil
    }

    private func clearOrphanShields(keeping currentIDs: Set<UUID>) {
        // A wake can survive a crash before its owner ID is persisted. Recover
        // that ID from the registered activity so its separate shield store
        // can also be cleared when the saved rule no longer exists.
        let monitoredIDs = Set(center.activities.compactMap(ScheduleRuleActivityNames.ownerID))
        let staleIDs = store.scheduleShieldOwners.union(monitoredIDs).subtracting(currentIDs)
        for id in staleIDs {
            ManagedSettingsStore(named: ScheduleRuleActivityNames.shield(ruleID: id))
                .clearAllSettings()
            let suffix = id.uuidString.lowercased()
            center.stopMonitoringIfAny(center.activities.filter {
                ($0.rawValue.hasPrefix(ScheduleRuleActivityNames.wakePrefix)
                    && $0.rawValue.hasSuffix(suffix))
                    || $0.rawValue == ScheduleRuleActivityNames.relaxation(ruleID: id).rawValue
            })
        }
        store.scheduleShieldOwners = currentIDs
    }

    private func applyMaturedLegacyChanges(now: Date = Date()) {
        var changed = false
        configurations = configurations.compactMap { rule in
            guard let pending = rule.pendingLegacyRelaxation,
                  pending.effectiveAt <= now else { return rule }
            changed = true
            recordImmediateLegacyStop(for: rule.id, remove: pending.action == .remove)
            coordinator.stop(rule)
            stopLegacyActivities(for: rule.id)
            switch pending.action {
            case .remove:
                return nil
            case .disable:
                var disabled = rule
                disabled.isEnabled = false
                disabled.pendingLegacyRelaxation = nil
                return disabled
            }
        }
        if changed {
            logger.info("Applied matured legacy schedule changes")
        }
    }

    private func stopAllV2Activities() {
        let names = center.activities.filter {
            $0.rawValue.hasPrefix(ScheduleRuleActivityNames.wakePrefix)
                || $0.rawValue.hasPrefix(ScheduleRuleActivityNames.relaxationPrefix)
        }
        center.stopMonitoringIfAny(names)
    }

    private func clearLegacyActivities(expected: Set<DeviceActivityName>) {
        let stale = center.activities.filter {
            $0.rawValue.hasPrefix("noxa.schedule.") && !expected.contains($0)
        }
        center.stopMonitoringIfAny(stale)
        for name in stale {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue)).clearAllSettings()
        }
    }

    private func stopLegacyActivities(for id: UUID) {
        let names = [
            NoxaDeviceActivityConfiguration.scheduleActivityName(for: id, segment: "before"),
            NoxaDeviceActivityConfiguration.scheduleActivityName(for: id, segment: "after"),
            NoxaDeviceActivityConfiguration.scheduleRelaxationActivityName(for: id)
        ]
        center.stopMonitoring(names)
        for name in names {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue)).clearAllSettings()
        }
    }

    private func recordImmediateLegacyStop(for id: UUID, remove: Bool) {
        guard var legacy = try? store.loadRestrictionSchedules(),
              let index = legacy.firstIndex(where: { $0.id == id }) else { return }
        if remove {
            legacy.remove(at: index)
        } else {
            legacy[index].isEnabled = false
            legacy[index].pendingRelaxation = nil
        }
        try? store.saveRestrictionSchedules(legacy)
    }

    private func validated(_ rule: ScheduleRule) -> ScheduleRule? {
        let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give this schedule a name."
            return nil
        }
        guard !rule.weekdays.isEmpty,
              rule.weekdays.isSubset(of: Set(1...7)) else {
            errorMessage = "Choose at least one day for this schedule."
            return nil
        }
        let duration = (rule.endMinutes - rule.startMinutes + 1_440) % 1_440
        guard (15...1_425).contains(duration) else {
            errorMessage = "Choose a window from 15 minutes to 23 hours 45 minutes."
            return nil
        }
        let normalizedDomains = rule.websiteDomains.compactMap(WebsiteBlocklistService.normalize)
        guard normalizedDomains.count == rule.websiteDomains.count,
              normalizedDomains.count <= WebsiteBlocklistService.maximumDomains else {
            errorMessage = "Check the website domains in this schedule."
            return nil
        }
        guard !rule.selection.applicationTokens.isEmpty
                || !rule.selection.categoryTokens.isEmpty
                || !rule.selection.webDomainTokens.isEmpty
                || !normalizedDomains.isEmpty else {
            errorMessage = "Select an app, category, or website for this schedule."
            return nil
        }
        var normalized = rule
        normalized.name = String(name.prefix(50))
        // Every Blocked hours schedule locks while active. Allowed hours can
        // block open-endedly, so they never lock.
        normalized.lockWhileActive = ScheduleCommitmentPolicy.canLock(rule.mode)
        normalized.websiteDomains = Array(Set(normalizedDomains)).sorted()
        return normalized
    }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
