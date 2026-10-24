import Combine
import Foundation
import Supabase

struct AuthenticationInputValidator {
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func validate(email: String, password: String) -> String? {
        let email = normalizedEmail(email)
        guard email.contains("@"), email.contains(".") else {
            return "Enter a valid email address."
        }
        guard password.count >= 8 else {
            return "Your password must contain at least 8 characters."
        }
        return nil
    }
}

@MainActor
final class AuthenticationService: ObservableObject {
    @Published private(set) var isBootstrapping = true
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isBusy = false
    @Published private(set) var userID: UUID?
    @Published private(set) var userEmail: String?
    @Published private(set) var displayName: String?
    @Published private(set) var hasCompletedOnboarding = false
    @Published private(set) var rememberedUserEmail: String?
    @Published private(set) var rememberedDisplayName: String?
    @Published private(set) var confirmationEmail: String?
    @Published private(set) var requiresEmailConfirmation = false
    @Published var isPasswordRecoveryPresented = false
    @Published var message: String?

    private let client: SupabaseClient
    private let defaults: UserDefaults
    private var authStateTask: Task<Void, Never>?

    private enum RememberedAccountKey {
        static let email = "noxa.rememberedAccount.email"
        static let displayName = "noxa.rememberedAccount.displayName"
    }

    var hasRememberedAccount: Bool {
        rememberedUserEmail != nil || rememberedDisplayName != nil
    }

    init(client: SupabaseClient? = nil, defaults: UserDefaults = .standard) {
        self.client = client ?? SupabaseProvider.client
        self.defaults = defaults
        rememberedUserEmail = defaults.string(forKey: RememberedAccountKey.email)
        rememberedDisplayName = defaults.string(forKey: RememberedAccountKey.displayName)
        let authClient = self.client
        authStateTask = Task { [weak self] in
            for await change in authClient.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                self?.handleAuthChange(event: change.event, session: change.session)
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func bootstrap() async {
        defer { isBootstrapping = false }
        do {
            let session = try await client.auth.session
            apply(session: session)
        } catch {
            isAuthenticated = false
            userID = nil
            userEmail = nil
            displayName = nil
            hasCompletedOnboarding = false
        }
    }

    func signIn(email: String, password: String) async {
        guard let validatedEmail = validatedEmail(email, password: password) else { return }
        await perform {
            let session = try await self.client.auth.signIn(
                email: validatedEmail,
                password: password
            )
            self.apply(session: session)
            self.confirmationEmail = nil
            self.requiresEmailConfirmation = false
            self.message = nil
        }

        if message == "Confirm your email address before signing in." {
            confirmationEmail = validatedEmail
            requiresEmailConfirmation = true
        }
    }

    func signUp(email: String, password: String) async {
        guard let validatedEmail = validatedEmail(email, password: password) else { return }
        await perform {
            let response = try await self.client.auth.signUp(
                email: validatedEmail,
                password: password
            )

            if let session = response.session {
                self.apply(session: session)
                self.confirmationEmail = nil
                self.requiresEmailConfirmation = false
                self.message = nil
            } else {
                self.isAuthenticated = false
                self.userID = nil
                self.userEmail = nil
                self.displayName = nil
                self.hasCompletedOnboarding = false
                self.confirmationEmail = validatedEmail
                self.requiresEmailConfirmation = true
                self.message = "Check your email to confirm your account, then return here to sign in."
            }
        }
    }

    func resendConfirmationEmail() async {
        guard let confirmationEmail else { return }

        await perform {
            try await self.client.auth.resend(email: confirmationEmail, type: .signup)
            self.message = "A new confirmation email was sent. Check your inbox and spam folder."
        }
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        fullName: PersonNameComponents?
    ) async {
        await perform {
            let session = try await self.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: identityToken,
                    nonce: rawNonce
                )
            )
            self.apply(session: session)

            if let fullName, let displayName = PersonNameComponentsFormatter().string(from: fullName).nilIfEmpty {
                _ = try? await self.client.auth.update(
                    user: .init(data: ["full_name": .string(displayName)])
                )
            }
            self.message = nil
        }
    }

    func signOut() async {
        rememberCurrentAccount()
        await perform {
            try await self.client.auth.signOut()
            self.isAuthenticated = false
            self.userID = nil
            self.userEmail = nil
            self.displayName = nil
            self.hasCompletedOnboarding = false
            self.confirmationEmail = nil
            self.requiresEmailConfirmation = false
            self.message = nil
        }
    }

    /// Deletes the authenticated Supabase user through the server-side Edge
    /// Function. The service-role credential is never present in the app.
    func deleteAccount() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }

        do {
            try await client.functions.invoke("delete-account")
            try? await client.auth.signOut()
            forgetRememberedAccount()
            isAuthenticated = false
            userID = nil
            userEmail = nil
            displayName = nil
            hasCompletedOnboarding = false
            message = nil
            return true
        } catch {
            message = "Your account could not be deleted right now. Please try again."
            return false
        }
    }

    func sendPasswordReset(to email: String) async {
        let normalizedEmail = AuthenticationInputValidator.normalizedEmail(email)
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            message = "Enter a valid email address."
            return
        }

        await perform {
            try await self.client.auth.resetPasswordForEmail(
                normalizedEmail,
                redirectTo: SupabaseProvider.authCallbackURL
            )
            self.message = "If an account exists for that email, a password-reset link is on its way."
        }
    }

    func handleAuthCallback(_ url: URL) async {
        guard url.scheme == "noxa", url.host == "auth-callback" else { return }
        await perform {
            let session = try await self.client.auth.session(from: url)
            self.apply(session: session)
            self.confirmationEmail = nil
            self.requiresEmailConfirmation = false
            self.message = nil
        }
    }

    func updateRecoveredPassword(_ password: String) async {
        guard password.count >= 8 else {
            message = "Your password must contain at least 8 characters."
            return
        }

        await perform {
            _ = try await self.client.auth.update(user: .init(password: password))
            self.isPasswordRecoveryPresented = false
            self.message = nil
        }
    }

    func forgetRememberedAccount() {
        rememberedUserEmail = nil
        rememberedDisplayName = nil
        defaults.removeObject(forKey: RememberedAccountKey.email)
        defaults.removeObject(forKey: RememberedAccountKey.displayName)
    }

    /// Stores non-sensitive onboarding preferences in Supabase Auth metadata.
    /// Local onboarding remains authoritative so an offline user is never
    /// prevented from reaching the subscription screen.
    @discardableResult
    func syncOnboardingProfile(_ progress: OnboardingProgress) async -> Bool {
        guard isAuthenticated else { return false }
        let name = progress.draftSetupConfiguration["name"] ?? ""
        let goals = progress.draftPersonalizationAnswers
        let distractions = Self.answers(for: "distractions", in: progress)
        let problemTimes = Self.answers(for: "problemTimes", in: progress)
        let motivations = Self.answers(for: "motivations", in: progress)
        var metadata: [String: AnyJSON] = [
            "noxa_onboarding_complete": .bool(progress.isComplete),
            "noxa_goals": .array(goals.map(AnyJSON.string)),
            "noxa_distractions": .array(distractions.map(AnyJSON.string)),
            "noxa_problem_times": .array(problemTimes.map(AnyJSON.string)),
            "noxa_motivations": .array(motivations.map(AnyJSON.string))
        ]
        if !name.isEmpty {
            metadata["full_name"] = .string(name)
        }

        do {
            let user = try await client.auth.update(
                user: .init(data: metadata)
            )
            apply(user: user)
            return true
        } catch {
            return false
        }
    }

    private func validatedEmail(_ email: String, password: String) -> String? {
        if let validationMessage = AuthenticationInputValidator.validate(email: email, password: password) {
            message = validationMessage
            return nil
        }
        return AuthenticationInputValidator.normalizedEmail(email)
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            message = Self.userFacingMessage(for: error)
        }
    }

    private func apply(session: Session) {
        isAuthenticated = true
        userID = session.user.id
        userEmail = session.user.email
        apply(user: session.user)
    }

    private func apply(user: User) {
        displayName = user.userMetadata["full_name"]?.stringValue
        hasCompletedOnboarding = user.userMetadata["noxa_onboarding_complete"]?.boolValue ?? false
        rememberCurrentAccount()
    }

    private func rememberCurrentAccount() {
        if let email = userEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            rememberedUserEmail = email
            defaults.set(email, forKey: RememberedAccountKey.email)
        }
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            rememberedDisplayName = name
            defaults.set(name, forKey: RememberedAccountKey.displayName)
        }
    }

    private func handleAuthChange(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedOut:
            isAuthenticated = false
            userID = nil
            userEmail = nil
            displayName = nil
            hasCompletedOnboarding = false
            confirmationEmail = nil
            requiresEmailConfirmation = false
        case .userDeleted:
            forgetRememberedAccount()
            isAuthenticated = false
            userID = nil
            userEmail = nil
            displayName = nil
            hasCompletedOnboarding = false
            confirmationEmail = nil
            requiresEmailConfirmation = false
        case .passwordRecovery:
            if let session {
                apply(session: session)
            }
            isPasswordRecoveryPresented = true
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            if let session {
                apply(session: session)
            }
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("invalid login credentials") {
            return "The email or password is incorrect."
        }
        if description.localizedCaseInsensitiveContains("email not confirmed") {
            return "Confirm your email address before signing in."
        }
        if description.localizedCaseInsensitiveContains("already registered") {
            return "An account already exists for this email address."
        }
        return description
    }

    private static func answers(for key: String, in progress: OnboardingProgress) -> [String] {
        progress.draftSetupConfiguration[key]?
            .split(separator: "|")
            .map(String.init) ?? []
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
