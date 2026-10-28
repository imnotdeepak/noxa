import Foundation

/// DeviceActivity schedules omit fractional seconds. Start/end callbacks may
/// arrive just before a saved boundary; one-second warning callbacks arrive
/// earlier still. Only move a callback forward within its narrow tolerance.
enum DeviceActivityBoundaryClock {
    static func effectiveDate(
        now: Date,
        expectedBoundary: Date?,
        maxEarlySeconds: TimeInterval = 1
    ) -> Date {
        guard let expectedBoundary,
              expectedBoundary > now,
              expectedBoundary.timeIntervalSince(now) <= maxEarlySeconds else { return now }
        return expectedBoundary
    }
}

extension DateInterval {
    /// `contains(_:)` includes `end`, so a callback snapped onto a work
    /// round's end would still count as work. The end instant belongs to the
    /// following break, matching `PomodoroCyclePlan.phase(at:)`.
    nonisolated func containsBeforeEnd(_ date: Date) -> Bool {
        start <= date && date < end
    }
}
