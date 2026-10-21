import Foundation

/// A stable reference to a rule that can require a Screen Time restriction.
struct RestrictionRuleID: nonisolated Hashable, nonisolated Equatable {
    enum Source: nonisolated Hashable, nonisolated Equatable {
        case focusSession
        case schedule
        case dailyLimit
        case pomodoro
        case manualShield
        case websiteBlocklist
        case instagramFullBlock
    }

    let source: Source
    let value: UUID
}

/// The caller resolves time windows and session state before evaluation.
/// An allowed window only means this rule does not request a block; it cannot
/// grant access over another active rule.
enum RestrictionRuleEffect {
    case block
    case allow
    case inactive
}

struct RestrictionRule<Target: Hashable> {
    let id: RestrictionRuleID
    let effect: RestrictionRuleEffect
    let targets: Set<Target>
}

struct EffectiveRestrictions<Target: Hashable> {
    fileprivate var ownersByTarget: [Target: Set<RestrictionRuleID>] = [:]

    var blockedTargets: Set<Target> {
        Set(ownersByTarget.keys)
    }

    var activeRuleIDs: Set<RestrictionRuleID> {
        ownersByTarget.values.reduce(into: Set<RestrictionRuleID>()) { result, owners in
            result.formUnion(owners)
        }
    }

    func owners(for target: Target) -> Set<RestrictionRuleID> {
        ownersByTarget[target] ?? []
    }
}

/// Combines normalized rules without touching ManagedSettingsStore. A target
/// remains blocked while at least one active rule requires it.
enum RestrictionRuleEvaluator {
    static func evaluate<Target: Hashable>(
        _ rules: [RestrictionRule<Target>]
    ) -> EffectiveRestrictions<Target> {
        var result = EffectiveRestrictions<Target>()
        for rule in rules where rule.effect == .block {
            for target in rule.targets {
                result.ownersByTarget[target, default: []].insert(rule.id)
            }
        }
        return result
    }
}
