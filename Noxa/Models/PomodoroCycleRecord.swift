import FamilyControls
import Foundation

/// Device-local state for one four-round Pomodoro cycle. Its selected targets
/// stay fixed for the cycle so future monitor callbacks can enforce them even
/// when the app process is not running.
struct PomodoroCycleRecord: nonisolated Codable, nonisolated Equatable, Sendable {
    let id: UUID
    let plan: PomodoroCyclePlan
    var selection: FamilyActivitySelection
    var websiteDomains: [String]
    let isStrict: Bool
    let roundSessionIDs: [UUID]

    init(
        id: UUID = UUID(),
        plan: PomodoroCyclePlan,
        selection: FamilyActivitySelection,
        websiteDomains: [String],
        isStrict: Bool,
        firstSessionID: UUID
    ) {
        self.id = id
        self.plan = plan
        self.selection = selection
        self.websiteDomains = websiteDomains
        self.isStrict = isStrict
        self.roundSessionIDs = [firstSessionID] + (2...PomodoroCyclePlan.roundCount).map { _ in UUID() }
    }

    func session(for round: Int) -> ActiveSessionRecord? {
        guard let interval = plan.workInterval(round: round),
              roundSessionIDs.indices.contains(round - 1) else { return nil }
        return ActiveSessionRecord(
            id: roundSessionIDs[round - 1],
            startedAt: interval.start,
            plannedEndAt: interval.end,
            plannedDurationSeconds: plan.workMinutes * 60,
            outcome: .active,
            isStrict: isStrict
        )
    }

    func verifiedCompletedSessions(
        asOf date: Date,
        enforcedAt: (Int) -> Date?
    ) -> [ActiveSessionRecord] {
        (1...PomodoroCyclePlan.roundCount).compactMap { round in
            guard let interval = plan.workInterval(round: round),
                  interval.end <= date,
                  let appliedAt = enforcedAt(round),
                  var session = session(for: round) else { return nil }
            session.outcome = .completed
            session.actualDurationSeconds = session.plannedDurationSeconds
            session.lastRestrictionApplicationAt = appliedAt
            return session
        }
    }
}
