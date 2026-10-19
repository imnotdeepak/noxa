import Foundation
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
}
