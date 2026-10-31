import Foundation

struct FocusPeriodStatistics: Equatable, Sendable {
    let focusMinutes: Int
    let completedSessions: Int
    let abandonedSessions: Int
    let focusedDays: Int

    var completionRate: Int {
        let attempted = completedSessions + abandonedSessions
        guard attempted > 0 else { return 0 }
        return Int((Double(completedSessions) / Double(attempted) * 100).rounded())
    }
}

enum FocusPeriodUnit: CaseIterable, Hashable, Sendable {
    case day, week, month, year

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

struct FocusPeriodSummary: Equatable, Sendable {
    let focusMinutes: Int
    let completedSessions: Int
    let abandonedSessions: Int
    let focusedDays: Int
    let longestSessionMinutes: Int
    let averageMinutesPerFocusedDay: Int

    /// Completed out of completed plus ended early or interrupted.
    var completionRate: Int {
        let attempted = completedSessions + abandonedSessions
        guard attempted > 0 else { return 0 }
        return Int((Double(completedSessions) / Double(attempted) * 100).rounded())
    }
}

struct FocusBucket: Equatable, Identifiable, Sendable {
    let start: Date
    let minutes: Int
    let sessions: Int
    /// Not happened yet: drawn blank, never as a recorded zero.
    var isFuture = false

    var id: Date { start }
}

struct FocusStatistics: Equatable, Sendable {
    let completedSessions: Int
    let abandonedSessions: Int
    let totalFocusMinutes: Int
    let dailyFocusMinutes: Int
    let weeklyFocusMinutes: Int
    let monthlyFocusMinutes: Int
    let yearlyFocusMinutes: Int
    let currentStreak: Int
    let longestStreak: Int

    var completionRate: Int {
        let attempted = completedSessions + abandonedSessions
        guard attempted > 0 else { return 0 }
        return Int((Double(completedSessions) / Double(attempted) * 100).rounded())
    }

    init(
        history: [ActiveSessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let completed = history.filter { $0.outcome.countsTowardFocusStatistics }
        let abandoned = history.filter { [.endedEarly, .interrupted].contains($0.outcome) }
        let protected = history.filter { $0.outcome.countsTowardProtectedTime }
        completedSessions = completed.count
        abandonedSessions = abandoned.count
        totalFocusMinutes = Self.minutes(in: protected)

        let today = calendar.startOfDay(for: now)
        dailyFocusMinutes = Self.minutes(in: Self.records(protected, sinceDaysAgo: 0, today: today, calendar: calendar))
        weeklyFocusMinutes = Self.minutes(in: Self.records(protected, sinceDaysAgo: 6, today: today, calendar: calendar))
        monthlyFocusMinutes = Self.minutes(in: Self.records(protected, sinceDaysAgo: 29, today: today, calendar: calendar))
        yearlyFocusMinutes = Self.minutes(in: Self.records(protected, sinceDaysAgo: 364, today: today, calendar: calendar))

        let completedDays = Set(completed.map { calendar.startOfDay(for: $0.startedAt) })
        let streaks = Self.streaks(completedDays: completedDays, now: now, calendar: calendar)
        currentStreak = streaks.current
        longestStreak = streaks.longest
    }

    static func period(
        history: [ActiveSessionRecord],
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FocusPeriodStatistics {
        let today = calendar.startOfDay(for: now)
        let lookback = max(days - 1, 0)
        let completed = records(
            history.filter { $0.outcome.countsTowardFocusStatistics },
            sinceDaysAgo: lookback,
            today: today,
            calendar: calendar
        )
        let abandoned = records(
            history.filter { [.endedEarly, .interrupted].contains($0.outcome) },
            sinceDaysAgo: lookback,
            today: today,
            calendar: calendar
        )
        let protected = records(
            history.filter { $0.outcome.countsTowardProtectedTime },
            sinceDaysAgo: lookback,
            today: today,
            calendar: calendar
        )

        return FocusPeriodStatistics(
            focusMinutes: minutes(in: protected),
            completedSessions: completed.count,
            abandonedSessions: abandoned.count,
            focusedDays: Set(completed.map { calendar.startOfDay(for: $0.startedAt) }).count
        )
    }

    /// Different days with at least one completed session, all time.
    static func totalFocusedDays(history: [ActiveSessionRecord], calendar: Calendar) -> Int {
        Set(history.filter { $0.outcome.countsTowardFocusStatistics }
            .map { calendar.startOfDay(for: $0.startedAt) }).count
    }

    /// Completed sessions whose blocked time reached `minimumMinutes`.
    static func completedSessionCount(history: [ActiveSessionRecord], minimumMinutes: Int) -> Int {
        history.filter {
            $0.outcome.countsTowardFocusStatistics && protectedDurationSeconds(for: $0) >= minimumMinutes * 60
        }.count
    }

    /// The calendar Insights uses: weeks run Monday to Sunday.
    static func insightsCalendar(_ base: Calendar = .autoupdatingCurrent) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func interval(
        of unit: FocusPeriodUnit,
        containing date: Date,
        calendar: Calendar
    ) -> DateInterval {
        calendar.dateInterval(of: unit.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    /// Totals for one calendar period. Sessions count in the period where
    /// they started, as the chart buckets do.
    static func summary(
        history: [ActiveSessionRecord],
        in interval: DateInterval,
        calendar: Calendar
    ) -> FocusPeriodSummary {
        let inPeriod = history.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
        let completed = inPeriod.filter { $0.outcome.countsTowardFocusStatistics }
        let abandoned = inPeriod.filter { [.endedEarly, .interrupted].contains($0.outcome) }
        let protected = inPeriod.filter { $0.outcome.countsTowardProtectedTime }
        let focusedDays = Set(completed.map { calendar.startOfDay(for: $0.startedAt) }).count
        let totalMinutes = minutes(in: protected)
        return FocusPeriodSummary(
            focusMinutes: totalMinutes,
            completedSessions: completed.count,
            abandonedSessions: abandoned.count,
            focusedDays: focusedDays,
            longestSessionMinutes: protected.map { protectedDurationSeconds(for: $0) / 60 }.max() ?? 0,
            averageMinutesPerFocusedDay: focusedDays == 0 ? 0 : totalMinutes / focusedDays
        )
    }

    /// Chart points for one calendar period: four-hour blocks for a day,
    /// days for a week or month, and months for a year.
    static func buckets(
        history: [ActiveSessionRecord],
        in interval: DateInterval,
        unit: FocusPeriodUnit,
        now: Date = Date(),
        calendar: Calendar
    ) -> [FocusBucket] {
        let protected = history.filter { $0.outcome.countsTowardProtectedTime }
        let step: (component: Calendar.Component, value: Int) = switch unit {
        case .day: (.hour, 4)
        case .week, .month: (.day, 1)
        case .year: (.month, 1)
        }
        var buckets: [FocusBucket] = []
        var start = interval.start
        while start < interval.end, let end = calendar.date(byAdding: step.component, value: step.value, to: start) {
            let inBucket = protected.filter { $0.startedAt >= start && $0.startedAt < end }
            buckets.append(FocusBucket(
                start: start,
                minutes: minutes(in: inBucket),
                sessions: inBucket.count,
                isFuture: start > now
            ))
            start = end
        }
        return buckets
    }

    /// Focus minutes in this period against the same stretch of the
    /// previous one: for the current period, only as far as `now` has got,
    /// so a half-finished week is compared with the first half of the last.
    /// Nil when there is no history from before this period to compare with.
    static func comparison(
        history: [ActiveSessionRecord],
        in interval: DateInterval,
        unit: FocusPeriodUnit,
        now: Date,
        calendar: Calendar
    ) -> (current: Int, previous: Int)? {
        guard history.contains(where: { $0.startedAt < interval.start }),
              let previousStart = calendar.date(byAdding: unit.component, value: -1, to: interval.start) else { return nil }
        let currentEnd = min(interval.end, max(now, interval.start))
        let span = currentEnd.timeIntervalSince(interval.start)
        let previous = DateInterval(start: previousStart, end: min(previousStart.addingTimeInterval(span), interval.start))
        let current = DateInterval(start: interval.start, end: currentEnd)
        return (
            summary(history: history, in: current, calendar: calendar).focusMinutes,
            summary(history: history, in: previous, calendar: calendar).focusMinutes
        )
    }

    /// Monday-to-Sunday days of the week containing `date`, and whether each
    /// had a completed session.
    static func focusedDays(
        inWeekContaining date: Date,
        history: [ActiveSessionRecord],
        calendar: Calendar
    ) -> [(day: Date, focused: Bool)] {
        let week = interval(of: .week, containing: date, calendar: calendar)
        let focusedDays = Set(
            history.filter { $0.outcome.countsTowardFocusStatistics }
                .map { calendar.startOfDay(for: $0.startedAt) }
        )
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.start).map { ($0, focusedDays.contains($0)) }
        }
    }

    /// Days in the last week with a completed session, oldest first.
    static func focusedDaysInLastWeek(
        history: [ActiveSessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(day: Date, focused: Bool)] {
        let today = calendar.startOfDay(for: now)
        let focusedDays = Set(
            history.filter { $0.outcome.countsTowardFocusStatistics }
                .map { calendar.startOfDay(for: $0.startedAt) }
        )
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, focusedDays.contains($0)) }
        }
    }

    private static func minutes(in records: [ActiveSessionRecord]) -> Int {
        records.reduce(0) { $0 + protectedDurationSeconds(for: $1) } / 60
    }

    private static func protectedDurationSeconds(for record: ActiveSessionRecord) -> Int {
        switch record.outcome {
        case .completed, .recoveredStale:
            return max(0, record.actualDurationSeconds ?? record.plannedDurationSeconds)
        case .endedEarly:
            return max(0, record.actualDurationSeconds ?? 0)
        case .startPending, .active, .failedToStart, .interrupted:
            return 0
        }
    }

    private static func records(
        _ records: [ActiveSessionRecord],
        sinceDaysAgo days: Int,
        today: Date,
        calendar: Calendar
    ) -> [ActiveSessionRecord] {
        guard let start = calendar.date(byAdding: .day, value: -days, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }
        return records.filter { $0.startedAt >= start && $0.startedAt < tomorrow }
    }

    private static func streaks(
        completedDays: Set<Date>,
        now: Date,
        calendar: Calendar
    ) -> (current: Int, longest: Int) {
        guard !completedDays.isEmpty else { return (0, 0) }
        let ordered = completedDays.sorted()
        var longest = 1
        var run = 1
        for index in 1..<ordered.count {
            let difference = calendar.dateComponents(
                [.day],
                from: ordered[index - 1],
                to: ordered[index]
            ).day
            if difference == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        guard completedDays.contains(today) || (yesterday.map(completedDays.contains) ?? false) else {
            return (0, longest)
        }

        var current = 0
        var cursor = completedDays.contains(today) ? today : yesterday!
        while completedDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return (current, longest)
    }
}
