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
    }

    var enabledCount: Int { configurations.filter(\.isEnabled).count }

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
        end: Date
    ) {
        errorMessage = nil
        guard configurations.count < Self.maximumConfigurations else {
            errorMessage = "You can create up to \(Self.maximumConfigurations) schedules."
            return
        }
        let calendar = Calendar.autoupdatingCurrent
        let rule = ScheduleRule(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            selection: selection,
            websiteDomains: websiteDomains,
            weekdays: weekdays,
            startMinutes: Self.minutesSinceMidnight(start, calendar: calendar),
            endMinutes: Self.minutesSinceMidnight(end, calendar: calendar)
        )
        guard let normalized = validated(rule) else { return }
        configurations.append(normalized)
        persistAndReschedule()
    }

    func update(_ configuration: ScheduleRule) {
        errorMessage = nil
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }),
              let normalized = validated(configuration) else { return }
        configurations[index] = normalized
        persistAndReschedule()
    }

    func rename(_ configuration: ScheduleRule, to name: String) {
        errorMessage = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Give this schedule a name."
            return
        }
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].name = String(trimmed.prefix(50))
        do {
            try store.saveScheduleRules(configurations)
        } catch {
            errorMessage = "Could not rename the schedule: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ enabled: Bool, for configuration: ScheduleRule) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].isEnabled = enabled
        configurations[index].pendingLegacyRelaxation = nil
        if !enabled {
            recordImmediateLegacyStop(for: configuration.id, remove: false)
            coordinator.stop(configuration)
            stopLegacyActivities(for: configuration.id)
        }
        persistAndReschedule()
    }

    func remove(_ configuration: ScheduleRule) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        recordImmediateLegacyStop(for: configuration.id, remove: true)
        coordinator.stop(configuration)
        stopLegacyActivities(for: configuration.id)
        configurations.remove(at: index)
        persistAndReschedule()
    }

    func cancelPendingRelaxation(for configuration: ScheduleRule) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].pendingLegacyRelaxation = nil
        persistAndReschedule()
    }

    func requestDisableAll() {
        guard configurations.contains(where: \.isEnabled) else { return }
        for index in configurations.indices where configurations[index].isEnabled {
            recordImmediateLegacyStop(for: configurations[index].id, remove: false)
            coordinator.stop(configurations[index])
            stopLegacyActivities(for: configurations[index].id)
            configurations[index].isEnabled = false
            configurations[index].pendingLegacyRelaxation = nil
        }
        persistAndReschedule()
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
        configurations.forEach { stopLegacyActivities(for: $0.id) }
        stopAllV2Activities()
        clearLegacyActivities(expected: [])
        configurations = []
        store.clearRestrictionSchedules()
        errorMessage = nil
    }

    private func persistAndReschedule() {
        do {
            try store.saveScheduleRules(configurations)
            rescheduleAll()
        } catch {
            errorMessage = "Could not save schedules: \(error.localizedDescription)"
        }
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
        center.stopMonitoring(names)
    }

    private func clearLegacyActivities(expected: Set<DeviceActivityName>) {
        let stale = center.activities.filter {
            $0.rawValue.hasPrefix("noxa.schedule.") && !expected.contains($0)
        }
        center.stopMonitoring(stale)
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
        normalized.websiteDomains = Array(Set(normalizedDomains)).sorted()
        return normalized
    }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
