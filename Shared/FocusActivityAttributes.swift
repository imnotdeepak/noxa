import ActivityKit
import Foundation

nonisolated struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let startedAt: Date
        let plannedEndAt: Date
    }

    let sessionID: UUID
    let isStrict: Bool
}
