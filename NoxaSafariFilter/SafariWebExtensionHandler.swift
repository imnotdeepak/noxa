import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
        let allowedUntil = defaults?.object(forKey: "noxa.safariFilterAllowedUntil") as? Date
        let enabled = defaults?.bool(forKey: "noxa.safariFilterEnabled") == true
            && (allowedUntil.map { $0 > Date() } ?? false)
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["enabled": enabled]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
