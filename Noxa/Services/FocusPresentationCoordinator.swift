import ActivityKit
import Foundation
import Supabase
import WidgetKit

/// Keeps the glanceable surfaces aligned with the persisted focus session.
/// ActivityKit presentation is optional; the Screen Time session never depends on it.
@MainActor
enum FocusPresentationCoordinator {
    private static var endTask: Task<Void, Never>?
    private static var pushTokenTask: Task<Void, Never>?

    static func reconcile(session: ActiveSessionRecord?) async {
        WidgetCenter.shared.reloadTimelines(ofKind: "NoxaFocusWidget")
        endTask?.cancel()
        pushTokenTask?.cancel()

        let current = session.flatMap { candidate -> ActiveSessionRecord? in
            candidate.outcome == .active && candidate.plannedEndAt > Date()
                ? candidate : nil
        }

        for activity in Activity<FocusActivityAttributes>.activities {
            if activity.attributes.sessionID != current?.id {
                await activity.end(nil, dismissalPolicy: .immediate)
                Task { await removeRemoteEnd(for: activity.attributes.sessionID) }
            }
        }

        guard let current else { return }
        var presentedActivity = Activity<FocusActivityAttributes>.activities.first(where: {
            $0.attributes.sessionID == current.id
        })
        if ActivityAuthorizationInfo().areActivitiesEnabled,
           presentedActivity == nil {
            let attributes = FocusActivityAttributes(
                sessionID: current.id,
                isStrict: current.isStrict
            )
            let content = ActivityContent(
                state: FocusActivityAttributes.ContentState(
                    startedAt: current.startedAt,
                    plannedEndAt: current.plannedEndAt
                ),
                staleDate: current.plannedEndAt
            )
            do {
                presentedActivity = try Activity<FocusActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: .token
                )
            } catch {
                // Keep the local timer available if push setup is unavailable.
                presentedActivity = try? Activity<FocusActivityAttributes>.request(
                    attributes: attributes,
                    content: content
                )
            }
        }

        if let presentedActivity {
            pushTokenTask = Task {
                if let token = presentedActivity.pushToken {
                    await registerRemoteEnd(for: current, token: token)
                }
                for await token in presentedActivity.pushTokenUpdates {
                    guard !Task.isCancelled else { break }
                    await registerRemoteEnd(for: current, token: token)
                }
            }
        }

        endTask = Task {
            let remaining = max(0, current.plannedEndAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await reconcile(session: nil)
        }
    }

    private struct RemoteEndRequest: Encodable {
        let action: String
        let sessionID: UUID
        let pushToken: String?
        let environment: String?
        let startedAt: String?
        let plannedEndAt: String?
    }

    private static func registerRemoteEnd(for session: ActiveSessionRecord, token: Data) async {
        guard session.plannedEndAt > Date() else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let request = RemoteEndRequest(
            action: "register",
            sessionID: session.id,
            pushToken: token.map { String(format: "%02x", $0) }.joined(),
            environment: {
                #if DEBUG
                return "sandbox"
                #else
                return "production"
                #endif
            }(),
            startedAt: formatter.string(from: session.startedAt),
            plannedEndAt: formatter.string(from: session.plannedEndAt)
        )
        try? await SupabaseProvider.client.functions.invoke(
            "focus-live-activity", options: .init(body: request)
        )
    }

    private static func removeRemoteEnd(for sessionID: UUID) async {
        let request = RemoteEndRequest(
            action: "remove", sessionID: sessionID, pushToken: nil,
            environment: nil, startedAt: nil, plannedEndAt: nil
        )
        try? await SupabaseProvider.client.functions.invoke(
            "focus-live-activity", options: .init(body: request)
        )
    }
}
