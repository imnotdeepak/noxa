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
        completedSessions = completed.count
        abandonedSessions = abandoned.count
        totalFocusMinutes = Self.minutes(in: completed)

        let today = calendar.startOfDay(for: now)
        dailyFocusMinutes = Self.minutes(in: Self.records(completed, sinceDaysAgo: 0, today: today, calendar: calendar))
        weeklyFocusMinutes = Self.minutes(in: Self.records(completed, sinceDaysAgo: 6, today: today, calendar: calendar))
        monthlyFocusMinutes = Self.minutes(in: Self.records(completed, sinceDaysAgo: 29, today: today, calendar: calendar))
        yearlyFocusMinutes = Self.minutes(in: Self.records(completed, sinceDaysAgo: 364, today: today, calendar: calendar))

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

        return FocusPeriodStatistics(
            focusMinutes: minutes(in: completed),
            completedSessions: completed.count,
            abandonedSessions: abandoned.count,
            focusedDays: Set(completed.map { calendar.startOfDay(for: $0.startedAt) }).count
        )
    }

    private static func minutes(in records: [ActiveSessionRecord]) -> Int {
        records.reduce(0) {
            $0 + (($1.actualDurationSeconds ?? $1.plannedDurationSeconds) / 60)
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
