import Foundation
import FamilyControls
import Testing
@testable import Noxa

struct RestrictionRuleEvaluatorTests {
    private let focus = RestrictionRuleID(
        source: .focusSession,
        value: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
    private let schedule = RestrictionRuleID(
        source: .schedule,
        value: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
    private let dailyLimit = RestrictionRuleID(
        source: .dailyLimit,
        value: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    )

    @Test func endingOneOverlappingRuleKeepsTheOtherBlock() {
        let active = RestrictionRuleEvaluator.evaluate([
            RestrictionRule(id: focus, effect: .block, targets: ["Instagram", "Reddit"]),
            RestrictionRule(id: dailyLimit, effect: .block, targets: ["Instagram"])
        ])
        #expect(active.blockedTargets == ["Instagram", "Reddit"])
        #expect(active.owners(for: "Instagram") == [focus, dailyLimit])
        #expect(active.owners(for: "Reddit") == [focus])

        let focusEnded = RestrictionRuleEvaluator.evaluate([
            RestrictionRule(id: focus, effect: .inactive, targets: ["Instagram", "Reddit"]),
            RestrictionRule(id: dailyLimit, effect: .block, targets: ["Instagram"])
        ])
        #expect(focusEnded.blockedTargets == ["Instagram"])
        #expect(focusEnded.owners(for: "Instagram") == [dailyLimit])
    }

    @Test func allowedScheduleWindowCannotOverrideAnIndependentBlock() {
        let result = RestrictionRuleEvaluator.evaluate([
            RestrictionRule(id: schedule, effect: .allow, targets: ["Instagram", "Reddit"]),
            RestrictionRule(id: dailyLimit, effect: .block, targets: ["Instagram"])
        ])
        #expect(result.blockedTargets == ["Instagram"])
        #expect(result.owners(for: "Instagram") == [dailyLimit])
        #expect(result.owners(for: "Reddit").isEmpty)
    }

    @Test func twoSchedulesCanBlockTheSameTargetAndRepeatedCallbacksAreIdempotent() {
        let result = RestrictionRuleEvaluator.evaluate([
            RestrictionRule(id: schedule, effect: .block, targets: ["Instagram"]),
            RestrictionRule(id: schedule, effect: .block, targets: ["Instagram"]),
            RestrictionRule(id: focus, effect: .block, targets: ["Instagram"])
        ])
        #expect(result.blockedTargets == ["Instagram"])
        #expect(result.owners(for: "Instagram") == [schedule, focus])
    }

    @Test func liveOwnershipPlanPreservesAnotherOwnerAfterFocusEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 20, hour: 10
        )))
        let selection = FamilyActivitySelection()
        let focusID = UUID()
        let schedule = ScheduleRule(
            name: "Allowed morning",
            mode: .allowedHours,
            selection: selection,
            websiteDomains: ["example.com"],
            weekdays: [3],
            startMinutes: 9 * 60,
            endMinutes: 11 * 60
        )
        let focusRule = RestrictionOwnershipPlan.Focus(
            id: focusID,
            plannedEndAt: now.addingTimeInterval(30 * 60),
            isPomodoro: false,
            restrictions: FocusSessionRestrictionConfiguration(
                selection: selection,
                websiteDomains: ["example.com"]
            )
        )
        let inputs = RestrictionOwnershipPlan.Inputs(
            focus: focusRule,
            schedules: [schedule],
            manualShield: ManualShieldConfiguration(
                selection: selection,
                websiteDomains: ["EXAMPLE.COM"]
            )
        )
        let target = RestrictionTarget.domain("example.com")
        let active = RestrictionOwnershipPlan.evaluate(inputs, at: now, calendar: calendar)
        #expect(active.owners(for: target).contains(
            RestrictionRuleID(source: .focusSession, value: focusID)
        ))
        #expect(active.owners(for: target).contains(where: { $0.source == .manualShield }))
        #expect(!active.owners(for: target).contains(where: { $0.source == .schedule }))

        let focusEnded = RestrictionOwnershipPlan.evaluate(
            inputs,
            at: now.addingTimeInterval(31 * 60),
            calendar: calendar
        )
        #expect(focusEnded.owners(for: target).count == 1)
        #expect(focusEnded.owners(for: target).contains(where: { $0.source == .manualShield }))
    }

    @Test func reachedDailyLimitMarkersExpireAtLocalMidnight() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DailyMarker.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        defaults.set(NoxaDeviceActivityConfiguration.dailyLimitDayStamp(for: day, calendar: calendar),
                     forKey: "noxa.dailyLimitResetDay")
        defaults.set(["noxa.daily.limit.test"], forKey: "noxa.dailyLimitReachedEvents")
        #expect(store.reachedDailyLimitEventNames(at: day, calendar: calendar)
            == ["noxa.daily.limit.test"])
        #expect(store.reachedDailyLimitEventNames(
            at: day.addingTimeInterval(24 * 60 * 60), calendar: calendar
        ).isEmpty)
    }

    @Test func pomodoroBreakDoesNotReleaseAnIndependentScheduleOrFullSiteBlock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 20, hour: 10
        )))
        let schedule = ScheduleRule(
            name: "Work hours",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            weekdays: [3],
            startMinutes: 9 * 60,
            endMinutes: 11 * 60
        )
        let result = RestrictionOwnershipPlan.evaluate(
            .init(schedules: [schedule], instagramFullBlockRequested: true),
            at: now,
            calendar: calendar
        )
        #expect(result.owners(for: .domain("example.com"))
            == [RestrictionRuleID(source: .schedule, value: schedule.id)])
        #expect(result.owners(for: .domain("instagram.com"))
            .contains(where: { $0.source == .instagramFullBlock }))
    }
}
