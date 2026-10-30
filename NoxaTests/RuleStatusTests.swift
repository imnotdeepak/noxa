import FamilyControls
import Foundation
import Testing
@testable import Noxa

struct RuleStatusTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }

    private func date(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: hour))!
    }

    private func rule(enabled: Bool = true) -> ScheduleRule {
        var rule = ScheduleRule(
            name: "Evening",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            startMinutes: 21 * 60,
            endMinutes: 23 * 60
        )
        rule.isEnabled = enabled
        return rule
    }

    @Test func onIsNotTheSameAsBlockingNow() {
        #expect(RuleStatus.schedule(rule(), isAuthorized: true, lockedUntil: nil, at: date(12), calendar: calendar)
            == .scheduled(next: date(21)))
        #expect(RuleStatus.schedule(rule(), isAuthorized: true, lockedUntil: nil, at: date(22), calendar: calendar)
            == .blockingNow)
        #expect(RuleStatus.schedule(rule(enabled: false), isAuthorized: true, lockedUntil: nil, at: date(22), calendar: calendar)
            == .off)
    }

    @Test func missingPermissionWinsOverEveryOtherState() {
        #expect(RuleStatus.schedule(rule(), isAuthorized: false, lockedUntil: date(23), at: date(22), calendar: calendar)
            == .needsPermission)
        #expect(RuleStatus.dailyLimit(isEnabled: true, isAuthorized: false, isMonitoring: true, hasReachedLimit: true)
            == .needsPermission)
    }

    @Test func pausedLimitNeverLooksEnforced() {
        #expect(RuleStatus.dailyLimit(isEnabled: true, isAuthorized: true, isMonitoring: false, hasReachedLimit: true)
            == .paused)
        #expect(RuleStatus.dailyLimit(isEnabled: true, isAuthorized: true, isMonitoring: true, hasReachedLimit: false)
            == .counting)
        #expect(RuleStatus.dailyLimit(isEnabled: true, isAuthorized: true, isMonitoring: true, hasReachedLimit: true)
            == .blockingNow)
    }

    @Test func futureBucketsAreMarked() {
        var base = Calendar(identifier: .gregorian)
        base.timeZone = calendar.timeZone
        let insights = FocusStatistics.insightsCalendar(base)
        let week = FocusStatistics.interval(of: .week, containing: date(12), calendar: insights)
        let buckets = FocusStatistics.buckets(history: [], in: week, unit: .week, now: date(12), calendar: insights)
        // Wednesday the 28th: Monday to Wednesday have happened.
        #expect(buckets.map(\.isFuture) == [false, false, false, true, true, true, true])
    }
}
