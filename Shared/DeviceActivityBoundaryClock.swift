import Foundation

/// DeviceActivity schedules omit fractional seconds. A callback can arrive
/// just before the saved boundary when its whole-second interval begins.
enum DeviceActivityBoundaryClock {
    static func effectiveDate(now: Date, expectedBoundary: Date?) -> Date {
        guard let expectedBoundary,
              expectedBoundary > now,
              expectedBoundary.timeIntervalSince(now) <= 1 else { return now }
        return expectedBoundary
    }
}
