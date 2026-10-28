import FamilyControls
import Foundation
import Testing
@testable import Noxa

@MainActor struct InstagramSiteModeTests {
    @Test func siteModeChoicesPersist() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.InstagramSite.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        store.setSafariFilterEnabled(true)
        #expect(store.instagramSiteMode == .distractionFree)

        store.setInstagramSiteMode(.off)
        #expect(!store.isSafariFilterEnabled)
        #expect(!store.instagramAppBlockEnabled)

        store.clearInstagramSiteMode()
        #expect(store.instagramSiteMode == .off)
    }

    @Test func savedFullBlockChoiceBecomesOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.InstagramSite.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        defaults.set("fullBlock", forKey: "noxa.instagramSiteMode")
        // Even if the old Safari flag was left on, the removed mode is Off.
        store.setSafariFilterEnabled(true)
        #expect(store.instagramSiteMode == .off)
        #expect(InstagramSiteMode.allCases == [.off, .distractionFree])
    }
}

@MainActor struct InstagramAppBlockTests {
    @Test func appBlockFollowsTheSafariFilterModeAndPaidAccess() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let paid = now.addingTimeInterval(60)
        let chosen = FamilyActivitySelection()

        // An empty selection (nothing picked yet) never blocks.
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: paid, appSelection: chosen, now: now
        ))
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: paid, appSelection: nil, now: now
        ))
        // Off and expired access leave the app alone.
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .off, isEnabled: true, allowedUntil: paid, appSelection: chosen, now: now
        ))
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: now.addingTimeInterval(-1), appSelection: chosen, now: now
        ))
    }

    @Test func chosenInstagramAppPersistsAndClears() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.InstagramApp.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        store.setInstagramSiteMode(.distractionFree)
        store.setInstagramAppBlockEnabled(true)
        #expect(store.instagramAppBlockEnabled)
        #expect(try store.loadInstagramAppSelection() == nil)
        try store.saveInstagramAppSelection(FamilyActivitySelection())
        #expect(try store.loadInstagramAppSelection() == FamilyActivitySelection())
        store.clearInstagramAppSelection()
        #expect(try store.loadInstagramAppSelection() == nil)
        store.setInstagramSiteMode(.off)
        #expect(!store.instagramAppBlockEnabled)
    }
}
