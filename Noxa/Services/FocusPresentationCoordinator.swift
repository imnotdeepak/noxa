import ActivityKit
import Foundation
import WidgetKit

/// Keeps the glanceable surfaces aligned with the persisted focus session.
/// ActivityKit presentation is optional; the Screen Time session never depends on it.
@MainActor
enum FocusPresentationCoordinator {
    private static var endTask: Task<Void, Never>?

    static func reconcile(session: ActiveSessionRecord?) async {
        WidgetCenter.shared.reloadTimelines(ofKind: "NoxaFocusWidget")
        endTask?.cancel()

        let current = session.flatMap { candidate -> ActiveSessionRecord? in
            candidate.outcome == .active && candidate.plannedEndAt > Date()
                ? candidate : nil
        }

        for activity in Activity<FocusActivityAttributes>.activities {
            if activity.attributes.sessionID != current?.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard let current else { return }
        if ActivityAuthorizationInfo().areActivitiesEnabled,
           !Activity<FocusActivityAttributes>.activities.contains(where: {
               $0.attributes.sessionID == current.id
           }) {
            do {
                _ = try Activity<FocusActivityAttributes>.request(
                    attributes: FocusActivityAttributes(
                        sessionID: current.id,
                        isStrict: current.isStrict
                    ),
                    content: ActivityContent(
                        state: .init(
                            startedAt: current.startedAt,
                            plannedEndAt: current.plannedEndAt
                        ),
                        staleDate: current.plannedEndAt
                    )
                )
            } catch {
                // A presentation failure must not change restriction enforcement.
            }
        }

        endTask = Task {
            let remaining = max(0, current.plannedEndAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await reconcile(session: nil)
        }
    }
}
