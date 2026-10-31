import Foundation
import Testing
@testable import Noxa

struct AnalyticsEventTests {
    @Test func limitAndScheduleEventsCarryBucketsNotDetails() {
        let added = AnalyticsEvent.dailyLimitAdded(minutes: 45, appCount: 2)
        #expect(added.name == "daily_limit_added")
        #expect(added.properties["allowance_bucket"] as? String == "30_59")
        #expect(added.properties["app_count"] as? Int == 2)

        let schedule = AnalyticsEvent.scheduleCreated(blockMinutes: 90, dayCount: 5)
        #expect(schedule.properties["block_length_bucket"] as? String == "60_119")
        #expect(schedule.properties["day_count"] as? Int == 5)
        #expect(Set(schedule.properties.keys) == ["block_length_bucket", "day_count"])
    }

    @Test func lockStatesHaveStableNames() {
        let end = Date()
        #expect(AnalyticsEvent.lockStateName(.locked(until: end)) == "locked")
        #expect(AnalyticsEvent.lockStateName(.changeWindow(until: end)) == "change_window")
        #expect(AnalyticsEvent.lockStateName(.unlocked) == "unlocked")
    }

    @Test func websiteEventsSendCountsOnly() {
        let added = AnalyticsEvent.blockedWebsiteAdded(totalCount: 3)
        #expect(Set(added.properties.keys) == ["total_count"])
        let filter = AnalyticsEvent.shortVideoFilterChanged(site: "youtube", on: true)
        #expect(filter.properties["site"] as? String == "youtube")
        #expect(filter.properties["on"] as? Bool == true)
    }
}

@MainActor struct AnalyticsConsentTests {
    @Test func offUntilTheUserAgrees() throws {
        let fresh = try #require(UserDefaults(suiteName: "NoxaTests.Analytics.\(UUID())"))
        #expect(!AnalyticsService(defaults: fresh).isEnabled)

        let agreed = try #require(UserDefaults(suiteName: "NoxaTests.Analytics.\(UUID())"))
        agreed.set(true, forKey: "analyticsConsentEnabled")
        #expect(AnalyticsService(defaults: agreed).isEnabled)
    }
}

struct RevenueCatPostHogLinkTests {
    @Test func linkedOnlyWhileSharingAnalytics() {
        #expect(SubscriptionService.postHogLinkValue(accountID: "abc", analyticsEnabled: true) == "abc")
        // An empty value removes the attribute in RevenueCat.
        #expect(SubscriptionService.postHogLinkValue(accountID: "abc", analyticsEnabled: false) == "")
    }
}
