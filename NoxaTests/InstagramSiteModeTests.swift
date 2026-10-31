import FamilyControls
import Foundation
import ManagedSettings
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
        let paid = now.addingTimeInterval(3_600)
        let chosen = FamilyActivitySelection()

        // Nothing picked yet still blocks, by Instagram's app ID.
        #expect(InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: paid, appSelection: chosen, now: now
        ))
        #expect(InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: paid, appSelection: nil, now: now
        ))
        // Released 15 minutes before paid access ends.
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: now.addingTimeInterval(60), appSelection: nil, now: now
        ))
        // Off and expired access leave the app alone.
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .off, isEnabled: true, allowedUntil: paid, appSelection: chosen, now: now
        ))
        #expect(!InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: now.addingTimeInterval(-1), appSelection: chosen, now: now
        ))
    }

    @Test func hidingReelsAlsoBlocksTheApp() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.InstagramAuto.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        store.setInstagramSiteMode(.distractionFree)
        #expect(store.instagramAppBlockEnabled)
        store.setInstagramSiteMode(.off)
        #expect(!store.instagramAppBlockEnabled)
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

@MainActor struct YouTubeShortsTests {
    @Test func hidingShortsAlsoBlocksTheAppAndClears() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.YouTube.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        #expect(!store.youtubeShortsHidden)

        store.setYouTubeShortsHidden(true)
        #expect(store.youtubeShortsHidden)
        #expect(store.youtubeAppBlockEnabled)
        // The Safari handler reads this exact key.
        #expect(defaults.bool(forKey: "noxa.youtubeShortsHidden"))

        store.clearYouTubeShorts()
        #expect(!store.youtubeShortsHidden)
        #expect(!store.youtubeAppBlockEnabled)
    }

    @Test func appBlockNeedsShortsHiddenOneAppAndPaidAccess() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let paid = now.addingTimeInterval(3_600)
        let empty = FamilyActivitySelection()
        // Nothing picked still blocks, by YouTube's app ID.
        #expect(YouTubeShortsProtectionService.shouldApplyAppBlock(
            shortsHidden: true, isEnabled: true, allowedUntil: paid, appSelection: nil, now: now
        ))
        #expect(YouTubeShortsProtectionService.shouldApplyAppBlock(
            shortsHidden: true, isEnabled: true, allowedUntil: paid, appSelection: empty, now: now
        ))
        #expect(YouTubeShortsProtectionService.blockedApps(for: nil)
            == [Application(bundleIdentifier: "com.google.ios.youtube")])
        #expect(!YouTubeShortsProtectionService.shouldApplyAppBlock(
            shortsHidden: false, isEnabled: true, allowedUntil: paid, appSelection: empty, now: now
        ))
        // Released 15 minutes ahead of paid access ending.
        #expect(!YouTubeShortsProtectionService.shouldApplyAppBlock(
            shortsHidden: true, isEnabled: true, allowedUntil: now.addingTimeInterval(600), appSelection: empty, now: now
        ))
    }
}

@MainActor struct ShortVideoFilterLockTests {
    @Test func turningOnStartsAWeekAndTurningOffClearsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.FilterLock.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        #expect(store.instagramLockAnchor == nil)
        store.setInstagramSiteMode(.distractionFree)
        let anchor = try #require(store.instagramLockAnchor)
        // Saving the same choice again doesn't restart the week.
        store.setInstagramSiteMode(.distractionFree)
        #expect(store.instagramLockAnchor == anchor)
        store.setInstagramSiteMode(.off)
        #expect(store.instagramLockAnchor == nil)

        store.setYouTubeShortsHidden(true)
        #expect(store.youtubeLockAnchor != nil)
        store.clearYouTubeShorts()
        #expect(store.youtubeLockAnchor == nil)
    }

    @Test func filtersAlreadyOnStartTheirWeekOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.FilterLock.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        defaults.set("distractionFree", forKey: "noxa.instagramSiteMode")
        defaults.set(true, forKey: "noxa.youtubeShortsHidden")
        let now = Date()
        store.startMissingFilterLocks(at: now)
        #expect(store.instagramLockAnchor == now)
        #expect(store.youtubeLockAnchor == now)
        store.startMissingFilterLocks(at: now.addingTimeInterval(60))
        #expect(store.instagramLockAnchor == now)
    }

    @Test func instagramBlocksByAppIDWithoutAPick() {
        let paid = Date().addingTimeInterval(3_600)
        #expect(InstagramSiteProtectionService.shouldApplyAppBlock(
            mode: .distractionFree, isEnabled: true, allowedUntil: paid, appSelection: nil
        ))
        #expect(InstagramSiteProtectionService.blockedApps(for: nil)
            == [Application(bundleIdentifier: "com.burbn.instagram")])
    }
}
