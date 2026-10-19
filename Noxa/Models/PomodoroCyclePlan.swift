import Foundation

/// Fixed elapsed-time plan for four work intervals and three breaks. The
/// timeline can be reconstructed after the app or monitor extension restarts.
struct PomodoroCyclePlan: Codable, Equatable, Sendable {
    enum Phase: nonisolated Equatable {
        case scheduled(startsAt: Date)
        case work(round: Int, endsAt: Date)
        case breakTime(afterRound: Int, endsAt: Date)
        case complete
    }

    static let roundCount = 4

    let startedAt: Date
    let workMinutes: Int
    let breakMinutes: Int

    init(startedAt: Date, workMinutes: Int, breakMinutes: Int) {
        self.startedAt = startedAt
        self.workMinutes = min(max(workMinutes, 15), 240)
        self.breakMinutes = min(max(breakMinutes, 5), 60)
    }

    func workInterval(round: Int) -> DateInterval? {
        guard (1...Self.roundCount).contains(round) else { return nil }
        let work = TimeInterval(workMinutes * 60)
        let breakTime = TimeInterval(breakMinutes * 60)
        let start = startedAt.addingTimeInterval(TimeInterval(round - 1) * (work + breakTime))
        return DateInterval(start: start, duration: work)
    }

    func breakInterval(afterRound round: Int) -> DateInterval? {
        guard (1..<Self.roundCount).contains(round),
              let work = workInterval(round: round) else { return nil }
        return DateInterval(start: work.end, duration: TimeInterval(breakMinutes * 60))
    }

    func phase(at date: Date) -> Phase {
        if date < startedAt { return .scheduled(startsAt: startedAt) }
        for round in 1...Self.roundCount {
            guard let work = workInterval(round: round) else { continue }
            if date < work.end {
                return .work(round: round, endsAt: work.end)
            }
            if let breakTime = breakInterval(afterRound: round), date < breakTime.end {
                return .breakTime(afterRound: round, endsAt: breakTime.end)
            }
        }
        return .complete
    }
}
