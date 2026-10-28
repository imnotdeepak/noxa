import Foundation
import Testing
@testable import Noxa

struct PomodoroBreakTimingTests {
    @Test func fiveMinuteBreakRemindersFollowTheWorkInterval() {
        let workEnd = Date(timeIntervalSince1970: 1_700_000_000)
        let timing = PomodoroBreakTiming(workEndsAt: workEnd, breakMinutes: 5)

        #expect(timing.halfwayAt.timeIntervalSince(workEnd) == 150)
        #expect(timing.oneMinuteRemainingAt.timeIntervalSince(workEnd) == 240)
        #expect(timing.endsAt.timeIntervalSince(workEnd) == 300)
        #expect(timing.halfwayAt < timing.oneMinuteRemainingAt)
    }

    @Test func longerBreakKeepsTheOneMinuteWarningNearItsEnd() {
        let workEnd = Date(timeIntervalSince1970: 1_700_000_000)
        let timing = PomodoroBreakTiming(workEndsAt: workEnd, breakMinutes: 15)

        #expect(timing.halfwayAt.timeIntervalSince(workEnd) == 450)
        #expect(timing.endsAt.timeIntervalSince(timing.oneMinuteRemainingAt) == 60)
    }
}
