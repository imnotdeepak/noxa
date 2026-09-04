//
//  NoxaTests.swift
//  NoxaTests
//
//  Created by Deepak on 9/2/26.
//

import Foundation
import DeviceActivity
import FamilyControls
import Testing
@testable import Noxa

struct NoxaTests {

    @Test @MainActor func localSnapshotRoundTripsThroughAppGroupStore() throws {
        let suiteName = "NoxaTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)
        let session = ActiveSessionRecord(
            plannedEndAt: Date(timeIntervalSince1970: 1_700_000_000),
            plannedDurationSeconds: 1_500
        )
        var snapshot = NoxaLocalSnapshot()
        snapshot.sessionEngineState = .starting
        snapshot.activeSession = session
        snapshot.sessionHistory = [session]
        snapshot.onboarding.hasSeenWelcome = true

        try store.saveSnapshot(snapshot)

        #expect(try store.loadSnapshot() == snapshot)
        store.clearSnapshot()
        #expect(try store.loadSnapshot() == nil)
    }

    @Test func sessionsStartPendingAndDoNotAllowPartialStartOutcome() {
        let session = ActiveSessionRecord(
            plannedEndAt: Date(timeIntervalSince1970: 1_700_000_000),
            plannedDurationSeconds: 300
        )

        #expect(session.outcome == .startPending)
        #expect(SessionOutcome.failedToStart.rawValue == "failed_to_start")
    }

    @Test func endedEarlySessionCanStoreMeasuredDuration() {
        let session = ActiveSessionRecord(
            plannedEndAt: Date(timeIntervalSince1970: 1_700_001_500),
            plannedDurationSeconds: 1_500,
            outcome: .endedEarly,
            actualDurationSeconds: 120
        )

        #expect(session.actualDurationSeconds == 120)
    }

    @Test func endedEarlySessionDoesNotCountAsCompletedFocusStatistics() {
        #expect(!SessionOutcome.endedEarly.countsTowardFocusStatistics)
        #expect(SessionOutcome.completed.countsTowardFocusStatistics)
        #expect(SessionOutcome.recoveredStale.countsTowardFocusStatistics)
    }

    @Test @MainActor func measuredSessionDurationClampsToValidRange() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(FocusSessionService.measuredDurationSeconds(
            startedAt: start,
            endedAt: start.addingTimeInterval(120),
            plannedDurationSeconds: 1_500
        ) == 120)
        #expect(FocusSessionService.measuredDurationSeconds(
            startedAt: start,
            endedAt: start.addingTimeInterval(2_000),
            plannedDurationSeconds: 1_500
        ) == 1_500)
        #expect(FocusSessionService.measuredDurationSeconds(
            startedAt: start,
            endedAt: start.addingTimeInterval(-10),
            plannedDurationSeconds: 1_500
        ) == 0)
    }

    @Test @MainActor func focusSessionDurationStaysWithinDeviceActivityBounds() {
        #expect(FocusSessionService.normalizedDurationMinutes(1) == 15)
        #expect(FocusSessionService.normalizedDurationMinutes(45) == 45)
        #expect(FocusSessionService.normalizedDurationMinutes(600) == 480)
    }

    @Test @MainActor func focusSessionRestrictionsRoundTripThroughAppGroupStore() throws {
        let suiteName = "NoxaTests.FocusRestrictions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)
        let configuration = FocusSessionRestrictionConfiguration(
            selection: FamilyActivitySelection(),
            websiteDomains: ["reddit.com", "news.ycombinator.com"]
        )

        try store.saveFocusSessionRestrictions(configuration)

        #expect(try store.loadFocusSessionRestrictions() == configuration)
        store.clearFocusSessionRestrictions()
        #expect(try store.loadFocusSessionRestrictions() == nil)
    }

    @Test @MainActor func blocklistEditsAreRejectedDuringAnActiveFocusSession() throws {
        let suiteName = "NoxaTests.FocusLock.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)
        var snapshot = NoxaLocalSnapshot()
        snapshot.activeSession = ActiveSessionRecord(
            plannedEndAt: Date().addingTimeInterval(900),
            plannedDurationSeconds: 900,
            outcome: .active
        )
        try store.saveSnapshot(snapshot)

        let websites = WebsiteBlocklistService(store: store)

        #expect(!websites.addDomain("reddit.com"))
        #expect(websites.domains.isEmpty)
        #expect(websites.errorMessage == "Blocklist changes are locked until the focus session ends.")
    }

    @Test @MainActor func interruptedPendingSessionReleasesFocusLock() throws {
        let suiteName = "NoxaTests.PendingFocus.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)
        let session = ActiveSessionRecord(
            plannedEndAt: Date().addingTimeInterval(900),
            plannedDurationSeconds: 900
        )
        var snapshot = NoxaLocalSnapshot(sessionEngineState: .starting)
        snapshot.activeSession = session
        try store.saveSnapshot(snapshot)
        try store.saveFocusSessionRestrictions(
            FocusSessionRestrictionConfiguration(selection: FamilyActivitySelection())
        )

        let service = FocusSessionService(store: store)
        #expect(store.hasActiveFocusSession())

        service.reconcile()

        #expect(service.activeSession == nil)
        #expect(!store.hasActiveFocusSession())
        #expect(try store.loadFocusSessionRestrictions() == nil)
        #expect(service.history.first?.outcome == .failedToStart)
    }

    @Test @MainActor func recoveredSessionCountsTowardStatisticsAndSurvivesReconcile() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.History.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let session = ActiveSessionRecord(
            plannedEndAt: Date(timeIntervalSince1970: 1_700_001_500),
            plannedDurationSeconds: 1_500,
            outcome: .recoveredStale,
            actualDurationSeconds: 1_500
        )
        var snapshot = NoxaLocalSnapshot()
        snapshot.sessionHistory = [session]
        try store.saveSnapshot(snapshot)

        let service = FocusSessionService(store: store)
        service.reconcile()

        #expect(service.history == [session])
        #expect(service.completedSessionCount == 1)
        #expect(service.completedFocusMinutes == 25)
        store.clearSnapshot()
    }

    @Test func focusStatisticsCalculateWeeklyProgressStreaksAndAbandonment() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 4, hour: 12
        )))

        func session(daysAgo: Int, outcome: SessionOutcome, minutes: Int) throws -> ActiveSessionRecord {
            let start = try #require(calendar.date(byAdding: .day, value: -daysAgo, to: now))
            return ActiveSessionRecord(
                startedAt: start,
                plannedEndAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                plannedDurationSeconds: minutes * 60,
                outcome: outcome,
                actualDurationSeconds: minutes * 60
            )
        }

        let history = try [
            session(daysAgo: 0, outcome: .completed, minutes: 25),
            session(daysAgo: 1, outcome: .completed, minutes: 20),
            session(daysAgo: 2, outcome: .recoveredStale, minutes: 15),
            session(daysAgo: 3, outcome: .endedEarly, minutes: 5),
            session(daysAgo: 10, outcome: .completed, minutes: 30),
            session(daysAgo: 11, outcome: .interrupted, minutes: 2),
            session(daysAgo: 12, outcome: .failedToStart, minutes: 0)
        ]

        let statistics = FocusStatistics(history: history, now: now, calendar: calendar)

        #expect(statistics.completedSessions == 4)
        #expect(statistics.abandonedSessions == 2)
        #expect(statistics.totalFocusMinutes == 90)
        #expect(statistics.weeklyFocusMinutes == 60)
        #expect(statistics.currentStreak == 3)
        #expect(statistics.longestStreak == 3)
        #expect(statistics.completionRate == 67)
    }

    @Test @MainActor func onboardingMilestonesPersistAcrossServiceInstances() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.Onboarding.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let firstService = OnboardingService(store: store)

        firstService.markWelcomeSeen()
        firstService.saveGoals(["Work", "Deep focus"])
        firstService.saveDistractions(["Web browsing"])

        let secondService = OnboardingService(store: store)
        #expect(secondService.progress.hasSeenWelcome)
        #expect(secondService.progress.hasCompletedGoals)
        #expect(secondService.progress.hasCompletedDistractions)
        #expect(secondService.progress.draftPersonalizationAnswers == ["Work", "Deep focus"])
        #expect(secondService.progress.draftSetupConfiguration["distractions"] == "Web browsing")
        store.clearSnapshot()
    }

    @Test @MainActor func onboardingCannotCompleteBeforeRequiredMilestones() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.OnboardingGate.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = OnboardingService(store: store)

        #expect(!service.completeCapabilitiesExplainer())
        #expect(!service.progress.hasSeenCapabilitiesExplainer)

        #expect(service.markWelcomeSeen())
        #expect(service.saveGoals(["Work"]))
        #expect(service.saveDistractions(["Social media"]))
        #expect(service.completeCapabilitiesExplainer())
        #expect(service.progress.hasSeenCapabilitiesExplainer)
        store.clearSnapshot()
    }

    @Test @MainActor func failedOnboardingSaveDoesNotAdvanceInMemoryProgress() {
        let service = OnboardingService(store: FailingOnboardingStore())

        #expect(!service.markWelcomeSeen())
        #expect(!service.progress.hasSeenWelcome)
        #expect(service.errorMessage != nil)
    }

    @Test func familyActivitySelectionRoundTripsThroughAppGroupStore() throws {
        let suiteName = "NoxaTests.Selection.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)
        let selection = FamilyActivitySelection()

        try store.saveFamilyActivitySelection(selection)

        #expect(try store.loadFamilyActivitySelection() == selection)
        store.clearFamilyActivitySelection()
        #expect(try store.loadFamilyActivitySelection() == nil)
    }

    @Test @MainActor
    func websiteDomainsNormalizeAndRejectInvalidInput() {
        #expect(WebsiteBlocklistService.normalize(" HTTPS://Reddit.com/r/all ") == "reddit.com")
        #expect(WebsiteBlocklistService.normalize("www.news.ycombinator.com") == "news.ycombinator.com")
        #expect(WebsiteBlocklistService.normalize("not a domain") == nil)
    }

    @Test func dailyLimitConfigurationClampsToSupportedRange() {
        let configuration = DailyLimitConfiguration(
            selection: FamilyActivitySelection(),
            dailyLimitMinutes: 500
        )

        #expect(configuration.dailyLimitMinutes == 240)
    }

    @Test func dailyLimitConfigurationEditsRetainOnlyReachedEnabledLimits() throws {
        let enabledID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let disabledID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let removedID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let enabled = DailyLimitConfiguration(
            id: enabledID,
            selection: FamilyActivitySelection(),
            dailyLimitMinutes: 30
        )
        let disabled = DailyLimitConfiguration(
            id: disabledID,
            selection: FamilyActivitySelection(),
            dailyLimitMinutes: 30,
            isEnabled: false
        )
        let reached = Set([
            NoxaDeviceActivityConfiguration.dailyLimitEventName(for: enabledID).rawValue,
            NoxaDeviceActivityConfiguration.dailyLimitEventName(for: disabledID).rawValue,
            NoxaDeviceActivityConfiguration.dailyLimitEventName(for: removedID).rawValue
        ])

        let retained = NoxaDeviceActivityConfiguration.retainedDailyLimitEventNames(
            configurations: [enabled, disabled],
            reachedEventNames: reached
        )

        #expect(retained == [
            NoxaDeviceActivityConfiguration.dailyLimitEventName(for: enabledID).rawValue
        ])
    }

    @Test func authenticationInputNormalizesAndValidatesCredentials() {
        #expect(AuthenticationInputValidator.normalizedEmail("  Person@Example.COM ") == "person@example.com")
        #expect(AuthenticationInputValidator.validate(email: "person@example.com", password: "password") == nil)
        #expect(AuthenticationInputValidator.validate(email: "invalid", password: "password") != nil)
        #expect(AuthenticationInputValidator.validate(email: "person@example.com", password: "short") != nil)
    }

    @Test @MainActor func subscriptionCatalogUsesStableDistinctProductIdentifiers() {
        #expect(SubscriptionService.monthlyProductID == "com.lycheecorp.noxa.monthly")
        #expect(SubscriptionService.annualProductID == "com.lycheecorp.noxa.annual")
        #expect(SubscriptionService.productIDs.count == 2)
        #expect(Set(SubscriptionService.productIDs).count == 2)
        #expect(SubscriptionService.productIDs.contains(SubscriptionService.monthlyProductID))
        #expect(SubscriptionService.productIDs.contains(SubscriptionService.annualProductID))
    }

    @Test @MainActor func cloudSessionPayloadPreservesOutcomeAndUsesStableIdentity() throws {
        let userID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let sessionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let session = ActiveSessionRecord(
            id: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plannedEndAt: Date(timeIntervalSince1970: 1_700_001_500),
            plannedDurationSeconds: 1_500,
            outcome: .recoveredStale,
            actualDurationSeconds: 1_200
        )

        let payload = CloudFocusSessionRow(userID: userID, record: session)

        #expect(payload.id == sessionID)
        #expect(payload.userID == userID)
        #expect(payload.platform == "ios")
        #expect(payload.plannedDurationSeconds == 1_500)
        #expect(payload.actualDurationSeconds == 1_200)
        #expect(payload.outcome == .recoveredStale)
        #expect(payload.completedSuccessfully)
        #expect(payload.startTime == "2023-11-14T22:13:20Z")
        #expect(payload.localRecord() == session)
    }

    @Test func endedEarlyCloudSessionIsNotReportedAsSuccessfullyCompleted() throws {
        let userID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000012"))
        let session = ActiveSessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plannedEndAt: Date(timeIntervalSince1970: 1_700_001_500),
            plannedDurationSeconds: 1_500,
            outcome: .endedEarly,
            actualDurationSeconds: 120
        )

        let payload = CloudFocusSessionRow(userID: userID, record: session)

        #expect(payload.outcome == .endedEarly)
        #expect(!payload.completedSuccessfully)
        #expect(payload.actualDurationSeconds == 120)
    }

    @Test @MainActor func websiteMergeHydratesFreshDevicesAndPropagatesDeletions() {
        #expect(CloudSyncService.mergedDomains(
            base: nil,
            local: [],
            remote: ["reddit.com", "youtube.com"]
        ) == ["reddit.com", "youtube.com"])

        #expect(CloudSyncService.mergedDomains(
            base: ["reddit.com", "youtube.com"],
            local: ["youtube.com", "news.ycombinator.com"],
            remote: ["reddit.com", "youtube.com"]
        ) == ["news.ycombinator.com", "youtube.com"])

        #expect(CloudSyncService.mergedDomains(
            base: ["reddit.com", "youtube.com"],
            local: ["reddit.com", "youtube.com"],
            remote: ["youtube.com"]
        ) == ["youtube.com"])
    }

    @Test @MainActor func accountSwitchLoadsIsolatedLocalCache() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.AccountCache.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = CloudSyncService(store: store)
        let firstUserID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))
        let secondUserID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000021"))
        let firstSession = ActiveSessionRecord(
            plannedEndAt: Date(timeIntervalSince1970: 1_700_001_500),
            plannedDurationSeconds: 1_500,
            outcome: .completed,
            actualDurationSeconds: 1_500
        )

        let firstResult = service.prepareLocalData(
            for: firstUserID,
            history: [firstSession],
            websiteDomains: ["reddit.com"]
        )
        #expect(firstResult.websiteDomains == ["reddit.com"])
        #expect(firstResult.focusHistory == [firstSession])

        let secondResult = service.prepareLocalData(
            for: secondUserID,
            history: firstResult.focusHistory,
            websiteDomains: firstResult.websiteDomains
        )
        #expect(secondResult.websiteDomains.isEmpty)
        #expect(secondResult.focusHistory.isEmpty)

        let restoredFirstResult = service.prepareLocalData(
            for: firstUserID,
            history: secondResult.focusHistory,
            websiteDomains: secondResult.websiteDomains
        )
        #expect(restoredFirstResult.websiteDomains == ["reddit.com"])
        #expect(restoredFirstResult.focusHistory == [firstSession])

        store.clearCloudAccountCaches()
        #expect(try store.loadCloudAccountCache(userID: firstUserID) == nil)
        #expect(try store.loadCloudAccountCache(userID: secondUserID) == nil)
    }

    @Test @MainActor func cloudSyncStateRoundTripsThroughAppGroupStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.CloudSync.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let state = CloudSyncState(
            userID: UUID(),
            pending: true,
            lastAttemptAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSuccessfulSyncAt: nil,
            lastError: "offline"
        )

        try store.saveCloudSyncState(state)

        #expect(try store.loadCloudSyncState() == state)
        store.clearCloudSyncState()
        #expect(try store.loadCloudSyncState() == nil)
    }

}

private struct FailingOnboardingStore: OnboardingStoring {
    func loadSnapshot() throws -> NoxaLocalSnapshot? {
        NoxaLocalSnapshot()
    }

    func saveSnapshot(_ snapshot: NoxaLocalSnapshot) throws {
        throw FailingOnboardingStoreError.expectedFailure
    }
}

private enum FailingOnboardingStoreError: Error {
    case expectedFailure
}
