import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
        let message = (context.inputItems.first as? NSExtensionItem)?
            .userInfo?[SFExtensionMessageKey] as? [String: Any]
        let isInstagramPage = ["instagram.com", "www.instagram.com"]
            .contains(message?["host"] as? String ?? "")
        let allowedUntil = defaults?.object(forKey: "noxa.safariFilterAllowedUntil") as? Date
        let enabled = defaults?.bool(forKey: "noxa.safariFilterEnabled") == true
            && message?["type"] as? String == "noxa.instagram.filterState"
            && isInstagramPage
            && (allowedUntil.map { $0 > Date() } ?? false)
        if enabled {
            defaults?.set(Date(), forKey: "noxa.safariFilterLastSeenAt")
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["enabled": enabled]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
