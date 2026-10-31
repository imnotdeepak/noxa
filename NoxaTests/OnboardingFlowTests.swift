import Foundation
import Testing
@testable import Noxa

struct OnboardingFlowTests {
    // ONB-03: 3 hours a day.
    @Test func threeHoursADayProjection() {
        let projection = TimeProjection(minutesPerDay: 180)
        #expect(projection.weekHours == 21)
        #expect(projection.averageMonthHours == 91.25)
        #expect(projection.annualHours == 1_095)
        #expect(projection.annualFullDays == 45.625)
        #expect(TimeProjection.format(projection.annualFullDays) == "45.6")
    }

    @Test func projectionHandlesZeroFractionsAndTheMaximum() {
        #expect(TimeProjection(minutesPerDay: 0).annualFullDays == 0)
        #expect(TimeProjection(minutesPerDay: 30).weekHours == 3.5)
        #expect(TimeProjection(minutesPerDay: 90).annualHours == 547.5)
        #expect(TimeProjection(minutesPerDay: 10_000).minutesPerDay == TimeProjection.maximumMinutesPerDay)
        #expect(TimeProjection(minutesPerDay: -5).minutesPerDay == 0)
        #expect(TimeProjection.label(minutes: 30) == "30m")
        #expect(TimeProjection.label(minutes: 135) == "2h 15m")
        #expect(TimeProjection.label(minutes: 360) == "6h+")
    }

    private func narrativeDone() -> OnboardingProgress {
        var progress = OnboardingProgress()
        progress.hasSeenWelcome = true
        progress.hasCompletedGoals = true
        progress.hasCompletedEstimate = true
        progress.hasSeenProjection = true
        progress.hasCompletedDistractions = true
        progress.hasSeenInsight = true
        progress.hasSeenProductDemo = true
        return progress
    }

    private func resume(
        _ progress: OnboardingProgress,
        signedIn: Bool = true,
        approved: Bool = true,
        selection: Bool = true,
        subscribed: Bool = false
    ) -> OnboardingStep {
        OnboardingStep.resume(
            progress: progress,
            isAuthenticated: signedIn,
            isScreenTimeApproved: approved,
            hasSelection: selection,
            hasSubscription: subscribed
        )
    }

    @Test func narrativeResumesAtTheFirstUnansweredStep() {
        // Time and its projection come first, then the why.
        var progress = OnboardingProgress()
        #expect(resume(progress) == .estimate)
        progress.hasCompletedEstimate = true
        #expect(resume(progress) == .projection)
        progress.hasSeenProjection = true
        #expect(resume(progress) == .goals)
        #expect(resume(narrativeDone(), signedIn: false) == .account)
    }

    // ONB-05, ONB-06, ONB-15: live checks always win over saved progress.
    @Test func setupIsRecheckedLiveBeforePayment() {
        var progress = narrativeDone()
        progress.hasSeenNotificationExplainer = true
        progress.hasAnsweredAnalyticsConsent = true
        #expect(resume(progress, approved: false) == .screenTime)
        #expect(resume(progress, selection: false) == .selection)
        #expect(resume(progress) == .subscription)
    }

    // The analytics question comes right after notifications, before payment.
    @Test func analyticsIsAskedAfterNotifications() {
        var progress = narrativeDone()
        progress.hasSeenNotificationExplainer = true
        #expect(resume(progress) == .analyticsConsent)
        #expect(OnboardingStep.analyticsConsent.previous == .notifications)
    }

    // ONB-11: an existing subscriber skips the purchase.
    @Test func existingSubscriberGoesStraightToThePact() {
        var progress = narrativeDone()
        progress.hasSeenNotificationExplainer = true
        progress.hasAnsweredAnalyticsConsent = true
        #expect(resume(progress, subscribed: true) == .pact)
    }

    @Test func backNeverUndoesExternalSteps() {
        #expect(OnboardingStep.estimate.previous == nil)
        #expect(OnboardingStep.goals.previous == .projection)
        #expect(OnboardingStep.screenTime.previous == nil)
        #expect(OnboardingStep.subscription.previous == nil)
        #expect(OnboardingStep.pact.previous == nil)
        #expect(OnboardingStep.projection.previous == .estimate)
    }

    // ONB-04: "Not sure" stores no estimate, so nothing is attributed to the user.
    @Test @MainActor func notSureStoresNoEstimate() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.Estimate.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = OnboardingService(store: store)
        #expect(service.saveEstimate(minutesPerDay: 240))
        #expect(service.saveEstimate(minutesPerDay: nil))
        #expect(service.progress.estimatedDistractingMinutesPerDay == nil)
        #expect(service.progress.hasCompletedEstimate)
        store.clearSnapshot()
    }

    // ONB-13: skipping the Pact still opens Home for a subscriber.
    @Test @MainActor func skippingThePactStillFinishesOnboarding() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.Pact.\(UUID().uuidString)"))
        let store = AppGroupStore(defaults: defaults)
        let service = OnboardingService(store: store)
        #expect(service.confirmSubscription(hasVerifiedAccess: true))
        #expect(service.finishPact(.skipped))
        #expect(service.progress.isComplete)
        store.clearSnapshot()
    }

    @Test func pactStatusRoundTrips() throws {
        var progress = narrativeDone()
        progress.pactStatus = .completed
        let decoded = try JSONDecoder().decode(
            OnboardingProgress.self, from: JSONEncoder().encode(progress)
        )
        #expect(decoded.pactStatus == .completed)
        #expect(decoded.hasSeenProductDemo)
    }

    // An in-progress draft from the old flow skips the new narrative once
    // it had passed the old name step, instead of starting over.
    @Test func olderDraftKeepsItsPlace() throws {
        let legacy = """
        {"flowVersion": 5, "hasSeenWelcome": true, "hasCompletedName": true,
         "hasCompletedGoals": true, "hasCompletedDistractions": true}
        """
        let progress = try JSONDecoder().decode(OnboardingProgress.self, from: Data(legacy.utf8))
        #expect(progress.hasSeenProductDemo)
        #expect(resume(progress, approved: false) == .screenTime)

        let early = """
        {"flowVersion": 5, "hasSeenWelcome": true, "hasCompletedGoals": true}
        """
        let earlyProgress = try JSONDecoder().decode(OnboardingProgress.self, from: Data(early.utf8))
        #expect(resume(earlyProgress) == .estimate)
    }
}
