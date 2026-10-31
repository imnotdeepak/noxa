import Combine
import Foundation

protocol OnboardingStoring {
    func loadSnapshot() throws -> NoxaLocalSnapshot?
    func saveSnapshot(_ snapshot: NoxaLocalSnapshot) throws
}

extension AppGroupStore: OnboardingStoring {}

/// Persists onboarding milestones and draft answers in the shared App Group.
/// The route is derived from these milestones at launch rather than from the
/// last SwiftUI screen that happened to be visible.
@MainActor
final class OnboardingService: ObservableObject {
    @Published private(set) var progress: OnboardingProgress
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticationRequested = false
    @Published private(set) var isPersonalizationRequested = false

    private let store: any OnboardingStoring

    init(store: (any OnboardingStoring)? = nil) {
        self.store = store ?? AppGroupStore.shared
        do {
            progress = try self.store.loadSnapshot()?.onboarding ?? OnboardingProgress()
        } catch {
            progress = OnboardingProgress()
            errorMessage = "Could not load onboarding progress: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func markWelcomeSeen() -> Bool {
        commit { $0.hasSeenWelcome = true }
    }

    @discardableResult
    func beginPersonalization() -> Bool {
        let didSave = commit { $0.hasSeenWelcome = true }
        if didSave {
            isPersonalizationRequested = true
        }
        return didSave
    }

    /// Starts onboarding for a new account. A draft that no account owns yet
    /// is resumed with its answers; completed progress left by a signed-out
    /// account is replaced so it can't leak into the new one.
    @discardableResult
    func beginNewAccountPersonalization() -> Bool {
        let didSave = commit { progress in
            if progress.ownerUserID != nil || progress.isComplete {
                progress = OnboardingProgress()
            }
            progress.hasSeenWelcome = true
        }
        if didSave {
            isAuthenticationRequested = false
            isPersonalizationRequested = true
        }
        return didSave
    }

    /// An unowned draft that was started but not finished on this device,
    /// so a relaunch can quietly return to it instead of to Welcome.
    var hasUnfinishedNewUserDraft: Bool {
        progress.ownerUserID == nil && progress.hasSeenWelcome
            && progress.hasCompletedEstimate && !progress.isComplete
    }

    /// Set when leaving the account screen, so the narrative reopens on its
    /// last step instead of immediately routing back to account creation.
    private(set) var resumeOverride: OnboardingStep?

    /// Back from the account screen to the narrative, keeping every answer.
    func returnToPersonalization() {
        resumeOverride = .productDemo
        isAuthenticationRequested = false
        isPersonalizationRequested = true
    }

    func consumeResumeOverride() -> OnboardingStep? {
        defer { resumeOverride = nil }
        return resumeOverride
    }

    @discardableResult
    func beginAuthentication(mode: String) -> Bool {
        let didSave = commit {
            $0.hasSeenWelcome = true
            $0.draftSetupConfiguration["authenticationMode"] = mode
        }
        if didSave {
            isAuthenticationRequested = true
            isPersonalizationRequested = false
        }
        return didSave
    }

    /// Binds device-local onboarding to the signed-in account. Older builds
    /// stored one device-wide progress record, so the first authenticated user
    /// adopts it. A different account starts with an isolated onboarding flow.
    @discardableResult
    func bind(to userID: UUID, remoteCompletion: Bool) -> Bool {
        if progress.ownerUserID == userID {
            guard remoteCompletion, !progress.isComplete else { return true }
            return commit { progress in
                Self.markComplete(&progress, ownerUserID: userID)
            }
        }

        if progress.ownerUserID == nil {
            return commit { progress in
                progress.ownerUserID = userID
                if remoteCompletion {
                    Self.markComplete(&progress, ownerUserID: userID)
                }
            }
        }

        return commit { progress in
            progress = OnboardingProgress()
            progress.ownerUserID = userID
            progress.hasSeenWelcome = true
            if remoteCompletion {
                Self.markComplete(&progress, ownerUserID: userID)
            }
        }
    }

    func isComplete(for userID: UUID?, remoteCompletion: Bool) -> Bool {
        guard let userID else { return false }
        return remoteCompletion || (progress.ownerUserID == userID && progress.isComplete)
    }

    /// Goals are optional; an empty set records a skip. Each tap saves the
    /// draft with `complete: false` so a relaunch keeps the choices.
    @discardableResult
    func saveGoals(_ goals: Set<OnboardingGoal>, complete: Bool = true) -> Bool {
        commit {
            $0.hasSeenWelcome = true
            $0.draftPersonalizationAnswers = OnboardingGoal.allCases.filter(goals.contains).map(\.rawValue)
            if complete { $0.hasCompletedGoals = true }
        }
    }

    /// nil means "I'm not sure"; the projection then shows a labelled example.
    @discardableResult
    func saveEstimate(minutesPerDay: Int?) -> Bool {
        commit {
            $0.hasSeenWelcome = true
            if let minutesPerDay {
                $0.draftSetupConfiguration["estimatedMinutes"] = String(
                    TimeProjection(minutesPerDay: minutesPerDay).minutesPerDay
                )
            } else {
                $0.draftSetupConfiguration.removeValue(forKey: "estimatedMinutes")
            }
            $0.hasCompletedEstimate = true
        }
    }

    @discardableResult
    func completeProjection() -> Bool {
        guard progress.hasCompletedEstimate else {
            errorMessage = "Add an estimate before continuing."
            return false
        }
        return commit { $0.hasSeenProjection = true }
    }

    /// Distraction types are preference hints only, never blocked tokens.
    @discardableResult
    func saveDistractions(_ distractions: Set<OnboardingDistraction>, complete: Bool = true) -> Bool {
        commit {
            let ordered = OnboardingDistraction.allCases.filter(distractions.contains).map(\.rawValue)
            if ordered.isEmpty {
                $0.draftSetupConfiguration.removeValue(forKey: "distractions")
            } else {
                $0.draftSetupConfiguration["distractions"] = ordered.joined(separator: "|")
            }
            if complete { $0.hasCompletedDistractions = true }
        }
    }

    @discardableResult
    func completeInsight() -> Bool {
        commit { $0.hasSeenInsight = true }
    }

    @discardableResult
    func completeProductDemo() -> Bool {
        guard progress.hasCompletedGoals,
              progress.hasCompletedEstimate,
              progress.hasSeenProjection,
              progress.hasCompletedDistractions,
              progress.hasSeenInsight else {
            errorMessage = "Complete the earlier onboarding steps before continuing."
            return false
        }
        return commit { $0.hasSeenProductDemo = true }
    }

    /// Optional: granted, denied and "Not Now" all continue.
    @discardableResult
    func completeNotificationExplainer() -> Bool {
        commit { $0.hasSeenNotificationExplainer = true }
    }

    /// Allow and Skip both continue; only the answer differs.
    @discardableResult
    func completeAnalyticsConsent() -> Bool {
        commit { $0.hasAnsweredAnalyticsConsent = true }
    }

    /// Records a verified entitlement. The caller checks access first; this
    /// is never set from a purchase button tap alone.
    @discardableResult
    func confirmSubscription(hasVerifiedAccess: Bool) -> Bool {
        guard hasVerifiedAccess else {
            errorMessage = "Your subscription isn't active yet."
            return false
        }
        return commit { $0.hasSeenPricingPreview = true }
    }

    /// Finishes onboarding. The Pact is voluntary, so completing and skipping
    /// both open Home; only a verified subscription is required.
    @discardableResult
    func finishPact(_ status: PactStatus) -> Bool {
        guard progress.hasSeenPricingPreview else {
            errorMessage = "Your subscription isn't active yet."
            return false
        }
        return commit {
            $0.pactStatus = status
            $0.hasCompletedInitialSetup = true
            $0.hasSeenFirstSessionPrompt = true
        }
    }

    @discardableResult
    func markFirstFocusReviewPresented() -> Bool {
        guard progress.isComplete else { return false }
        return commit { $0.hasSeenFirstFocusReview = true }
    }

    @discardableResult
    func reset() -> Bool {
        let didReset = commit { $0 = OnboardingProgress() }
        if didReset {
            clearTransientRoute()
        }
        return didReset
    }

    func clearTransientRoute() {
        isAuthenticationRequested = false
        isPersonalizationRequested = false
    }

    private func commit(_ update: (inout OnboardingProgress) -> Void) -> Bool {
        var updatedProgress = progress
        update(&updatedProgress)

        do {
            var snapshot = (try store.loadSnapshot()) ?? NoxaLocalSnapshot()
            snapshot.onboarding = updatedProgress
            try store.saveSnapshot(snapshot)
            progress = updatedProgress
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save onboarding progress: \(error.localizedDescription)"
            return false
        }
    }

    private static func markComplete(_ progress: inout OnboardingProgress, ownerUserID: UUID) {
        progress.ownerUserID = ownerUserID
        progress.hasSeenWelcome = true
        progress.hasCompletedName = true
        progress.hasCompletedGoals = true
        progress.hasCompletedDistractions = true
        progress.hasCompletedProblemTimes = true
        progress.hasCompletedMotivation = true
        progress.hasSeenCapabilitiesExplainer = true
        progress.hasSeenValueOverview = true
        progress.hasSeenPricingPreview = true
        progress.hasSeenNotificationExplainer = true
        progress.hasCompletedInitialSetup = true
        progress.hasSeenFirstSessionPrompt = true
        progress.hasSeenFirstFocusReview = true
        progress.hasCompletedEstimate = true
        progress.hasSeenProjection = true
        progress.hasSeenInsight = true
        progress.hasSeenProductDemo = true
        progress.hasAnsweredAnalyticsConsent = true
    }
}
