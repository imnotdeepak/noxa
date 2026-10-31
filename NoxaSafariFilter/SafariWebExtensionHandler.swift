import Foundation
import SafariServices

/// Answers each content script: filter this page only when its site's
/// choice is on and paid access hasn't expired. Records when each site last
/// connected, so the app can show whether the filter is reaching Safari.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
        let message = (context.inputItems.first as? NSExtensionItem)?
            .userInfo?[SFExtensionMessageKey] as? [String: Any]
        let host = message?["host"] as? String ?? ""
        let allowedUntil = defaults?.object(forKey: "noxa.safariFilterAllowedUntil") as? Date
        let isPaid = allowedUntil.map { $0 > Date() } ?? false

        let enabled: Bool
        let lastSeenKey: String?
        switch message?["type"] as? String {
        case "noxa.instagram.filterState":
            enabled = isPaid
                && defaults?.bool(forKey: "noxa.safariFilterEnabled") == true
                && ["instagram.com", "www.instagram.com"].contains(host)
            lastSeenKey = "noxa.safariFilterLastSeenAt"
        case "noxa.youtube.filterState":
            enabled = isPaid
                && defaults?.bool(forKey: "noxa.youtubeShortsHidden") == true
                && ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host)
            lastSeenKey = "noxa.youtubeFilterLastSeenAt"
        default:
            enabled = false
            lastSeenKey = nil
        }
        if enabled, let lastSeenKey {
            defaults?.set(Date(), forKey: lastSeenKey)
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["enabled": enabled]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
