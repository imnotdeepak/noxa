import SwiftUI

/// A disposable onboarding draft. Replaying the flow never writes to the
/// signed-in account's onboarding record or App Group snapshot.
private final class OnboardingReplayStore: OnboardingStoring {
    private var snapshot: NoxaLocalSnapshot?

    func loadSnapshot() throws -> NoxaLocalSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: NoxaLocalSnapshot) throws { self.snapshot = snapshot }
}

struct OnboardingReplayView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var replayOnboarding = OnboardingService(store: OnboardingReplayStore())
    @State private var hasStarted = false

    var body: some View {
        Group {
            if hasStarted {
                OnboardingView(previewStep: .estimate, isReplay: true) { dismiss() }
            } else {
                OnboardingWelcomeView(onGetStarted: { hasStarted = true })
            }
        }
        .environmentObject(replayOnboarding)
        .overlay(alignment: .topTrailing) {
            Button("Close preview", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(NoxaTheme.primaryText)
                .frame(width: 44, height: 44)
                .background(NoxaTheme.elevated, in: Circle())
                .padding(12)
                .accessibilityLabel("Close onboarding preview")
        }
        .preferredColorScheme(.dark)
    }
}
