import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum ScheduleRuleActivityNames {
    static let wakePrefix = "noxa.schedule.v2.wake."
    static let relaxationPrefix = "noxa.schedule.v2.relax."
    static let shieldPrefix = "noxa.schedule.v2.shield."

    static func wake(ruleID: UUID, minute: Int) -> DeviceActivityName {
        DeviceActivityName("\(wakePrefix)\(minute).\(ruleID.uuidString.lowercased())")
    }

    static func shield(ruleID: UUID) -> ManagedSettingsStore.Name {
        ManagedSettingsStore.Name("\(shieldPrefix)\(ruleID.uuidString.lowercased())")
    }

    static func relaxation(ruleID: UUID) -> DeviceActivityName {
        DeviceActivityName("\(relaxationPrefix)\(ruleID.uuidString.lowercased())")
    }

    static func ownerID(for activity: DeviceActivityName) -> UUID? {
        let name = activity.rawValue
        guard name.hasPrefix(wakePrefix) || name.hasPrefix(relaxationPrefix),
              let suffix = name.split(separator: ".").last else { return nil }
        return UUID(uuidString: String(suffix))
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
        let existingNames = Set(center.activities)
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
            if let pending = rule.pendingLegacyRelaxation,
               pending.effectiveAt > Date() {
                let calendar = Calendar.autoupdatingCurrent
                let end = pending.effectiveAt.addingTimeInterval(15 * 60)
                try center.startMonitoring(
                    ScheduleRuleActivityNames.relaxation(ruleID: rule.id),
                    during: DeviceActivitySchedule(
                        intervalStart: calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute, .second],
                            from: pending.effectiveAt
                        ),
                        intervalEnd: calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute, .second],
                            from: end
                        ),
                        repeats: false
                    )
                )
            }
        } catch {
            center.stopMonitoring(
                (names + [ScheduleRuleActivityNames.relaxation(ruleID: rule.id)])
                    .filter { !existingNames.contains($0) }
            )
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
        RestrictionStoreWriter.apply(
            selection: rule.selection,
            websiteDomains: rule.websiteDomains,
            to: settings
        )
    }

    func stop(_ rule: ScheduleRule) {
        center.stopMonitoring(
            ScheduleRuleActivityNames.wakes(for: rule)
                + [ScheduleRuleActivityNames.relaxation(ruleID: rule.id)]
        )
        ManagedSettingsStore(named: ScheduleRuleActivityNames.shield(ruleID: rule.id))
            .clearAllSettings()
    }
}
