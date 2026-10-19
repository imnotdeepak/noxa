import FamilyControls
import Foundation
import Testing
@testable import Noxa

struct PomodoroCycleRecordTests {
    @Test func enforcementStampKeepsFirstApplicationAndCanBeCleared() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.PomodoroStamp.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let cycleID = UUID()
        let first = Date(timeIntervalSince1970: 1_700_000_000)

        store.markPomodoroRoundEnforced(cycleID: cycleID, round: 2, at: first)
        store.markPomodoroRoundEnforced(cycleID: cycleID, round: 2, at: first.addingTimeInterval(60))
        #expect(store.pomodoroRoundEnforcedAt(cycleID: cycleID, round: 2) == first)

        store.clearPomodoroRoundEnforcement(cycleID: cycleID)
        #expect(store.pomodoroRoundEnforcedAt(cycleID: cycleID, round: 2) == nil)
    }

    @Test func roundRecordsKeepStrictPolicyAndRecoverCompletedWork() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let cycle = PomodoroCycleRecord(
            plan: PomodoroCyclePlan(startedAt: start, workMinutes: 25, breakMinutes: 5),
            selection: FamilyActivitySelection(),
            websiteDomains: ["reddit.com"],
            isStrict: true,
            firstSessionID: firstID
        )

        #expect(cycle.session(for: 1)?.id == firstID)
        #expect(cycle.session(for: 4)?.isStrict == true)
        let allRoundsEnforced: (Int) -> Date? = { round in
            cycle.plan.workInterval(round: round)?.start
        }
        #expect(cycle.verifiedCompletedSessions(
            asOf: start.addingTimeInterval(1_799), enforcedAt: allRoundsEnforced
        ).count == 1)
        #expect(cycle.verifiedCompletedSessions(
            asOf: start.addingTimeInterval(5_401), enforcedAt: allRoundsEnforced
        ).count == 3)
        #expect(cycle.verifiedCompletedSessions(
            asOf: start.addingTimeInterval(6_900), enforcedAt: allRoundsEnforced
        ).count == 4)
        #expect(cycle.verifiedCompletedSessions(
            asOf: start.addingTimeInterval(6_900), enforcedAt: allRoundsEnforced
        ).allSatisfy {
            $0.outcome == .completed && $0.actualDurationSeconds == 1_500
        })

        let onlyFirstRound = cycle.verifiedCompletedSessions(
            asOf: start.addingTimeInterval(6_900),
            enforcedAt: { $0 == 1 ? start : nil }
        )
        #expect(onlyFirstRound.map(\.id) == [firstID])

        let restored = try JSONDecoder().decode(
            PomodoroCycleRecord.self,
            from: JSONEncoder().encode(cycle)
        )
        #expect(restored == cycle)
    }
}
