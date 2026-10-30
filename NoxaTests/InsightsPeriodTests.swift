import Foundation
import Testing
@testable import Noxa

struct InsightsPeriodTests {
    private var calendar: Calendar {
        var base = Calendar(identifier: .gregorian)
        base.timeZone = TimeZone(identifier: "America/New_York")!
        return FocusStatistics.insightsCalendar(base)
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func session(_ start: Date, minutes: Int, outcome: SessionOutcome = .completed) -> ActiveSessionRecord {
        ActiveSessionRecord(
            startedAt: start,
            plannedEndAt: start.addingTimeInterval(Double(minutes) * 60),
            plannedDurationSeconds: minutes * 60,
            outcome: outcome
        )
    }

    @Test func weeksRunMondayToSunday() {
        // Thursday, October 29, 2026.
        let week = FocusStatistics.interval(of: .week, containing: date(10, 29), calendar: calendar)
        #expect(week.start == calendar.startOfDay(for: date(10, 26)))
        #expect(week.end == calendar.startOfDay(for: date(11, 2)))
        let sunday = FocusStatistics.interval(of: .week, containing: date(11, 1, 23), calendar: calendar)
        #expect(sunday.start == week.start)
    }

    @Test func bucketCountsMatchEachPeriod() {
        let history = [session(date(10, 27, 9), minutes: 60)]
        let day = FocusStatistics.buckets(history: history, in: FocusStatistics.interval(of: .day, containing: date(10, 27), calendar: calendar), unit: .day, calendar: calendar)
        let week = FocusStatistics.buckets(history: history, in: FocusStatistics.interval(of: .week, containing: date(10, 27), calendar: calendar), unit: .week, calendar: calendar)
        let month = FocusStatistics.buckets(history: history, in: FocusStatistics.interval(of: .month, containing: date(10, 27), calendar: calendar), unit: .month, calendar: calendar)
        let year = FocusStatistics.buckets(history: history, in: FocusStatistics.interval(of: .year, containing: date(10, 27), calendar: calendar), unit: .year, calendar: calendar)
        #expect(day.count == 6)
        #expect(week.count == 7)
        #expect(month.count == 31)
        #expect(year.count == 12)
        // Tuesday is the second point of a Monday-first week.
        #expect(week[1].minutes == 60)
        #expect(year[9].minutes == 60)
    }

    @Test func summaryCoversOnlyThePeriod() {
        let history = [
            session(date(10, 26, 9), minutes: 30),
            session(date(10, 26, 15), minutes: 90),
            session(date(10, 28, 9), minutes: 20, outcome: .endedEarly),
            session(date(10, 20, 9), minutes: 45)
        ]
        let summary = FocusStatistics.summary(
            history: history,
            in: FocusStatistics.interval(of: .week, containing: date(10, 29), calendar: calendar),
            calendar: calendar
        )
        #expect(summary.completedSessions == 2)
        #expect(summary.abandonedSessions == 1)
        #expect(summary.focusedDays == 1)
        #expect(summary.longestSessionMinutes == 90)
        #expect(summary.completionRate == 67)
    }

    @Test func milestonePercentNeverRoundsUpToEarned() {
        let milestones = FocusMilestone.all(totalFocusMinutes: 599, completedSessions: 3, longestStreak: 2)
        let tenHours = milestones.first { $0.category == .focusTime && $0.target == 10 }!
        #expect(!tenHours.isEarned)
        #expect(tenHours.percent == 99)
        let oneHour = milestones.first { $0.category == .focusTime && $0.target == 1 }!
        #expect(oneHour.isEarned)
        #expect(oneHour.percent == 100)
    }

    @Test func milestoneSetCoversEveryCategoryAndHighTargets() {
        let milestones = FocusMilestone.all(
            totalFocusMinutes: 0, completedSessions: 0, longestStreak: 0, totalFocusedDays: 3, longSessions: 1
        )
        #expect(Set(milestones.map(\.category)) == Set(FocusMilestone.Category.allCases))
        #expect(milestones.contains { $0.category == .sessions && $0.target == 10_000 })
        #expect(milestones.first { $0.category == .longSessions && $0.target == 1 }?.isEarned == true)
        #expect(milestones.first { $0.category == .focusedDays && $0.target == 7 }?.percent == 42)
    }

    @Test func longSessionsNeedTwoHoursOfBlockedTime() {
        let history = [
            session(date(10, 26, 9), minutes: 120),
            session(date(10, 27, 9), minutes: 90),
            session(date(10, 28, 9), minutes: 180, outcome: .endedEarly)
        ]
        #expect(FocusStatistics.completedSessionCount(history: history, minimumMinutes: 120) == 1)
        #expect(FocusStatistics.totalFocusedDays(history: history, calendar: calendar) == 2)
    }

    @Test func featuredMilestonesAreTheClosestUnearned() {
        let milestones = FocusMilestone.all(totalFocusMinutes: 599, completedSessions: 3, longestStreak: 2)
        let featured = FocusMilestone.featured(from: milestones)
        #expect(featured.count == 3)
        #expect(featured.allSatisfy { !$0.isEarned })
        #expect(featured.first?.title == "10 hours blocked")
    }
}
