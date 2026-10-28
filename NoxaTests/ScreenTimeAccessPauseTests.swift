import FamilyControls
import Foundation
import Testing
@testable import Noxa

/// The simulator never grants Screen Time access, so these service tests run
/// the same path as a device where the user turned Noxa's access off.
@MainActor struct ScreenTimeAccessPauseTests {
    private func store() throws -> (AppGroupStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.AccessPause.\(UUID())"))
        return (AppGroupStore(defaults: defaults), defaults)
    }

    @Test func pausesOpenOnceAndCloseOnce() throws {
        let (store, _) = try store()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        store.beginScreenTimeAccessPause(at: start)
        store.beginScreenTimeAccessPause(at: start.addingTimeInterval(60))
        #expect(store.isScreenTimeAccessPaused)
        #expect(store.loadScreenTimeAccessPauses().count == 1)

        store.endScreenTimeAccessPause(at: start.addingTimeInterval(120))
        store.endScreenTimeAccessPause(at: start.addingTimeInterval(180))
        #expect(!store.isScreenTimeAccessPaused)
        #expect(store.loadScreenTimeAccessPauses()
            == [ScreenTimeAccessPause(startedAt: start, endedAt: start.addingTimeInterval(120))])
        store.clearScreenTimeAccessPauses()
        #expect(store.loadScreenTimeAccessPauses().isEmpty)
    }

    @Test func overlapCountsOpenPausesUpToNow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = DateInterval(start: start, duration: 900)
        let before = ScreenTimeAccessPause(startedAt: start.addingTimeInterval(-600), endedAt: start.addingTimeInterval(-1))
        let during = ScreenTimeAccessPause(startedAt: start.addingTimeInterval(300), endedAt: start.addingTimeInterval(400))
        let stillOpen = ScreenTimeAccessPause(startedAt: start.addingTimeInterval(-60), endedAt: nil)

        #expect(!ScreenTimeAccessPause.overlaps(session, [before], now: start.addingTimeInterval(900)))
        #expect(ScreenTimeAccessPause.firstOverlap(with: session, [during]) == start.addingTimeInterval(300))
        #expect(ScreenTimeAccessPause.firstOverlap(
            with: session, [stillOpen], now: start.addingTimeInterval(10)
        ) == start)
    }

    @Test func pomodoroRoundThatOverlappedAPauseIsInterrupted() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let round = ActiveSessionRecord(
            startedAt: start,
            plannedEndAt: start.addingTimeInterval(1_500),
            plannedDurationSeconds: 1_500,
            outcome: .completed,
            actualDurationSeconds: 1_500
        )
        let pause = ScreenTimeAccessPause(startedAt: start.addingTimeInterval(600), endedAt: start.addingTimeInterval(700))

        let interrupted = FocusSessionService.applyingAccessPauses([pause], to: round)
        #expect(interrupted.outcome == .interrupted)
        #expect(interrupted.actualDurationSeconds == 600)
        #expect(FocusSessionService.applyingAccessPauses([], to: round) == round)
    }

    @Test func runningSessionPausesInsteadOfEndingWithoutAccess() throws {
        let (store, _) = try store()
        let session = ActiveSessionRecord(
            plannedEndAt: Date().addingTimeInterval(900),
            plannedDurationSeconds: 900,
            outcome: .active
        )
        try store.saveSnapshot(NoxaLocalSnapshot(sessionEngineState: .active, activeSession: session))
        try store.saveFocusSessionRestrictions(
            FocusSessionRestrictionConfiguration(selection: FamilyActivitySelection(), websiteDomains: ["example.com"])
        )

        let service = FocusSessionService(store: store)
        service.reconcile()

        #expect(service.activeSession?.id == session.id)
        #expect(service.isPausedForScreenTimeAccess)
        #expect(store.isScreenTimeAccessPaused)
        #expect(try store.loadSnapshot()?.activeSession?.outcome == .active)
        // The saved targets stay so iOS and Noxa can restore the same block.
        #expect(try store.loadFocusSessionRestrictions()?.websiteDomains == ["example.com"])
        #expect(service.history.isEmpty)
    }

    @Test func sessionThatEndsDuringAPauseIsRecordedAsInterrupted() throws {
        let (store, _) = try store()
        let startedAt = Date().addingTimeInterval(-1_200)
        let session = ActiveSessionRecord(
            startedAt: startedAt,
            plannedEndAt: startedAt.addingTimeInterval(900),
            plannedDurationSeconds: 900,
            outcome: .active
        )
        try store.saveSnapshot(NoxaLocalSnapshot(sessionEngineState: .active, activeSession: session))
        store.beginScreenTimeAccessPause(at: startedAt.addingTimeInterval(300))

        let service = FocusSessionService(store: store)
        service.reconcile()

        #expect(service.activeSession == nil)
        #expect(!service.isPausedForScreenTimeAccess)
        let recorded = try #require(service.history.first)
        #expect(recorded.id == session.id)
        #expect(recorded.outcome == .interrupted)
        #expect(recorded.actualDurationSeconds == 300)
        #expect(!recorded.outcome.countsTowardFocusStatistics)
    }
}
