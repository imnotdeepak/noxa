import Combine
import Foundation

@MainActor
final class FocusLaunchRouter: ObservableObject {
    @Published private(set) var hasPendingStart = false
    @Published private(set) var hasPendingHome = false

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "noxa", url.host == "focus" else {
            return false
        }
        switch url.path {
        case "/start":
            hasPendingStart = true
            return true
        case "/active":
            hasPendingHome = true
            return true
        default:
            return false
        }
    }

    func consumeStart() {
        hasPendingStart = false
    }

    func consumeHome() {
        hasPendingHome = false
    }
}
