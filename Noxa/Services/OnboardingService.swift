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

    @discardableResult
    func saveName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            errorMessage = "Enter the name you’d like Noxa to use."
            return false
        }
        return commit {
            $0.draftSetupConfiguration["name"] = String(normalized.prefix(50))
            $0.hasCompletedName = true
        }
    }

    @discardableResult
    func saveGoals(_ goals: [String]) -> Bool {
        guard !goals.isEmpty else {
            errorMessage = "Choose at least one goal to continue."
            return false
        }
        return commit {
            $0.draftPersonalizationAnswers = goals
            $0.draftSetupConfiguration["primaryGoal"] = goals.first
            $0.hasCompletedGoals = true
        }
    }

    @discardableResult
    func saveDistractions(_ distractions: [String]) -> Bool {
        guard !distractions.isEmpty else {
            errorMessage = "Choose at least one distraction to continue."
            return false
        }
        return commit {
            $0.draftSetupConfiguration["distractions"] = distractions.joined(separator: "|")
            $0.draftSetupConfiguration["primaryDistraction"] = distractions.first
            $0.hasCompletedDistractions = true
        }
    }

    @discardableResult
    func saveProblemTimes(_ problemTimes: [String]) -> Bool {
        guard !problemTimes.isEmpty else {
            errorMessage = "Choose at least one time to continue."
            return false
        }
        return commit {
            $0.draftSetupConfiguration["problemTimes"] = problemTimes.joined(separator: "|")
            $0.draftSetupConfiguration["difficultFocusTime"] = problemTimes.first
            $0.hasCompletedProblemTimes = true
        }
    }

    @discardableResult
    func saveMotivations(_ motivations: [String]) -> Bool {
        guard !motivations.isEmpty else {
            errorMessage = "Choose at least one reason to continue."
            return false
        }
        return commit {
            $0.draftSetupConfiguration["motivations"] = motivations.joined(separator: "|")
            $0.draftSetupConfiguration["desiredBenefit"] = motivations.first
            $0.hasCompletedMotivation = true
        }
    }

    @discardableResult
    func completeCapabilitiesExplainer() -> Bool {
        guard progress.hasSeenWelcome,
              progress.hasCompletedName,
              progress.hasCompletedGoals,
              progress.hasCompletedDistractions,
              progress.hasCompletedProblemTimes,
              progress.hasCompletedMotivation else {
            errorMessage = "Complete the earlier onboarding steps before continuing."
            return false
        }
        return commit { $0.hasSeenCapabilitiesExplainer = true }
    }

    @discardableResult
    func completePricingPreview() -> Bool {
        guard progress.hasSeenValueOverview else {
            errorMessage = "Review how Noxa helps before choosing a subscription."
            return false
        }
        return commit { $0.hasSeenPricingPreview = true }
    }

    @discardableResult
    func completeValueOverview() -> Bool {
        guard progress.hasSeenCapabilitiesExplainer else {
            errorMessage = "Allow Screen Time access before continuing."
            return false
        }
        return commit { $0.hasSeenValueOverview = true }
    }

    @discardableResult
    func completeInitialSetup() -> Bool {
        guard progress.hasSeenPricingPreview else {
            errorMessage = "Choose a subscription before finishing setup."
            return false
        }
        return commit { $0.hasCompletedInitialSetup = true }
    }

    @discardableResult
    func completeFirstSessionPrompt() -> Bool {
        guard progress.hasCompletedInitialSetup else {
            errorMessage = "Complete the earlier onboarding steps before continuing."
            return false
        }
        return commit { $0.hasSeenFirstSessionPrompt = true }
    }

    @discardableResult
    func reset() -> Bool {
        let didReset = commit { $0 = OnboardingProgress() }
        if didReset {
            isAuthenticationRequested = false
            isPersonalizationRequested = false
        }
        return didReset
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
        progress.hasCompletedInitialSetup = true
        progress.hasSeenFirstSessionPrompt = true
    }
}
