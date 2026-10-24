import Foundation
import Testing
@testable import Noxa

@MainActor struct InstagramSiteModeTests {
    @Test func legacySelectiveChoiceMigratesAndFullBlockExpires() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.InstagramSite.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        store.setSafariFilterEnabled(true)
        #expect(store.instagramSiteMode == .distractionFree)

        store.setInstagramSiteMode(.fullBlock)
        #expect(store.instagramSiteMode == .fullBlock)
        #expect(!store.isSafariFilterEnabled)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.setSafariFilterAllowedUntil(now.addingTimeInterval(60))
        #expect(InstagramSiteProtectionService.shouldApplyFullBlock(
            mode: store.instagramSiteMode,
            allowedUntil: store.safariFilterAllowedUntil,
            now: now
        ))
        #expect(!InstagramSiteProtectionService.shouldApplyFullBlock(
            mode: store.instagramSiteMode,
            allowedUntil: store.safariFilterAllowedUntil,
            now: now.addingTimeInterval(61)
        ))

        store.clearInstagramSiteMode()
        #expect(store.instagramSiteMode == .off)
    }
}
