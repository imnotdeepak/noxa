import Foundation

/// Rules commit for a week at a time. From its anchor a rule is locked for
/// seven days, then open for one day of changes, then locked again; the
/// cycle repeats until the rule is turned off or removed during a window.
/// Shared by daily limits, schedules, and the Reels and Shorts filters.
enum WeeklyCommitment {
    enum State: Equatable {
        /// No anchor: saved before weekly locks existed, or currently off.
        case unlocked
        case locked(until: Date)
        case changeWindow(until: Date)
    }

    static let lockDuration: TimeInterval = 7 * 24 * 60 * 60
    static let changeWindowDuration: TimeInterval = 24 * 60 * 60

    static func state(anchor: Date?, at date: Date) -> State {
        guard let anchor else { return .unlocked }
        let cycle = lockDuration + changeWindowDuration
        let elapsed = date.timeIntervalSince(anchor)
        // A clock set back before the anchor can't open the window early.
        guard elapsed >= 0 else { return .locked(until: anchor.addingTimeInterval(lockDuration)) }
        let cycleStart = anchor.addingTimeInterval(floor(elapsed / cycle) * cycle)
        let lockEnd = cycleStart.addingTimeInterval(lockDuration)
        return date < lockEnd
            ? .locked(until: lockEnd)
            : .changeWindow(until: cycleStart.addingTimeInterval(cycle))
    }

    static func lockedUntil(anchor: Date?, at date: Date) -> Date? {
        if case .locked(let end) = state(anchor: anchor, at: date) { return end }
        return nil
    }
}

/// Daily limits use the weekly cycle. Stricter changes (a lower allowance,
/// turning a limit on) are always allowed.
enum DailyLimitCommitmentPolicy {
    typealias State = WeeklyCommitment.State

    static let lockDuration = WeeklyCommitment.lockDuration
    static let changeWindowDuration = WeeklyCommitment.changeWindowDuration

    static func state(for configuration: DailyLimitConfiguration, at date: Date) -> State {
        WeeklyCommitment.state(anchor: configuration.lockAnchor, at: date)
    }

    static func lockedUntil(_ configuration: DailyLimitConfiguration, at date: Date) -> Date? {
        if case .locked(let end) = state(for: configuration, at: date) { return end }
        return nil
    }

    static func canChangeMinutes(
        of configuration: DailyLimitConfiguration,
        to minutes: Int,
        at date: Date
    ) -> Bool {
        lockedUntil(configuration, at: date) == nil || minutes <= configuration.dailyLimitMinutes
    }

    static func lockedMessage(until end: Date) -> String {
        "This limit is locked until \(end.formatted(date: .abbreviated, time: .shortened)). You can lower it now, or change it once the week is up."
    }
}
