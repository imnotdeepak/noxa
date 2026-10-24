import Foundation
import ManagedSettings

/// Owns only Instagram's optional whole-website block. Other website rules
/// retain their separate Managed Settings stores.
@MainActor
enum InstagramSiteProtectionService {
    private static let settings = ManagedSettingsStore(
        named: ManagedSettingsStore.Name("noxa.instagram.full-block")
    )

    static var isFullBlockApplied: Bool {
        settings.webContent.blockedByFilter != nil
    }

    static func shouldApplyFullBlock(
        mode: InstagramSiteMode,
        allowedUntil: Date?,
        now: Date = Date()
    ) -> Bool {
        mode == .fullBlock && (allowedUntil.map { $0 > now } ?? false)
    }

    static func reconcile(store: AppGroupStore? = nil, now: Date = Date()) {
        let store = store ?? .shared
        guard shouldApplyFullBlock(
            mode: store.instagramSiteMode,
            allowedUntil: store.safariFilterAllowedUntil,
            now: now
        ) else {
            settings.webContent.blockedByFilter = nil
            return
        }
        settings.webContent.blockedByFilter = .specific([
            WebDomain(domain: "instagram.com"),
            WebDomain(domain: "www.instagram.com")
        ])
    }
}
