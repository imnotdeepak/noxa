import DeviceActivity
import Foundation
import Testing
@testable import Noxa

struct PomodoroCyclePlanTests {
    @Test func fourRoundsHaveThreeBreaksAndThenComplete() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = PomodoroCyclePlan(startedAt: start, workMinutes: 25, breakMinutes: 5)

        #expect(plan.phase(at: start.addingTimeInterval(-1)) == .scheduled(startsAt: start))
        #expect(plan.phase(at: start) == .work(round: 1, endsAt: start.addingTimeInterval(1_500)))
        #expect(plan.phase(at: start.addingTimeInterval(1_500)) == .breakTime(
            afterRound: 1, endsAt: start.addingTimeInterval(1_800)
        ))
        #expect(plan.workInterval(round: 4)?.start == start.addingTimeInterval(5_400))
        #expect(plan.breakInterval(afterRound: 4) == nil)
        #expect(plan.phase(at: start.addingTimeInterval(6_900)) == .complete)
    }

    @Test func timelineClampsDurationsAndRejectsOutOfRangeRounds() {
        let plan = PomodoroCyclePlan(startedAt: .now, workMinutes: 500, breakMinutes: 1)
        #expect(plan.workMinutes == 240)
        #expect(plan.breakMinutes == 5)
        #expect(plan.workInterval(round: 0) == nil)
        #expect(plan.workInterval(round: 5) == nil)
    }

    @Test func deviceActivityResolvesFutureRoundToPlannedInterval() throws {
        let calendar = Calendar.current
        let start = Date().addingTimeInterval(3_600)
        let end = start.addingTimeInterval(900)
        let components: Set<Calendar.Component> = [
            .calendar, .year, .month, .day, .hour, .minute, .second
        ]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        let resolved = try #require(schedule.nextInterval)
        #expect(abs(resolved.start.timeIntervalSince(start)) < 1)
        #expect(abs(resolved.end.timeIntervalSince(end)) < 1)
    }

    @Test func boundaryCallbackUsesSavedFractionalSecondOnlyWhenNearlyEarly() {
        let boundary = Date(timeIntervalSince1970: 1_700_000_000.227887)
        #expect(DeviceActivityBoundaryClock.effectiveDate(
            now: boundary.addingTimeInterval(-0.025), expectedBoundary: boundary
        ) == boundary)
        let tooEarly = boundary.addingTimeInterval(-2)
        #expect(DeviceActivityBoundaryClock.effectiveDate(
            now: tooEarly, expectedBoundary: boundary
        ) == tooEarly)
        let late = boundary.addingTimeInterval(0.5)
        #expect(DeviceActivityBoundaryClock.effectiveDate(
            now: late, expectedBoundary: boundary
        ) == late)
    }

    @Test func oneSecondWarningCanReconcileFractionalBoundaryWithoutMovingEarlierPhases() {
        let boundary = Date(timeIntervalSince1970: 1_700_000_000.477)
        let warning = boundary.addingTimeInterval(-1.477)
        #expect(DeviceActivityBoundaryClock.effectiveDate(
            now: warning, expectedBoundary: boundary, maxEarlySeconds: 3
        ) == boundary)
        let unrelatedEarlyCallback = boundary.addingTimeInterval(-4)
        #expect(DeviceActivityBoundaryClock.effectiveDate(
            now: unrelatedEarlyCallback, expectedBoundary: boundary, maxEarlySeconds: 3
        ) == unrelatedEarlyCallback)
    }
}
