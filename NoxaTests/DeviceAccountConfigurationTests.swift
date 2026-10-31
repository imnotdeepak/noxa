import FamilyControls
import Foundation
import Testing
@testable import Noxa

@MainActor struct DeviceAccountConfigurationTests {
    @Test func editableChoicesFollowTheirAccountAcrossSwitches() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DeviceAccounts.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let first = UUID()
        let second = UUID()

        try store.saveFamilyActivitySelection(FamilyActivitySelection())
        try store.saveWebsiteBlocklist(["reddit.com"])
        store.setInstagramSiteMode(.distractionFree)
        store.setYouTubeShortsHidden(true)
        store.hasOfferedScheduleSuggestion = true
        try store.bindEditableConfiguration(to: first)

        try store.bindEditableConfiguration(to: second)
        #expect(store.localConfigurationOwner == second)
        #expect(try store.loadFamilyActivitySelection() == nil)
        #expect(try store.loadWebsiteBlocklist().isEmpty)
        #expect(store.instagramSiteMode == .off)
        #expect(!store.youtubeShortsHidden)
        #expect(!store.hasOfferedScheduleSuggestion)

        try store.saveWebsiteBlocklist(["example.com"])
        try store.bindEditableConfiguration(to: first)
        #expect(store.localConfigurationOwner == first)
        #expect(try store.loadFamilyActivitySelection() != nil)
        #expect(try store.loadWebsiteBlocklist() == ["reddit.com"])
        #expect(store.instagramSiteMode == .distractionFree)
        #expect(store.youtubeShortsHidden)
        #expect(store.hasOfferedScheduleSuggestion)

        try store.bindEditableConfiguration(to: second)
        #expect(try store.loadWebsiteBlocklist() == ["example.com"])
    }

    @Test func legacyChoicesAreAssignedToTheirPreviousOwner() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DeviceAccounts.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let previous = UUID()
        let new = UUID()
        try store.saveWebsiteBlocklist(["reddit.com"])

        try store.bindEditableConfiguration(to: new, legacyOwner: previous)
        #expect(try store.loadWebsiteBlocklist().isEmpty)
        try store.bindEditableConfiguration(to: previous)
        #expect(try store.loadWebsiteBlocklist() == ["reddit.com"])
    }

    @Test func committedRulesStaySavedButOnlyTheirOwnerCanEditThem() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DeviceAccounts.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let previous = UUID()
        let new = UUID()
        let schedule = ScheduleRule(
            name: "Evening",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            startMinutes: 20 * 60,
            endMinutes: 21 * 60
        )
        let limit = DailyLimitConfiguration(
            selection: FamilyActivitySelection(),
            dailyLimitMinutes: 30
        )
        try store.saveScheduleRules([schedule])
        try store.saveDailyLimitConfigurations([limit])

        let schedules = RestrictionScheduleService(store: store)
        let limits = DailyLimitService(store: store)
        schedules.bindAccount(new, claimingUnownedRulesFor: previous)
        limits.bindAccount(new, claimingUnownedLimitsFor: previous)

        #expect(schedules.visibleConfigurations.isEmpty)
        #expect(limits.visibleConfigurations.isEmpty)
        #expect(schedules.configurations.first?.ownerUserID == previous)
        #expect(limits.configurations.first?.ownerUserID == previous)
        #expect(try store.loadScheduleRules().first?.ownerUserID == previous)
        #expect(try store.loadDailyLimitConfigurations().first?.ownerUserID == previous)

        schedules.bindAccount(previous, claimingUnownedRulesFor: nil)
        limits.bindAccount(previous, claimingUnownedLimitsFor: nil)
        #expect(schedules.visibleConfigurations.count == 1)
        #expect(limits.visibleConfigurations.count == 1)
    }

    @Test func existingCloudCacheSurvivesClearedBindingState() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DeviceAccounts.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let account = UUID()
        try store.saveCloudAccountCache(
            CloudAccountCache(websiteDomains: ["reddit.com"], focusHistory: []),
            userID: account
        )
        let cloudSync = CloudSyncService(store: store)
        let result = cloudSync.prepareLocalData(
            for: account,
            history: [],
            websiteDomains: []
        )
        #expect(result.websiteDomains == ["reddit.com"])
    }

    @Test func deletingOneAccountKeepsTheOtherAccountsSavedChoices() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DeviceAccounts.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let first = UUID()
        let second = UUID()
        try store.bindEditableConfiguration(to: first)
        try store.saveWebsiteBlocklist(["first.example"])
        try store.bindEditableConfiguration(to: second)
        try store.saveWebsiteBlocklist(["second.example"])
        try store.saveCloudAccountCache(
            CloudAccountCache(websiteDomains: ["first.example"], focusHistory: []),
            userID: first
        )
        try store.saveCloudAccountCache(
            CloudAccountCache(websiteDomains: ["second.example"], focusHistory: []),
            userID: second
        )

        store.removeEditableConfiguration(for: second)
        store.removeCloudAccountCache(userID: second)
        #expect(try store.loadWebsiteBlocklist().isEmpty)
        #expect(try store.loadCloudAccountCache(userID: second) == nil)
        try store.bindEditableConfiguration(to: first)
        #expect(try store.loadWebsiteBlocklist() == ["first.example"])
        #expect(try store.loadCloudAccountCache(userID: first)?.websiteDomains == ["first.example"])
    }

    @Test func deletionClearsActiveChoicesEvenIfAccountArchiveIsCorrupt() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DeviceAccounts.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let account = UUID()
        try store.bindEditableConfiguration(to: account)
        try store.saveWebsiteBlocklist(["private.example"])
        defaults.set(Data("corrupt".utf8), forKey: "noxa.editableConfigurationByAccount")

        store.removeEditableConfiguration(for: account)
        #expect(try store.loadWebsiteBlocklist().isEmpty)
    }
}
