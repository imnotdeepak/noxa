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
    func saveGoals(_ goals: [String]) -> Bool {
        guard !goals.isEmpty else {
            errorMessage = "Choose at least one goal to continue."
            return false
        }
        return commit {
            $0.draftPersonalizationAnswers = goals
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
            $0.hasCompletedDistractions = true
        }
    }

    @discardableResult
    func completeCapabilitiesExplainer() -> Bool {
        guard progress.hasSeenWelcome,
              progress.hasCompletedGoals,
              progress.hasCompletedDistractions else {
            errorMessage = "Complete the earlier onboarding steps before continuing."
            return false
        }
        return commit { $0.hasSeenCapabilitiesExplainer = true }
    }

    @discardableResult
    func completePricingPreview() -> Bool {
        guard progress.hasSeenCapabilitiesExplainer else {
            errorMessage = "Allow Screen Time access before continuing."
            return false
        }
        return commit { $0.hasSeenPricingPreview = true }
    }

    @discardableResult
    func reset() -> Bool {
        commit { $0 = OnboardingProgress() }
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
}
