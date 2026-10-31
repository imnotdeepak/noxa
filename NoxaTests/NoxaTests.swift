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

    @Test @MainActor func manualShieldSnapshotPersistsSeparatelyFromEditableSelection() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ManualShield.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let configuration = ManualShieldConfiguration(
            selection: FamilyActivitySelection(),
            websiteDomains: ["reddit.com"]
        )

        try store.saveManualShield(configuration)
        try store.saveFamilyActivitySelection(FamilyActivitySelection())
        #expect(try store.loadManualShield() == configuration)

        store.clearManualShield()
        #expect(try store.loadManualShield() == nil)
        #expect(try store.loadFamilyActivitySelection() != nil)
    }

    @Test @MainActor func manualShieldActivationAndRemovalUpdateDurableState() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ManualActivation.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = ScreenTimeRestrictionService(store: store)

        service.applyShield(customDomains: ["reddit.com"])
        #expect(try store.loadManualShield()?.websiteDomains == ["reddit.com"])

        service.removeShield()
        #expect(try store.loadManualShield() == nil)
    }

    @Test @MainActor func websiteBlocklistActivationSurvivesServiceRecreation() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.WebsiteActivation.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let first = WebsiteBlocklistService(store: store)
        #expect(first.addDomain("reddit.com"))
        first.applyBlocklist()

        let second = WebsiteBlocklistService(store: store)
        #expect(second.isBlocklistActive)
        #expect(store.isWebsiteShieldActive)

        second.clearBlocklist()
        #expect(!store.isWebsiteShieldActive)
    }

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
        #expect(FocusSessionService.normalizedDurationMinutes(240) == 240)
        #expect(FocusSessionService.normalizedDurationMinutes(600) == 240)
    }

    @Test @MainActor func legacyNormalSessionCanStillEndEarlyAfterUpgrade() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.LegacyEnd.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        // Started by a version that had a Strict Mode toggle, with it off.
        let session = ActiveSessionRecord(
            startedAt: Date().addingTimeInterval(-300),
            plannedEndAt: Date().addingTimeInterval(900),
            plannedDurationSeconds: 1_200,
            outcome: .active,
            isStrict: false
        )
        var snapshot = NoxaLocalSnapshot()
        snapshot.activeSession = session
        try store.saveSnapshot(snapshot)

        let service = FocusSessionService(store: store)
        service.endEarly()

        #expect(service.activeSession == nil)
        #expect(service.history.first?.id == session.id)
        #expect(service.history.first?.outcome == .endedEarly)
    }

    @Test func retiredStrictModePreferenceIsCleared() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.StrictPref.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        defaults.set(true, forKey: "noxa.strictModeEnabled")
        defaults.set(true, forKey: "noxa.hasOfferedStrictMode")
        store.clearLegacyStrictModePreference()
        #expect(defaults.object(forKey: "noxa.strictModeEnabled") == nil)
        #expect(defaults.object(forKey: "noxa.hasOfferedStrictMode") == nil)
    }

    @Test @MainActor func strictActiveSessionRejectsEarlyEnd() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.StrictEnd.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let session = ActiveSessionRecord(
            plannedEndAt: Date().addingTimeInterval(900),
            plannedDurationSeconds: 900,
            outcome: .active,
            isStrict: true
        )
        var snapshot = NoxaLocalSnapshot()
        snapshot.activeSession = session
        try store.saveSnapshot(snapshot)

        let service = FocusSessionService(store: store)
        service.endEarly()

        #expect(service.activeSession?.id == session.id)
        #expect(try store.loadSnapshot()?.activeSession?.outcome == .active)
        #expect(service.errorMessage?.contains("can't end early") == true)
    }

    @Test func legacySessionWithoutStrictFieldDecodesAsNormal() throws {
        let session = ActiveSessionRecord(
            plannedEndAt: Date(timeIntervalSince1970: 1_700_001_500),
            plannedDurationSeconds: 1_500
        )
        let encoded = try JSONEncoder().encode(session)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isStrict")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        #expect(try JSONDecoder().decode(ActiveSessionRecord.self, from: legacyData).isStrict == false)
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

    @Test @MainActor func focusMonitorReceiptClearsWithRestrictions() throws {
        let suiteName = "NoxaTests.FocusMonitorReceipt.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)
        let receipt = FocusMonitorReceipt(sessionID: UUID(), appliedAt: Date())
        defaults.set(try JSONEncoder().encode(receipt), forKey: "noxa.focusMonitorReceipt")

        #expect(try store.loadFocusMonitorReceipt() == receipt)
        store.clearFocusSessionRestrictions()
        #expect(try store.loadFocusMonitorReceipt() == nil)
    }

    @Test @MainActor func safariFilterToggleAndEntitlementExpiryPersistSeparately() throws {
        let suiteName = "NoxaTests.SafariFilter.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = AppGroupStore(defaults: defaults)

        #expect(!store.isSafariFilterEnabled)
        store.setSafariFilterEnabled(true)
        #expect(store.isSafariFilterEnabled)
        store.setSafariFilterAllowedUntil(Date().addingTimeInterval(3_600))
        #expect((defaults.object(forKey: "noxa.safariFilterAllowedUntil") as? Date) != nil)
        store.setSafariFilterAllowedUntil(nil)
        #expect(defaults.object(forKey: "noxa.safariFilterAllowedUntil") == nil)
    }

    @Test @MainActor func activeFocusSessionAllowsAdditionsButRejectsRemovals() throws {
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
        try store.saveFocusSessionRestrictions(
            FocusSessionRestrictionConfiguration(selection: FamilyActivitySelection())
        )

        let websites = WebsiteBlocklistService(store: store)

        #expect(websites.addDomain("reddit.com"))
        #expect(websites.domains == ["reddit.com"])
        #expect(try store.loadFocusSessionRestrictions()?.websiteDomains == ["reddit.com"])

        websites.removeDomain("reddit.com")

        #expect(websites.domains == ["reddit.com"])
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
        #expect(statistics.totalFocusMinutes == 95)
        #expect(statistics.dailyFocusMinutes == 25)
        #expect(statistics.weeklyFocusMinutes == 65)
        #expect(statistics.monthlyFocusMinutes == 95)
        #expect(statistics.yearlyFocusMinutes == 95)
        #expect(statistics.currentStreak == 3)
        #expect(statistics.longestStreak == 3)
        #expect(statistics.completionRate == 67)
    }

    @Test func focusPeriodStatisticsUseTheSelectedRollingWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 24, hour: 12
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
            session(daysAgo: 2, outcome: .completed, minutes: 30),
            session(daysAgo: 3, outcome: .endedEarly, minutes: 10),
            session(daysAgo: 20, outcome: .completed, minutes: 60)
        ]
        let day = FocusStatistics.period(history: history, days: 1, now: now, calendar: calendar)
        let week = FocusStatistics.period(history: history, days: 7, now: now, calendar: calendar)
        let month = FocusStatistics.period(history: history, days: 30, now: now, calendar: calendar)

        #expect(day.focusMinutes == 0)
        #expect(day.completedSessions == 0)
        #expect(day.abandonedSessions == 0)
        #expect(day.focusedDays == 0)
        #expect(week.focusMinutes == 40)
        #expect(week.completedSessions == 1)
        #expect(week.abandonedSessions == 1)
        #expect(week.focusedDays == 1)
        #expect(week.completionRate == 50)
        #expect(month.focusMinutes == 100)
        #expect(month.completedSessions == 2)
    }

    @Test func restrictionSchedulesRoundTripThroughAppGroupStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.Schedules.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let schedule = RestrictionScheduleConfiguration(
            selection: FamilyActivitySelection(),
            allowedStartMinutes: 21 * 60,
            allowedEndMinutes: 22 * 60
        )

        try store.saveRestrictionSchedules([schedule])

        #expect(try store.loadRestrictionSchedules() == [schedule])
        store.clearRestrictionSchedules()
        #expect(try store.loadRestrictionSchedules().isEmpty)
    }

    @Test @MainActor func onboardingMilestonesPersistAcrossServiceInstances() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.Onboarding.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let firstService = OnboardingService(store: store)

        firstService.markWelcomeSeen()
        firstService.saveGoals([.work, .studying])
        firstService.saveEstimate(minutesPerDay: 120)
        firstService.saveDistractions([.browsing])

        let secondService = OnboardingService(store: store)
        #expect(secondService.progress.hasSeenWelcome)
        #expect(secondService.progress.hasCompletedGoals)
        #expect(secondService.progress.hasCompletedEstimate)
        #expect(secondService.progress.hasCompletedDistractions)
        #expect(secondService.progress.selectedGoals == [.work, .studying])
        #expect(secondService.progress.estimatedDistractingMinutesPerDay == 120)
        #expect(secondService.progress.selectedDistractions == [.browsing])
        store.clearSnapshot()
    }

    @Test @MainActor func onboardingCannotCompleteBeforeRequiredMilestones() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.OnboardingGate.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = OnboardingService(store: store)

        #expect(!service.completeProductDemo())
        #expect(!service.completeProjection())

        #expect(service.saveGoals([]))
        #expect(service.saveEstimate(minutesPerDay: nil))
        #expect(service.completeProjection())
        #expect(service.saveDistractions([]))
        #expect(service.completeInsight())
        #expect(service.completeProductDemo())
        #expect(service.completeNotificationExplainer())

        // The Pact can't finish onboarding before a verified subscription.
        #expect(!service.finishPact(.completed))
        #expect(!service.confirmSubscription(hasVerifiedAccess: false))
        #expect(service.confirmSubscription(hasVerifiedAccess: true))
        #expect(service.finishPact(.skipped))
        #expect(service.progress.isComplete)
        #expect(service.progress.pactStatus == .skipped)
        #expect(!service.progress.hasSeenFirstFocusReview)
        #expect(service.markFirstFocusReviewPresented())
        store.clearSnapshot()
    }

    @Test @MainActor func onboardingProgressIsIsolatedWhenAccountsChange() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.OnboardingAccounts.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = OnboardingService(store: store)
        let firstUserID = UUID()
        let secondUserID = UUID()

        #expect(service.saveGoals([.work]))
        #expect(service.beginAuthentication(mode: AuthenticationView.Mode.createAccount.rawValue))
        #expect(service.bind(to: firstUserID, remoteCompletion: false))
        // The unowned draft is adopted, not wiped, by the first account.
        #expect(service.progress.ownerUserID == firstUserID)
        #expect(service.progress.selectedGoals == [.work])

        #expect(service.bind(to: secondUserID, remoteCompletion: false))
        #expect(service.progress.ownerUserID == secondUserID)
        #expect(!service.progress.hasCompletedGoals)
        #expect(service.progress.hasSeenWelcome)

        #expect(service.bind(to: secondUserID, remoteCompletion: true))
        #expect(service.isComplete(for: secondUserID, remoteCompletion: true))
        store.clearSnapshot()
    }

    @Test @MainActor func getStartedResumesAnUnownedDraft() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.OnboardingResume.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = OnboardingService(store: store)
        #expect(service.saveGoals([.betterSleep]))
        #expect(service.saveEstimate(minutesPerDay: 60))
        #expect(service.hasUnfinishedNewUserDraft)

        #expect(service.beginNewAccountPersonalization())
        #expect(service.progress.selectedGoals == [.betterSleep])

        // Progress owned by a signed-out account is replaced instead.
        #expect(service.bind(to: UUID(), remoteCompletion: true))
        #expect(service.beginNewAccountPersonalization())
        #expect(!service.progress.isComplete)
        #expect(service.progress.selectedGoals.isEmpty)
        store.clearSnapshot()
    }

    @Test @MainActor func buildEightOnboardingProgressMigratesPastPricingPreview() throws {
        let legacyJSON = """
        {
          "hasSeenWelcome": true,
          "hasCompletedGoals": true,
          "hasCompletedDistractions": true,
          "hasSeenCapabilitiesExplainer": true,
          "hasCompletedInitialSetup": false,
          "hasSeenFirstSessionPrompt": false,
          "draftPersonalizationAnswers": ["Work"],
          "draftSetupConfiguration": {"distractions": "Social media"}
        }
        """

        let progress = try JSONDecoder().decode(OnboardingProgress.self, from: Data(legacyJSON.utf8))

        #expect(progress.hasSeenPricingPreview)
        #expect(!progress.hasSeenNotificationExplainer)
    }

    @Test @MainActor func completedExistingOnboardingIsNotReopenedForNotificationEducation() throws {
        let legacyJSON = """
        {
          "flowVersion": 3,
          "hasSeenPricingPreview": true,
          "hasCompletedInitialSetup": true,
          "hasSeenFirstSessionPrompt": true
        }
        """
        let progress = try JSONDecoder().decode(OnboardingProgress.self, from: Data(legacyJSON.utf8))
        #expect(progress.isComplete)
        #expect(!progress.hasSeenNotificationExplainer)
        #expect(progress.hasSeenFirstFocusReview)
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

    @Test @MainActor func legacyLocalSubscriptionReviewCannotGrantAccess() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.\(UUID().uuidString)"))
        let firstAccount = UUID()
        let secondAccount = UUID()

        // Old local acknowledgements must not grant access under the current
        // RevenueCat entitlement gate, including to another account.
        defaults.set([firstAccount.uuidString], forKey: "reviewedSubscriptionAccountIDs")
        let subscriptions = SubscriptionService(defaults: defaults)
        #expect(!subscriptions.canEnterApp(for: firstAccount))
        #expect(!subscriptions.canEnterApp(for: secondAccount))
        #expect(!subscriptions.canEnterApp(for: nil))
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
