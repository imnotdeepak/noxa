import Foundation

/// Decides whether a schedule can be weakened right now. A locked Blocked
/// hours rule protects only its current window, measured from the saved rule
/// so a pending edit can never move its own release time.
enum ScheduleCommitmentPolicy {
    enum Decision: Equatable {
        case allowed
        case locked(until: Date)
    }

    /// The longest window a schedule can have. A computed release beyond this
    /// is treated as unknown so the rule can never lock indefinitely.
    private static let maximumLock: TimeInterval = 24 * 60 * 60

    static func canLock(_ mode: ScheduleRule.Mode) -> Bool {
        mode == .blockedHours
    }

    /// When the saved rule's active locked window ends, or nil when it is not
    /// locked. Uses only local time, so a lost Device Activity callback cannot
    /// keep the lock on.
    static func lockedUntil(_ rule: ScheduleRule, at date: Date, calendar: Calendar) -> Date? {
        guard rule.lockWhileActive,
              canLock(rule.mode),
              rule.isEnabled,
              ScheduleRuleEvaluator.isBlocking(rule, at: date, calendar: calendar),
              let end = ScheduleRuleEvaluator.nextChange(for: rule, after: date, calendar: calendar),
              end.timeIntervalSince(date) <= maximumLock else { return nil }
        return end
    }

    /// The current or next blocking window, shown before the lock is enabled.
    static func upcomingWindow(
        for rule: ScheduleRule,
        after date: Date,
        calendar: Calendar
    ) -> (start: Date?, end: Date)? {
        if ScheduleRuleEvaluator.isBlocking(rule, at: date, calendar: calendar) {
            return ScheduleRuleEvaluator.nextChange(for: rule, after: date, calendar: calendar)
                .map { (nil, $0) }
        }
        guard let start = ScheduleRuleEvaluator.nextChange(for: rule, after: date, calendar: calendar),
              let end = ScheduleRuleEvaluator.nextChange(for: rule, after: start, calendar: calendar)
        else { return nil }
        return (start, end)
    }

    static func update(
        from saved: ScheduleRule,
        to proposed: ScheduleRule,
        at date: Date,
        calendar: Calendar
    ) -> Decision {
        guard let end = lockedUntil(saved, at: date, calendar: calendar) else { return .allowed }
        // Names and reminders never change what is blocked.
        var comparable = proposed
        comparable.name = saved.name
        comparable.notifyAtStart = saved.notifyAtStart
        comparable.notifyAtEnd = saved.notifyAtEnd
        return comparable == saved ? .allowed : .locked(until: end)
    }

    /// Disabling and removing are both weakening while a lock is active.
    static func removal(of saved: ScheduleRule, at date: Date, calendar: Calendar) -> Decision {
        lockedUntil(saved, at: date, calendar: calendar).map { .locked(until: $0) } ?? .allowed
    }

    static func lockedMessage(name: String, until end: Date) -> String {
        "\(name) is locked until \(end.formatted(date: .omitted, time: .shortened)). You can change it after this window ends."
    }
}
