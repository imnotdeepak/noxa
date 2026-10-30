import Foundation

/// A milestone earned from real history: time blocked in Focus, completed
/// sessions, the longest daily streak, days focused, or two-hour sessions.
/// Nothing is placeholder.
struct FocusMilestone: Identifiable, Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case focusTime = "Time blocked"
        case sessions = "Sessions completed"
        case streak = "Streaks"
        case focusedDays = "Days focused"
        case longSessions = "Long sessions"

        var systemImage: String {
            switch self {
            case .focusTime: "hourglass"
            case .sessions: "checkmark.seal"
            case .streak: "flame"
            case .focusedDays: "calendar"
            case .longSessions: "mountain.2"
            }
        }
    }

    let category: Category
    let title: String
    /// What earning it takes, e.g. "Block distractions for 10 hours".
    let goal: String
    let current: Double
    let target: Double

    var id: String { "\(category.rawValue)-\(Int(target))" }
    var isEarned: Bool { current >= target }

    /// Whole-number progress, capped at 100 and never rounded up to 100
    /// before the milestone is actually earned.
    var percent: Int {
        guard target > 0 else { return 0 }
        let value = Int((current / target * 100).rounded(.down))
        return isEarned ? 100 : min(value, 99)
    }

    static let focusHourTargets = [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
    static let sessionTargets = [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
    static let streakTargets = [3, 7, 14, 30, 60, 100, 180, 365]
    static let focusedDayTargets = [1, 7, 30, 50, 100, 200, 365, 500, 1_000]
    /// Completed sessions of at least `longSessionMinutes`.
    static let longSessionTargets = [1, 5, 10, 25, 50, 100, 250]
    static let longSessionMinutes = 120

    static func all(
        totalFocusMinutes: Int,
        completedSessions: Int,
        longestStreak: Int,
        totalFocusedDays: Int = 0,
        longSessions: Int = 0
    ) -> [FocusMilestone] {
        let hours = Double(totalFocusMinutes) / 60
        let time = focusHourTargets.map { target in
            FocusMilestone(
                category: .focusTime,
                title: target == 1 ? "1 hour blocked" : "\(target.formatted()) hours blocked",
                goal: "Block distractions for \(target == 1 ? "1 hour" : "\(target.formatted()) hours") in Focus",
                current: hours,
                target: Double(target)
            )
        }
        let sessions = sessionTargets.map { target in
            FocusMilestone(
                category: .sessions,
                title: target == 1 ? "First session" : "\(target.formatted()) sessions",
                goal: "Complete \(target == 1 ? "a Focus session" : "\(target.formatted()) Focus sessions")",
                current: Double(completedSessions),
                target: Double(target)
            )
        }
        let streaks = streakTargets.map { target in
            FocusMilestone(
                category: .streak,
                title: "\(target)-day streak",
                goal: "Complete a session \(target) days in a row",
                current: Double(longestStreak),
                target: Double(target)
            )
        }
        let days = focusedDayTargets.map { target in
            FocusMilestone(
                category: .focusedDays,
                title: target == 1 ? "First focus day" : "\(target.formatted()) focus days",
                goal: "Complete a session on \(target == 1 ? "a day" : "\(target.formatted()) different days")",
                current: Double(totalFocusedDays),
                target: Double(target)
            )
        }
        let long = longSessionTargets.map { target in
            FocusMilestone(
                category: .longSessions,
                title: target == 1 ? "First 2-hour session" : "\(target.formatted()) two-hour sessions",
                goal: "Complete \(target == 1 ? "a Focus session" : "\(target.formatted()) Focus sessions") of 2 hours or more",
                current: Double(longSessions),
                target: Double(target)
            )
        }
        return time + sessions + streaks + days + long
    }

    /// The three to feature: the closest not yet earned, by progress. If
    /// fewer than three remain, the highest earned fill the rest.
    static func featured(from milestones: [FocusMilestone]) -> [FocusMilestone] {
        let open = milestones.filter { !$0.isEarned }
            .sorted { ($0.current / $0.target, -$0.target) > ($1.current / $1.target, -$1.target) }
        let earned = milestones.filter(\.isEarned).sorted { $0.target > $1.target }
        return Array((open + earned).prefix(3))
    }
}
