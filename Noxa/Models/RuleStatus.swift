import Foundation

/// One vocabulary for what a schedule or daily limit is doing right now.
/// "On" in a row's pill is configuration; these states say whether the rule
/// is actually in effect, so the two are never conflated.
enum RuleStatus: Equatable {
    /// Screen Time access is missing, so nothing can be enforced.
    case needsPermission
    /// Turned off by the user.
    case off
    /// On, but the daily-limit monitor is stopped.
    case paused
    /// On and waiting for its next window.
    case scheduled(next: Date)
    /// Inside its window (schedules) or past its allowance (limits).
    case blockingNow
    /// Blocking now, and locked against changes until the given time.
    case lockedUntil(Date)
    /// A daily limit that is on and counting today's use.
    case counting

    static func schedule(
        _ rule: ScheduleRule,
        isAuthorized: Bool,
        lockedUntil: Date?,
        at date: Date,
        calendar: Calendar
    ) -> RuleStatus {
        guard isAuthorized else { return .needsPermission }
        guard rule.isEnabled else { return .off }
        if let lockedUntil { return .lockedUntil(lockedUntil) }
        if ScheduleRuleEvaluator.isBlocking(rule, at: date, calendar: calendar) { return .blockingNow }
        if let next = ScheduleCommitmentPolicy.upcomingWindow(for: rule, after: date, calendar: calendar)?.start {
            return .scheduled(next: next)
        }
        return .off
    }

    static func dailyLimit(
        isEnabled: Bool,
        isAuthorized: Bool,
        isMonitoring: Bool,
        hasReachedLimit: Bool
    ) -> RuleStatus {
        guard isAuthorized else { return .needsPermission }
        guard isEnabled else { return .off }
        guard isMonitoring else { return .paused }
        return hasReachedLimit ? .blockingNow : .counting
    }
}
