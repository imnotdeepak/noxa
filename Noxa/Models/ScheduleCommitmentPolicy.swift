import Foundation

/// Decides whether a schedule can be weakened right now. Every Blocked hours
/// rule locks while active, protecting only its current window, measured from the saved rule
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
    /// keep the lock on. The lock is mandatory, so schedules saved before it
    /// was ("lockWhileActive" false) lock too.
    static func lockedUntil(_ rule: ScheduleRule, at date: Date, calendar: Calendar) -> Date? {
        guard canLock(rule.mode),
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

    /// The weekly cycle for a Blocked hours schedule that is on: locked for
    /// seven days from its anchor, then open for a day. A schedule that is
    /// off, or an older Allowed hours one, is free.
    static func weeklyState(_ rule: ScheduleRule, at date: Date) -> WeeklyCommitment.State {
        WeeklyCommitment.state(anchor: weeklyAnchor(rule), at: date)
    }

    private static func weeklyAnchor(_ rule: ScheduleRule) -> Date? {
        rule.isEnabled && canLock(rule.mode) ? rule.lockAnchor : nil
    }

    /// When a schedule can next be weakened: the later of its active window
    /// and its weekly lock, or nil when it can be changed now.
    static func commitmentLockedUntil(_ rule: ScheduleRule, at date: Date, calendar: Calendar) -> Date? {
        let windowEnd = lockedUntil(rule, at: date, calendar: calendar)
        let weekEnd = WeeklyCommitment.lockedUntil(anchor: weeklyAnchor(rule), at: date)
        return [windowEnd, weekEnd].compactMap { $0 }.max()
    }

    static func update(
        from saved: ScheduleRule,
        to proposed: ScheduleRule,
        at date: Date,
        calendar: Calendar
    ) -> Decision {
        guard let end = commitmentLockedUntil(saved, at: date, calendar: calendar) else { return .allowed }
        // Names and reminders never change what is blocked.
        var comparable = proposed
        comparable.name = saved.name
        comparable.notifyAtStart = saved.notifyAtStart
        comparable.notifyAtEnd = saved.notifyAtEnd
        comparable.lockWhileActive = saved.lockWhileActive
        comparable.lockAnchor = saved.lockAnchor
        return comparable == saved ? .allowed : .locked(until: end)
    }

    /// Disabling and removing are both weakening while a lock is active.
    static func removal(of saved: ScheduleRule, at date: Date, calendar: Calendar) -> Decision {
        commitmentLockedUntil(saved, at: date, calendar: calendar).map { .locked(until: $0) } ?? .allowed
    }

    static func lockedMessage(name: String, until end: Date) -> String {
        let sameDay = Calendar.autoupdatingCurrent.isDateInToday(end)
        return "\(name) is locked until \(end.formatted(date: sameDay ? .omitted : .abbreviated, time: sameDay ? .shortened : .omitted))."
    }
}
