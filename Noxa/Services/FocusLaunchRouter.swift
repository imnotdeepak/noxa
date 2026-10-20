import Combine
import Foundation

@MainActor
final class FocusLaunchRouter: ObservableObject {
    static let shared = FocusLaunchRouter()

    @Published private(set) var hasPendingStart = false
    @Published private(set) var hasPendingHome = false

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "noxa", url.host == "focus" else {
            return false
        }
        switch url.path {
        case "/start":
            requestStart()
            return true
        case "/active":
            hasPendingHome = true
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

    func consumeHome() {
        hasPendingHome = false
    }
}
