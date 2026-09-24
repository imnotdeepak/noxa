import FamilyControls
import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var page: Page
    @State private var goals: Set<String>
    @State private var distractions: Set<String>
    @State private var isRequestingAuthorization = false

    private enum Page: Int, CaseIterable {
        case welcome
        case goals
        case distractions
        case capabilities
    }

    private let goalOptions = ["Studying", "Work", "Sleep", "Reduce screen time", "Deep focus", "Better habits"]
    private let distractionOptions = [
        "Short-form media",
        "Long-form media",
        "Web browsing",
        "Playing games",
        "Social media",
        "Other"
    ]

    init() {
        _page = State(initialValue: .welcome)
        _goals = State(initialValue: [])
        _distractions = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page != .welcome {
                    Button {
                        moveBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Back")
                }

                Text("Noxa")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(page.rawValue + 1) of \(Page.allCases.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Group {
                switch page {
                case .welcome:
                    welcomePage
                case .goals:
                    goalsPage
                case .distractions:
                    distractionsPage
                case .capabilities:
                    capabilitiesPage
                }
            }
            .transition(.opacity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: page)
        .onAppear(perform: restoreDraft)
    }

    private var welcomePage: some View {
        pageLayout {
            Spacer()

            Text("Take back your\nattention.")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.2)

            Text("Block distractions, build better screen habits, and focus when you need to.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            onboardingErrorView

            onboardingButton("Get Started") {
                if onboarding.markWelcomeSeen() {
                    page = .goals
                }
            }
        }
    }

    private var goalsPage: some View {
        pageLayout {
            pageHeader("What do you want help with?", subtitle: "Choose any that fit. You can change your mind later.")
            selectionGrid(options: goalOptions, selected: $goals)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveGoals(Array(goals).sorted()) {
                    page = .distractions
                }
            }
            .disabled(goals.isEmpty)
        }
    }

    private var distractionsPage: some View {
        pageLayout {
            pageHeader("What distracts you the most?", subtitle: "This helps us explain the right Noxa tools before setup.")
            selectionGrid(options: distractionOptions, selected: $distractions)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveDistractions(Array(distractions).sorted()) {
                    page = .capabilities
                }
            }
            .disabled(distractions.isEmpty)
        }
    }

    private var capabilitiesPage: some View {
        pageLayout {
            Spacer()

            Image(systemName: authorization.state.isApproved ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(authorization.state.isApproved ? .white : .secondary)

            Text("Noxa needs Screen Time access")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Apple keeps your app and website selections private. Noxa uses that permission to block only what you choose.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if authorization.state.isApproved {
                Label("Screen Time access is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            } else if authorization.state == .denied {
                Text("Permission is currently denied. Enable Screen Time access in Settings, then try again.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage = authorization.errorMessage ?? onboarding.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            if authorization.state.isApproved {
                onboardingButton("Continue to account") {
                    _ = onboarding.completeCapabilitiesExplainer()
                }
            } else {
                onboardingButton(isRequestingAuthorization ? "Requesting…" : "Allow Screen Time Access") {
                    guard !isRequestingAuthorization else { return }
                    isRequestingAuthorization = true
                    Task { @MainActor in
                        await authorization.requestAuthorization()
                        isRequestingAuthorization = false
                    }
                }
                .disabled(isRequestingAuthorization)

                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }

    private func pageLayout<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18, content: content)
                    .padding(24)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height,
                        alignment: .leading
                    )
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.6)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionGrid(options: [String], selected: Binding<Set<String>>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button {
                    if selected.wrappedValue.contains(option) {
                        selected.wrappedValue.remove(option)
                    } else {
                        selected.wrappedValue.insert(option)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected.wrappedValue.contains(option) ? "checkmark.circle.fill" : "circle")
                        Text(option)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected.wrappedValue.contains(option) ? .black : .white)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .background(selected.wrappedValue.contains(option) ? Color.white : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onboardingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var onboardingErrorView: some View {
        if let errorMessage = onboarding.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moveBack() {
        switch page {
        case .welcome:
            break
        case .goals:
            page = .welcome
        case .distractions:
            page = .goals
        case .capabilities:
            page = .distractions
        }
    }

    private func restoreDraft() {
        goals = Set(onboarding.progress.draftPersonalizationAnswers)
        if let savedDistractions = onboarding.progress.draftSetupConfiguration["distractions"] {
            distractions = Set(savedDistractions.split(separator: "|").map(String.init))
        }

        if onboarding.progress.hasCompletedDistractions {
            page = .capabilities
        } else if onboarding.progress.hasCompletedGoals {
            page = .distractions
        } else if onboarding.progress.hasSeenWelcome {
            page = .goals
        }
    }
}

private extension ScreenTimeAuthorizationState {
    var isApproved: Bool {
        self == .approved || self == .approvedWithDataAccess
    }
}
