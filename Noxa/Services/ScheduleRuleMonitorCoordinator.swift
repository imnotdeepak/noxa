import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum ScheduleRuleActivityNames {
    static let wakePrefix = "noxa.schedule.v2.wake."
    static let shieldPrefix = "noxa.schedule.v2.shield."

    static func wake(ruleID: UUID, minute: Int) -> DeviceActivityName {
        DeviceActivityName("\(wakePrefix)\(minute).\(ruleID.uuidString.lowercased())")
    }

    static func shield(ruleID: UUID) -> ManagedSettingsStore.Name {
        ManagedSettingsStore.Name("\(shieldPrefix)\(ruleID.uuidString.lowercased())")
    }

    static func wakes(for rule: ScheduleRule) -> [DeviceActivityName] {
        ScheduleRuleEvaluator.dailyWakeMinutes(for: rule)
            .map { wake(ruleID: rule.id, minute: $0) }
    }
}

/// Owns only the v2 schedule's store. Another active rule keeps its own store.
@MainActor
final class ScheduleRuleMonitorCoordinator {
    private let center = DeviceActivityCenter()

    func start(_ rule: ScheduleRule) throws {
        let names = ScheduleRuleActivityNames.wakes(for: rule)
        do {
            for minute in ScheduleRuleEvaluator.dailyWakeMinutes(for: rule) {
                let endMinute = (minute + 15) % 1_440
                let schedule = DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: minute / 60, minute: minute % 60),
                    intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60),
                    repeats: true
                )
                try center.startMonitoring(
                    ScheduleRuleActivityNames.wake(ruleID: rule.id, minute: minute),
                    during: schedule
                )
            }
        } catch {
            center.stopMonitoring(names)
            throw error
        }
        applyCurrentShield(for: rule)
    }

    func applyCurrentShield(for rule: ScheduleRule, now: Date = Date()) {
        let settings = ManagedSettingsStore(named: ScheduleRuleActivityNames.shield(ruleID: rule.id))
        guard ScheduleRuleEvaluator.isBlocking(rule, at: now, calendar: .autoupdatingCurrent) else {
            settings.clearAllSettings()
            return
        }
        settings.shield.applications = rule.selection.applicationTokens.isEmpty
            ? nil : rule.selection.applicationTokens
        settings.shield.applicationCategories = rule.selection.categoryTokens.isEmpty
            ? nil : .specific(rule.selection.categoryTokens)
        settings.shield.webDomains = rule.selection.webDomainTokens.isEmpty
            ? nil : rule.selection.webDomainTokens
        settings.webContent.blockedByFilter = rule.websiteDomains.isEmpty
            ? nil : .specific(Set(rule.websiteDomains.map(WebDomain.init(domain:))))
    }

    func stop(_ rule: ScheduleRule) {
        center.stopMonitoring(ScheduleRuleActivityNames.wakes(for: rule))
        ManagedSettingsStore(named: ScheduleRuleActivityNames.shield(ruleID: rule.id))
            .clearAllSettings()
    }
}
