import Combine
import Foundation

@MainActor
final class FocusLaunchRouter: ObservableObject {
    static let shared = FocusLaunchRouter()

    @Published private(set) var hasPendingStart = false
    @Published private(set) var hasPendingHome = false
    private(set) var pendingHomeDurationMinutes: Int?

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "noxa", url.host == "focus" else {
            return false
        }
        switch url.path {
        case "/start":
            requestStart()
            return true
        case "/active":
            requestHome()
            return true
        case "/home":
            requestHome(defaultDurationMinutes: 60)
            return true
        default:
            return false
        }
    }

    func requestStart() {
        hasPendingStart = true
    }

    func consumeStart() {
        hasPendingStart = false
    }

    private func requestHome(defaultDurationMinutes: Int? = nil) {
        pendingHomeDurationMinutes = defaultDurationMinutes
        hasPendingHome = true
    }

    func consumeHome() {
        hasPendingHome = false
        pendingHomeDurationMinutes = nil
    }
}
