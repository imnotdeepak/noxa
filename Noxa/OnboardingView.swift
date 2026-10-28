import FamilyControls
import SwiftUI
import UIKit
import UserNotifications

struct OnboardingWelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var onboarding: OnboardingService
    @State private var revealsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image("NoxaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250, maxHeight: 126)
                    .accessibilityHidden(true)

                Text("noxa")
                    .font(NoxaTheme.font(42, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-1)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                Text("Your attention belongs to you.")
                    .font(NoxaTheme.font(28, weight: .bold, relativeTo: .title))
                    .multilineTextAlignment(.center)

                Text("Your phone is built to steal your attention. People spend way too much time on their phone. Let's change that")
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 30)
            .opacity(revealsDetails ? 1 : 0)
            .offset(y: revealsDetails ? 0 : 22)

            Spacer()

            VStack(spacing: 12) {
                Button("Get my life back") {
                    _ = onboarding.beginNewAccountPersonalization()
                }
                .buttonStyle(NoxaPrimaryButtonStyle())

                Button("I already have an account") {
                    _ = onboarding.beginAuthentication(
                        mode: AuthenticationView.Mode.signIn.rawValue
                    )
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            }
            .opacity(revealsDetails ? 1 : 0)
            .offset(y: revealsDetails ? 0 : 16)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .font(NoxaTheme.font(17))
        .background(NoxaOnboardingBackground())
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                revealsDetails = true
            } else {
                withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                    revealsDetails = true
                }
            }
        }
    }
}

struct ReturningUserView: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var onboarding: OnboardingService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("NoxaLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 112)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(welcomeTitle)
                    .font(NoxaTheme.font(38, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-0.9)
                    .multilineTextAlignment(.center)

                Text("Sign in to continue where you left off. You won’t need to repeat onboarding.")
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let email = authentication.rememberedUserEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(NoxaTheme.accent)
                }
            }
            .padding(.top, 28)

            Spacer()

            VStack(spacing: 12) {
                Button("Continue") {
                    _ = onboarding.beginAuthentication(
                        mode: AuthenticationView.Mode.signIn.rawValue
                    )
                }
                .buttonStyle(NoxaPrimaryButtonStyle())

                Button("Use a different account") {
                    authentication.forgetRememberedAccount()
                    _ = onboarding.reset()
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .font(NoxaTheme.font(17))
        .background(NoxaOnboardingBackground())
        .preferredColorScheme(.dark)
    }

    private var welcomeTitle: String {
        guard let name = authentication.rememberedDisplayName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Welcome back."
        }
        return "Welcome back, \(name)."
    }

}

struct OnboardingView: View {
    @EnvironmentObject private var onboarding: OnboardingService
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var notifications: FocusNotificationService
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var page: Page
    @State private var name: String
    @State private var goals: Set<String>
    @State private var distractions: Set<String>
    @State private var problemTimes: Set<String>
    @State private var motivations: Set<String>
    @State private var isRequestingAuthorization = false
    @FocusState private var isNameFieldFocused: Bool

    private enum Page: Int, CaseIterable {
        case goals
        case distractions
        case problemTimes
        case motivation
        case goalInsight
        case name
        case capabilities
        case valueOverview
        case notifications
        case distractionSetup
        case success
    }

    private let goalOptions = OnboardingGoal.allCases.map(\.rawValue)
    private let distractionOptions = OnboardingDistraction.allCases.map(\.rawValue)
    private let problemTimeOptions = OnboardingFocusTime.allCases.map(\.rawValue)
    private let motivationOptions = OnboardingBenefit.allCases.map(\.rawValue)

    init() {
        _page = State(initialValue: .goals)
        _name = State(initialValue: "")
        _goals = State(initialValue: [])
        _distractions = State(initialValue: [])
        _problemTimes = State(initialValue: [])
        _motivations = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if canMoveBack {
                    Button {
                        moveBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Back")
                }

                Spacer()

                Text("noxa")
                    .font(NoxaTheme.font(17, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(NoxaTheme.primaryText)

                Spacer()

                if canMoveBack {
                    Color.clear
                        .frame(width: 17, height: 17)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 18)

            Group {
                switch page {
                case .goals:
                    goalsPage
                case .distractions:
                    distractionsPage
                case .problemTimes:
                    problemTimesPage
                case .motivation:
                    motivationPage
                case .goalInsight:
                    goalInsightPage
                case .name:
                    namePage
                case .capabilities:
                    capabilitiesPage
                case .valueOverview:
                    valueOverviewPage
                case .notifications:
                    notificationsPage
                case .distractionSetup:
                    distractionSetupPage
                case .success:
                    successPage
                }
            }
            .transition(.opacity)
        }
        .font(NoxaTheme.font(17))
        .background(NoxaOnboardingBackground())
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: page)
        .onAppear(perform: restoreDraft)
        .sheet(isPresented: $restrictions.isPickerPresented) {
            NavigationStack {
                FamilyActivityPicker(selection: $restrictions.selection)
                    .navigationTitle("Choose distractions")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                restrictions.persistSelection()
                                restrictions.isPickerPresented = false
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var namePage: some View {
        pageLayout {
            Spacer()

            Text("What should we call you?")
                .font(NoxaTheme.font(36, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("This makes Noxa feel a little more like yours.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            TextField("What's your name?", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(NoxaTheme.font(26, weight: .medium, relativeTo: .title2))
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isNameFieldFocused ? NoxaTheme.accent : Color.white.opacity(0.3))
                        .frame(height: 1)
                }
                .focused($isNameFieldFocused)
                .submitLabel(.continue)
                .onSubmit(continueFromName)
                .onChange(of: name) { value in
                    if value.count > 50 {
                        name = String(value.prefix(50))
                    }
                }
                .padding(.horizontal, 20)

            Spacer()

            onboardingErrorView

            onboardingButton("Continue") {
                continueFromName()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func continueFromName() {
        isNameFieldFocused = false
        if onboarding.saveName(name) {
            if authentication.isAuthenticated {
                page = .capabilities
            } else {
                _ = onboarding.beginAuthentication(
                    mode: AuthenticationView.Mode.createAccount.rawValue
                )
            }
        }
    }

    private var goalsPage: some View {
        pageLayout {
            pageHeader(
                "What do you want help with?",
                subtitle: "Choose any that fit. You can change your mind later.",
                progress: "1 of 4"
            )
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

    private var goalInsightPage: some View {
        insightPage(
            statistic: "53%",
            title: "You’re not alone.",
            message: "More than half of U.S. adults say they spend too much time on their smartphone.",
            source: "Pew Research Center · Survey conducted May–June 2026"
        ) {
            page = .problemTimes
        }
    }

    private var distractionsPage: some View {
        pageLayout {
            pageHeader(
                "What distracts you the most?",
                subtitle: "This helps us explain the right Noxa tools before setup.",
                progress: "2 of 4"
            )
            selectionGrid(options: distractionOptions, selected: $distractions)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveDistractions(Array(distractions).sorted()) {
                    page = .goalInsight
                }
            }
            .disabled(distractions.isEmpty)
        }
    }

    private var problemTimesPage: some View {
        pageLayout {
            pageHeader(
                "When is staying focused hardest?",
                subtitle: "Choose any times that regularly pull you off track.",
                progress: "3 of 4"
            )
            selectionGrid(options: problemTimeOptions, selected: $problemTimes)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveProblemTimes(Array(problemTimes).sorted()) {
                    page = .motivation
                }
            }
            .disabled(problemTimes.isEmpty)
        }
    }

    private var motivationPage: some View {
        pageLayout {
            pageHeader(
                "What would less phone time give you?",
                subtitle: "Choose what you want to make more room for.",
                progress: "4 of 4"
            )
            selectionGrid(options: motivationOptions, selected: $motivations)
            Spacer()
            onboardingErrorView
            onboardingButton("Continue") {
                if onboarding.saveMotivations(Array(motivations).sorted()) {
                    page = .name
                }
            }
            .disabled(motivations.isEmpty)
        }
    }

    private var capabilitiesPage: some View {
        pageLayout {
            Spacer()

            Image(systemName: authorization.state.isApproved ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 52))
                .foregroundStyle(authorization.state.isApproved ? .white : .secondary)
                .frame(maxWidth: .infinity)

            Text("Noxa needs Screen Time access")
                .font(NoxaTheme.font(32, weight: .bold, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Apple keeps your app and website selections private. Noxa uses that permission to block only what you choose.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            if authorization.state.isApproved {
                Label("Screen Time access is ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            } else if authorization.state == .denied {
                Text("Permission is currently denied. Enable Screen Time access in Settings, then try again.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if authorization.state == .unknown {
                Text("Screen Time access is currently unavailable. Try again or check your device settings.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
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
                onboardingButton("Continue") {
                    if onboarding.completeCapabilitiesExplainer() {
                        page = .valueOverview
                    }
                }
            } else {
                onboardingButton(
                    isRequestingAuthorization
                        ? "Requesting…"
                        : (authorization.state == .denied ? "Try Screen Time Access Again" : "Allow Screen Time Access")
                ) {
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

    private var valueOverviewPage: some View {
        pageLayout {
            pageHeader(
                "Here’s how Noxa helps.",
                subtitle: "Simple tools that help you protect your attention."
            )

            VStack(spacing: 12) {
                valueRow(
                    icon: "hand.raised.slash",
                    title: "Block distractions",
                    detail: "Choose the apps and websites that pull your attention away."
                )
                valueRow(
                    icon: "timer",
                    title: "Focus intentionally",
                    detail: "Keep distractions blocked during intentional focus sessions."
                )
                valueRow(
                    icon: "hourglass",
                    title: "Set healthy limits",
                    detail: "Create boundaries around apps that consume too much of your time."
                )
                valueRow(
                    icon: "chart.bar",
                    title: "See your progress",
                    detail: "Understand your focus history and the time you’ve protected."
                )
            }

            Spacer()

            onboardingErrorView

            onboardingButton("Continue") {
                _ = onboarding.completeValueOverview()
            }
        }
    }

    private var notificationsPage: some View {
        pageLayout {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 52))
                .foregroundStyle(NoxaTheme.accent)
                .frame(maxWidth: .infinity)

            Text("Know when your focus time changes")
                .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Notifications can remind you when a focus session ends, when a Pomodoro break is halfway through, and one minute before the next work interval. Your blocks still work if you choose not to allow notifications.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            if notifications.canSchedule {
                Label("Notifications are enabled", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NoxaTheme.accent)
                    .frame(maxWidth: .infinity)
            } else if notifications.authorizationStatus == .denied {
                Text("Notifications are off. You can turn them on in Settings later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            onboardingErrorView

            onboardingButton(
                notifications.authorizationStatus == .notDetermined
                    ? "Enable Notifications" : "Continue"
            ) {
                Task { @MainActor in
                    if notifications.authorizationStatus == .notDetermined {
                        _ = await notifications.requestAuthorization()
                    }
                    if onboarding.completeNotificationExplainer() {
                        page = .distractionSetup
                    }
                }
            }

            if notifications.authorizationStatus == .notDetermined {
                Button("Not Now") {
                    if onboarding.completeNotificationExplainer() {
                        page = .distractionSetup
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            } else if notifications.authorizationStatus == .denied {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func valueRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NoxaTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(NoxaTheme.font(17, weight: .semibold, relativeTo: .headline))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .noxaCard()
    }

    private var distractionSetupPage: some View {
        pageLayout {
            Spacer()

            Image(systemName: "hand.raised.slash.fill")
                .font(.system(size: 50))
                .foregroundStyle(NoxaTheme.accent)
                .frame(maxWidth: .infinity)

            Text(restrictions.hasSelection ? "Your distractions are set" : "Choose your distractions")
                .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(distractionSetupMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Label(targetSuggestionMessage, systemImage: "sparkle.magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(NoxaTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(restrictions.hasSelection ? "Edit distractions" : "Choose distractions") {
                restrictions.isPickerPresented = true
            }
            .buttonStyle(NoxaSecondaryButtonStyle())

            Text(selectionCountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(restrictions.hasSelection ? NoxaTheme.accent : .secondary)
                .frame(maxWidth: .infinity)

            if let errorMessage = restrictions.errorMessage ?? onboarding.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            onboardingButton("Continue") {
                restrictions.persistSelection()
                guard restrictions.hasSelection, restrictions.errorMessage == nil else { return }
                if onboarding.completeInitialSetup() {
                    page = .success
                }
            }
            .disabled(!restrictions.hasSelection)

            Text("You can change these anytime from your Blocklist.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var successPage: some View {
        pageLayout {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(NoxaTheme.accent)
                .frame(maxWidth: .infinity)

            Text("Noxa is ready.")
                .font(NoxaTheme.font(36, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("\(selectedDistractionSummary) will be blocked during your focus sessions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(personalizedSuccessMessage)
                .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Start with a 30-minute focus session using the distractions you chose. You can review the targets and change the duration before starting.")
                .font(NoxaTheme.font(17, relativeTo: .body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let errorMessage = onboarding.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            onboardingButton("Review Your First Focus") {
                _ = onboarding.completeFirstSessionPrompt()
            }
        }
    }

    private func insightPage(
        statistic: String,
        title: String,
        message: String,
        source: String,
        action: @escaping () -> Void
    ) -> some View {
        pageLayout {
            Spacer()

            VStack(spacing: 16) {
                Text(statistic)
                    .font(NoxaTheme.font(statistic.count < 5 ? 68 : 38, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-1.4)
                    .multilineTextAlignment(.center)

                Text(title)
                    .font(NoxaTheme.font(30, weight: .bold, relativeTo: .title))
                    .multilineTextAlignment(.center)

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(source)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(NoxaTheme.border, lineWidth: 1)
            }

            Spacer()
            onboardingButton("Continue", action: action)
        }
    }

    private func pageLayout<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18, content: content)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 24)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height,
                        alignment: .leading
                    )
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func pageHeader(_ title: String, subtitle: String, progress: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress {
                Text(progress.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(NoxaTheme.accent)
            }
            Text(title)
                .font(NoxaTheme.font(32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.6)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionGrid(options: [String], selected: Binding<Set<String>>) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button {
                    if selected.wrappedValue.contains(option) {
                        selected.wrappedValue.remove(option)
                    } else {
                        selected.wrappedValue.insert(option)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(option)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if selected.wrappedValue.contains(option) {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(NoxaTheme.accent)
                        }
                    }
                    .font(NoxaTheme.font(17, weight: .medium))
                    .foregroundStyle(NoxaTheme.primaryText)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                selected.wrappedValue.contains(option) ? NoxaTheme.accent : NoxaTheme.border,
                                lineWidth: selected.wrappedValue.contains(option) ? 1.5 : 1
                            )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func onboardingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoxaPrimaryButtonStyle())
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
        case .goals:
            break
        case .distractions:
            page = .goals
        case .problemTimes:
            page = .goalInsight
        case .motivation:
            page = .problemTimes
        case .goalInsight:
            page = .distractions
        case .name:
            page = .motivation
        case .capabilities:
            page = .name
        case .valueOverview:
            page = .capabilities
        case .notifications, .distractionSetup, .success:
            break
        }
    }

    private func restoreDraft() {
        name = onboarding.progress.draftSetupConfiguration["name"]
            ?? authentication.displayName
            ?? ""
        goals = Set(onboarding.progress.draftPersonalizationAnswers)
        if let savedDistractions = onboarding.progress.draftSetupConfiguration["distractions"] {
            distractions = Set(savedDistractions.split(separator: "|").map(String.init))
        }
        if let savedProblemTimes = onboarding.progress.draftSetupConfiguration["problemTimes"] {
            problemTimes = Set(savedProblemTimes.split(separator: "|").map(String.init))
        }
        if let savedMotivations = onboarding.progress.draftSetupConfiguration["motivations"] {
            motivations = Set(savedMotivations.split(separator: "|").map(String.init))
        }

        if onboarding.progress.hasCompletedInitialSetup {
            page = .success
        } else if onboarding.progress.hasSeenPricingPreview {
            page = onboarding.progress.hasSeenNotificationExplainer
                ? .distractionSetup : .notifications
        } else if onboarding.progress.hasSeenValueOverview {
            page = .valueOverview
        } else if onboarding.progress.hasSeenCapabilitiesExplainer {
            page = .valueOverview
        } else if onboarding.progress.hasCompletedName {
            page = authentication.isAuthenticated ? .capabilities : .name
        } else if onboarding.progress.hasCompletedMotivation {
            page = .name
        } else if onboarding.progress.hasCompletedProblemTimes {
            page = .motivation
        } else if onboarding.progress.hasCompletedDistractions {
            page = .goalInsight
        } else if onboarding.progress.hasCompletedGoals {
            page = .distractions
        } else {
            page = .goals
        }
    }

    private var canMoveBack: Bool {
        switch page {
        case .distractions, .problemTimes, .motivation, .goalInsight, .name, .capabilities, .valueOverview:
            true
        case .goals, .notifications, .distractionSetup, .success:
            false
        }
    }

    private var selectionCountText: String {
        restrictions.selectedItemCount == 0
            ? "0 selected"
            : "\(selectedDistractionSummary) selected"
    }

    private var selectedDistractionSummary: String {
        let count = restrictions.selectedItemCount
        return "\(count) distraction\(count == 1 ? "" : "s")"
    }

    private var distractionSetupMessage: String {
        let callback = onboarding.progress.primaryDistraction.map {
            "You mentioned \($0.rawValue.lowercased()). "
        } ?? ""
        if restrictions.hasSelection {
            return "\(callback)Your selection is saved and ready. You can edit it before continuing."
        }
        return "\(callback)Pick the apps, categories, and websites you want Noxa to help you stay away from."
    }

    private var targetSuggestionMessage: String {
        let context: String
        switch onboarding.progress.primaryGoal {
        case .studying:
            context = "For study time,"
        case .work:
            context = "For work time,"
        case .sleep:
            context = "For bedtime,"
        default:
            context = "To protect your attention,"
        }

        let targets: String
        switch onboarding.progress.primaryDistraction {
        case .shortFormMedia:
            targets = "short-video apps and sites"
        case .longFormMedia:
            targets = "video and streaming apps or sites"
        case .webBrowsing:
            targets = "websites you tend to browse without a plan"
        case .playingGames:
            targets = "games or game categories"
        case .socialMedia:
            targets = "social apps and sites"
        case .other, .none:
            targets = "the apps, categories, or sites that pull you away"
        }
        return "\(context) consider selecting \(targets). You decide what Noxa blocks."
    }

    private var personalizedSuccessMessage: String {
        let preferredName = (onboarding.progress.preferredName ?? name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nameSuffix = preferredName.isEmpty ? "." : ", \(preferredName)."
        let message: String
        switch onboarding.progress.desiredBenefit {
        case .betterWorkOrStudy:
            message = "Let’s give you more uninterrupted time to focus"
        case .betterSleep:
            message = "Let’s make more room for calmer evenings and better rest"
        case .beingPresent, .strongerRelationships:
            message = "Let’s make more room to be present"
        case .lessStress:
            message = "Let’s create a little more calm in your day"
        case .moreTime:
            message = "Let’s give you more of your time back"
        case nil:
            message = "Let’s give you more of your time back"
        }
        return message + nameSuffix
    }

}

private extension ScreenTimeAuthorizationState {
    var isApproved: Bool {
        self == .approved || self == .approvedWithDataAccess
    }
}
