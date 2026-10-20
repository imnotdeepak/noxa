import Foundation

/// Device-local configuration history used for a modest follow-through metric.
/// It contains no Screen Time selection tokens or app usage.
struct ScheduleCommitmentEvent: Codable, Equatable, Sendable {
    let ruleID: UUID
    let changedAt: Date
    let weekdays: Set<Int>
    let startMinutes: Int
    let endMinutes: Int
    let isEnabled: Bool
    let isRemoved: Bool

    init(rule: ScheduleRule, changedAt: Date = Date(), isRemoved: Bool = false) {
        ruleID = rule.id
        self.changedAt = changedAt
        weekdays = rule.weekdays
        startMinutes = rule.startMinutes
        endMinutes = rule.endMinutes
        isEnabled = rule.isEnabled
        self.isRemoved = isRemoved
    }
}

struct ScheduleCommitmentSummary: Equatable, Sendable {
    let keptWindows: Int
    let interruptedWindows: Int

    var totalWindows: Int { keptWindows + interruptedWindows }
    var percentage: Int {
        guard totalWindows > 0 else { return 0 }
        return Int((Double(keptWindows) / Double(totalWindows) * 100).rounded())
    }
}

enum ScheduleCommitmentEvaluator {
    /// Counts completed, tracked schedule windows in the last seven local days.
    /// A configuration edit or disable during a window interrupts that window.
    /// This says nothing about whether iOS visibly blocked a target.
    static func lastSevenDays(
        events: [ScheduleCommitmentEvent],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> ScheduleCommitmentSummary {
        let grouped = Dictionary(grouping: events, by: \.ruleID)
            .mapValues { $0.sorted { $0.changedAt < $1.changedAt } }
        let today = calendar.startOfDay(for: now)
        var kept = 0
        var interrupted = 0

        for dayOffset in -6...0 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            for changes in grouped.values {
                // A schedule's local start time identifies its planned window.
                // The latest snapshot at that time defines the commitment.
                for candidate in changes where candidate.weekdays.contains(weekday) {
                    guard let start = boundary(
                        on: day,
                        minute: candidate.startMinutes,
                        calendar: calendar
                    ), start < now,
                    let active = changes.last(where: { $0.changedAt <= start }),
                    active == candidate,
                    active.isEnabled, !active.isRemoved,
                    let end = nextBoundary(
                        after: start,
                        minute: active.endMinutes,
                        calendar: calendar
                    ), end <= now else { continue }

                    if changes.contains(where: { $0.changedAt > start && $0.changedAt < end }) {
                        interrupted += 1
                    } else {
                        kept += 1
                    }
                }
            }
        }
        return ScheduleCommitmentSummary(keptWindows: kept, interruptedWindows: interrupted)
    }

    private static func boundary(on day: Date, minute: Int, calendar: Calendar) -> Date? {
        guard let candidate = calendar.nextDate(
            after: day.addingTimeInterval(-1),
            matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(candidate, inSameDayAs: day) else { return nil }
        return candidate
    }

    private static func nextBoundary(after start: Date, minute: Int, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: start,
            matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}
