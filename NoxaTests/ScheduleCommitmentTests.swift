import FamilyControls
import Foundation
import Testing
@testable import Noxa

struct ScheduleCommitmentTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 10, day: day, hour: hour, minute: minute
        ))!
    }

    @Test @MainActor func countsOnlyFullTrackedWindowsAndEarlyChanges() {
        let rule = ScheduleRule(
            name: "Weekday mornings",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2, 3],
            startMinutes: 9 * 60,
            endMinutes: 10 * 60
        )
        let began = ScheduleCommitmentEvent(rule: rule, changedAt: date(18, 12))
        var stopped = rule
        stopped.isEnabled = false
        let interruption = ScheduleCommitmentEvent(rule: stopped, changedAt: date(20, 9, 30))

        let result = ScheduleCommitmentEvaluator.lastSevenDays(
            events: [began, interruption], now: date(20, 12), calendar: calendar
        )
        #expect(result.keptWindows == 1)
        #expect(result.interruptedWindows == 1)
        #expect(result.percentage == 50)
    }

    @Test @MainActor func doesNotBackfillWindowsBeforeTrackingStarted() {
        let rule = ScheduleRule(
            name: "Morning",
            mode: .allowedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2],
            startMinutes: 9 * 60,
            endMinutes: 10 * 60
        )
        let beganMidWindow = ScheduleCommitmentEvent(rule: rule, changedAt: date(19, 9, 30))
        let result = ScheduleCommitmentEvaluator.lastSevenDays(
            events: [beganMidWindow], now: date(19, 12), calendar: calendar
        )
        #expect(result.totalWindows == 0)
    }

    @Test @MainActor func overnightWindowCountsAfterItsNextDayEnd() {
        let rule = ScheduleRule(
            name: "Night",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2],
            startMinutes: 22 * 60,
            endMinutes: 7 * 60
        )
        let began = ScheduleCommitmentEvent(rule: rule, changedAt: date(18, 12))
        let beforeEnd = ScheduleCommitmentEvaluator.lastSevenDays(
            events: [began], now: date(20, 6), calendar: calendar
        )
        let afterEnd = ScheduleCommitmentEvaluator.lastSevenDays(
            events: [began], now: date(20, 8), calendar: calendar
        )
        #expect(beforeEnd.totalWindows == 0)
        #expect(afterEnd.keptWindows == 1)
    }
}
