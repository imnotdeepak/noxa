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
