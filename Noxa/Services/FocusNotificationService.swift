import Combine
import Foundation
import UserNotifications

@MainActor
final class FocusNotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        Task { await refreshAuthorizationStatus() }
    }

    var canSchedule: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
        #if DEBUG
        UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.set(
            authorizationStatus.rawValue,
            forKey: "noxa.debug.notificationAuthorizationStatus"
        )
        #endif
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func schedule(for session: ActiveSessionRecord) async {
        await refreshAuthorizationStatus()
        guard canSchedule else { return }

        cancel(for: session.id)
        let now = Date()

        if session.plannedEndAt.timeIntervalSince(now) > 300 {
            let warning = UNMutableNotificationContent()
            warning.title = "5 minutes left"
            warning.body = "Your focus session is almost complete."
            warning.sound = .default
            await add(
                content: warning,
                date: session.plannedEndAt.addingTimeInterval(-300),
                identifier: warningIdentifier(for: session.id)
            )
        }

        let completion = UNMutableNotificationContent()
        completion.title = "Focus session complete"
        completion.body = "Great work. Take a moment to notice what you accomplished."
        completion.sound = .default
        await add(
            content: completion,
            date: session.plannedEndAt,
            identifier: completionIdentifier(for: session.id)
        )
    }

    func schedulePomodoroCycle(_ cycle: PomodoroCycleRecord) async {
        await refreshAuthorizationStatus()
        guard canSchedule else { return }
        cancelPomodoroCycle(cycle.id)

        for round in 1...PomodoroCyclePlan.roundCount {
            guard let interval = cycle.plan.workInterval(round: round) else { continue }
            let workComplete = UNMutableNotificationContent()
            workComplete.title = round == PomodoroCyclePlan.roundCount
                ? "Four focus rounds complete"
                : "Focus round \(round) complete"
            workComplete.body = round == PomodoroCyclePlan.roundCount
                ? "Your Pomodoro cycle is over. Would you like to start another one?"
                : "Your apps are available for a \(cycle.plan.breakMinutes)-minute break."
            workComplete.sound = .default
            await add(
                content: workComplete,
                date: interval.end,
                identifier: cycleNotificationIdentifier(cycle.id, round: round, kind: "work-end")
            )

            guard round < PomodoroCyclePlan.roundCount else { continue }
            let timing = PomodoroBreakTiming(
                workEndsAt: interval.end,
                breakMinutes: cycle.plan.breakMinutes
            )
            let halfway = UNMutableNotificationContent()
            halfway.title = "Halfway through your break"
            halfway.body = "Round \(round + 1) starts after your break."
            halfway.sound = .default
            await add(
                content: halfway,
                date: timing.halfwayAt,
                identifier: cycleNotificationIdentifier(cycle.id, round: round, kind: "break-halfway")
            )

            let warning = UNMutableNotificationContent()
            warning.title = "1 minute left in your break"
            warning.body = "Round \(round + 1) starts automatically in one minute."
            warning.sound = .default
            await add(
                content: warning,
                date: timing.oneMinuteRemainingAt,
                identifier: cycleNotificationIdentifier(cycle.id, round: round, kind: "break-warning")
            )

            let nextRound = UNMutableNotificationContent()
            nextRound.title = "Focus round \(round + 1) started"
            nextRound.body = "Your next focus interval is scheduled."
            nextRound.sound = .default
            await add(
                content: nextRound,
                date: timing.endsAt,
                identifier: cycleNotificationIdentifier(cycle.id, round: round, kind: "break-end")
            )
        }
    }

    func cancelPomodoroCycle(_ cycleID: UUID) {
        let identifiers = (1...PomodoroCyclePlan.roundCount).flatMap { round in
            ["work-end", "break-halfway", "break-warning", "break-end"].map { kind in
                cycleNotificationIdentifier(cycleID, round: round, kind: kind)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancel(for sessionID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            warningIdentifier(for: sessionID),
            completionIdentifier(for: sessionID),
            breakHalfwayIdentifier(for: sessionID),
            breakWarningIdentifier(for: sessionID),
            breakIdentifier(for: sessionID)
        ])
    }

    private func add(content: UNNotificationContent, date: Date, identifier: String) async {
        let delay = date.timeIntervalSinceNow
        guard delay > 1 else { return }
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        try? await center.add(request)
    }

    private func warningIdentifier(for sessionID: UUID) -> String {
        "noxa.focus.\(sessionID.uuidString).warning"
    }

    private func completionIdentifier(for sessionID: UUID) -> String {
        "noxa.focus.\(sessionID.uuidString).complete"
    }

    private func breakIdentifier(for sessionID: UUID) -> String {
        "noxa.focus.\(sessionID.uuidString).break-complete"
    }

    private func breakHalfwayIdentifier(for sessionID: UUID) -> String {
        "noxa.focus.\(sessionID.uuidString).break-halfway"
    }

    private func breakWarningIdentifier(for sessionID: UUID) -> String {
        "noxa.focus.\(sessionID.uuidString).break-warning"
    }

    private func cycleNotificationIdentifier(_ cycleID: UUID, round: Int, kind: String) -> String {
        "noxa.pomodoro.\(cycleID.uuidString).\(round).\(kind)"
    }
}
