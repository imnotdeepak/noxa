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

    func schedulePomodoro(for session: ActiveSessionRecord, breakMinutes: Int) async {
        await refreshAuthorizationStatus()
        guard canSchedule else { return }

        cancel(for: session.id)
        let breakTiming = PomodoroBreakTiming(
            workEndsAt: session.plannedEndAt,
            breakMinutes: breakMinutes
        )
        let focusComplete = UNMutableNotificationContent()
        focusComplete.title = "Focus interval complete"
        focusComplete.body = "Your apps are available. Take a \(breakMinutes)-minute break."
        focusComplete.sound = .default
        await add(
            content: focusComplete,
            date: breakTiming.startsAt,
            identifier: completionIdentifier(for: session.id)
        )

        let halfway = UNMutableNotificationContent()
        halfway.title = "Halfway through your break"
        halfway.body = "Take a moment to recharge before your next focus interval."
        halfway.sound = .default
        await add(
            content: halfway,
            date: breakTiming.halfwayAt,
            identifier: breakHalfwayIdentifier(for: session.id)
        )

        let almostOver = UNMutableNotificationContent()
        almostOver.title = "1 minute left in your break"
        almostOver.body = "Your next focus interval is coming up."
        almostOver.sound = .default
        await add(
            content: almostOver,
            date: breakTiming.oneMinuteRemainingAt,
            identifier: breakWarningIdentifier(for: session.id)
        )

        let breakComplete = UNMutableNotificationContent()
        breakComplete.title = "Break complete"
        breakComplete.body = "Ready for another Pomodoro? Open Noxa when you’re ready to begin."
        breakComplete.sound = .default
        await add(
            content: breakComplete,
            date: breakTiming.endsAt,
            identifier: breakIdentifier(for: session.id)
        )
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
        let delay = max(1, date.timeIntervalSinceNow)
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
}
