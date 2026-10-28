import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// A saved selection item. These are opaque Screen Time tokens, never app or
/// website identifiers sent outside the device.
enum RestrictionTarget: nonisolated Hashable {
    case application(ApplicationToken)
    case category(ActivityCategoryToken)
    case website(WebDomainToken)
    case domain(String)
}

/// Computes requested owners across rule types. Managed Settings stores still
/// enforce independently; this plan does not assert that iOS showed a shield.
enum RestrictionOwnershipPlan {
    struct Focus {
        let id: UUID
        let plannedEndAt: Date
        let isPomodoro: Bool
        let restrictions: FocusSessionRestrictionConfiguration
    }

    struct Inputs {
        var focus: Focus?
        var schedules: [ScheduleRule] = []
        var dailyLimits: [DailyLimitConfiguration] = []
        var reachedDailyEventNames: Set<String> = []
        var isDailyMonitoring = false
        var manualShield: ManualShieldConfiguration?
        var blockedWebsiteDomains: [String] = []
        var instagramAppBlock: FamilyActivitySelection?
    }

    static func evaluate(
        _ inputs: Inputs,
        at now: Date,
        calendar: Calendar
    ) -> EffectiveRestrictions<RestrictionTarget> {
        var rules: [RestrictionRule<RestrictionTarget>] = []

        if let focus = inputs.focus, focus.plannedEndAt > now {
            rules.append(RestrictionRule(
                id: RestrictionRuleID(
                    source: focus.isPomodoro ? .pomodoro : .focusSession,
                    value: focus.id
                ),
                effect: .block,
                targets: targets(
                    selection: focus.restrictions.selection,
                    domains: focus.restrictions.websiteDomains
                )
            ))
        }

        for schedule in inputs.schedules {
            rules.append(RestrictionRule(
                id: RestrictionRuleID(source: .schedule, value: schedule.id),
                effect: ScheduleRuleEvaluator.isBlocking(schedule, at: now, calendar: calendar)
                    ? .block : .allow,
                targets: targets(selection: schedule.selection, domains: schedule.websiteDomains)
            ))
        }

        if inputs.isDailyMonitoring {
            for limit in inputs.dailyLimits where limit.isEnabled {
                let eventName = NoxaDeviceActivityConfiguration.dailyLimitEventName(for: limit.id).rawValue
                rules.append(RestrictionRule(
                    id: RestrictionRuleID(source: .dailyLimit, value: limit.id),
                    effect: inputs.reachedDailyEventNames.contains(eventName) ? .block : .inactive,
                    targets: targets(selection: limit.selection, domains: [])
                ))
            }
        }

        if let manual = inputs.manualShield {
            rules.append(RestrictionRule(
                id: RestrictionRuleID(source: .manualShield, value: fixedOwnerID),
                effect: .block,
                targets: targets(selection: manual.selection, domains: manual.websiteDomains)
            ))
        }

        if !inputs.blockedWebsiteDomains.isEmpty {
            rules.append(RestrictionRule(
                id: RestrictionRuleID(source: .websiteBlocklist, value: fixedOwnerID),
                effect: .block,
                targets: targets(selection: FamilyActivitySelection(), domains: inputs.blockedWebsiteDomains)
            ))
        }

        if let instagramApp = inputs.instagramAppBlock {
            rules.append(RestrictionRule(
                id: RestrictionRuleID(source: .instagramAppBlock, value: fixedOwnerID),
                effect: .block,
                targets: targets(selection: instagramApp, domains: [])
            ))
        }

        return RestrictionRuleEvaluator.evaluate(rules)
    }

    static func targets(
        selection: FamilyActivitySelection,
        domains: [String]
    ) -> Set<RestrictionTarget> {
        var result = Set(selection.applicationTokens.map(RestrictionTarget.application))
        result.formUnion(selection.categoryTokens.map(RestrictionTarget.category))
        result.formUnion(selection.webDomainTokens.map(RestrictionTarget.website))
        result.formUnion(domains.compactMap { domain -> RestrictionTarget? in
            let normalized = domain.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return normalized.isEmpty ? nil : .domain(normalized)
        })
        return result
    }

    private static let fixedOwnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
