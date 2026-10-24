import Foundation

struct PomodoroBreakTiming: Equatable {
    let startsAt: Date
    let halfwayAt: Date
    let oneMinuteRemainingAt: Date
    let endsAt: Date

    init(workEndsAt: Date, breakMinutes: Int) {
        let duration = TimeInterval(max(5, breakMinutes) * 60)
        startsAt = workEndsAt
        halfwayAt = workEndsAt.addingTimeInterval(duration / 2)
        oneMinuteRemainingAt = workEndsAt.addingTimeInterval(duration - 60)
        endsAt = workEndsAt.addingTimeInterval(duration)
    }
}
