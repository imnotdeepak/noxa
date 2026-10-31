import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AuthenticationView: View {
    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
    }

    private enum CredentialField {
        case email
        case password
    }

    @EnvironmentObject private var authentication: AuthenticationService
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var currentAppleNonce: String?
    @State private var isPasswordResetPresented = false
    @State private var hasFocusedPassword = false
    @State private var hasEditedPassword = false
    @State private var hasBlurredPassword = false
    @FocusState private var focusedCredentialField: CredentialField?

    private let onBack: (() -> Void)?
    private let isPreview: Bool
    private let onPreviewContinue: (() -> Void)?

    init(initialMode: Mode = .signIn, initialEmail: String = "", onBack: (() -> Void)? = nil,
         isPreview: Bool = false, onPreviewContinue: (() -> Void)? = nil) {
        _mode = State(initialValue: initialMode)
        _email = State(initialValue: initialEmail)
        self.onBack = onBack
        self.isPreview = isPreview
        self.onPreviewContinue = onPreviewContinue
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 44)

                VStack(spacing: 10) {
                    Text("noxa")
                        .font(NoxaTheme.font(18, weight: .medium, relativeTo: .headline))
                        .foregroundStyle(.secondary)
                    Text(mode == .signIn ? "Welcome back." : "Create your Noxa account.")
                        .font(NoxaTheme.font(40, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-1)
                        .multilineTextAlignment(.center)
                    Text(mode == .signIn
                         ? "Sign in to continue to your focus tools."
                         : "Keep your setup and progress connected to you.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 18) {
                    Picker("Authentication mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 12) {
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.emailAddress)
                            .submitLabel(.next)
                            .noxaAuthenticationField()
                            .focused($focusedCredentialField, equals: .email)

                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .submitLabel(.go)
                            .noxaAuthenticationField()
                            .focused($focusedCredentialField, equals: .password)
                            .onSubmit(submitEmailForm)
                            .onChange(of: password) { value in
                                if !value.isEmpty {
                                    hasEditedPassword = true
                                }
                            }
                    }

                    if let emailValidationMessage {
                        Text(emailValidationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let passwordGuidanceText {
                        Text(passwordGuidanceText)
                            .font(.footnote)
                            .foregroundStyle(shouldShowPasswordError ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: submitEmailForm) {
                        HStack(spacing: 10) {
                            Spacer()
                            Text(mode.rawValue)
                            if authentication.isBusy {
                                ProgressView()
                                    .tint(.black)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(NoxaPrimaryButtonStyle())
                    .disabled(isPreview || authentication.isBusy || !canSubmitEmailForm)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            isPasswordResetPresented = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .disabled(isPreview || authentication.isBusy)
                    }

                    HStack {
                        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                        Text("OR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                    }

                    SignInWithAppleButton(mode == .createAccount ? .signUp : .signIn) { request in
                        let nonce = AppleNonce.make()
                        currentAppleNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = AppleNonce.sha256(nonce)
                    } onCompletion: { result in
                        handleAppleResult(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .disabled(isPreview || authentication.isBusy)

                    if let message = authentication.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(isPositiveAuthenticationMessage(message) ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if authentication.requiresEmailConfirmation {
                        Button("Resend confirmation email") {
                            Task {
                                await authentication.resendConfirmationEmail()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .disabled(isPreview || authentication.isBusy)
                    }

                    if isPreview {
                        Text("Preview only — your account stays signed in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Continue preview", action: { onPreviewContinue?() })
                            .buttonStyle(NoxaPrimaryButtonStyle())
                    }
                }
                .padding(22)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(NoxaTheme.border, lineWidth: 1)
                }

                LegalLinksView()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .font(NoxaTheme.font(17))
        .background(NoxaOnboardingBackground())
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(NoxaTheme.primaryText)
                .padding(.leading, 12)
                .accessibilityLabel("Back")
                .disabled(authentication.isBusy)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: mode) { _ in
            if !isPreview { authentication.message = nil }
        }
        .onChange(of: focusedCredentialField) { field in
            if field == .password {
                hasFocusedPassword = true
            } else if hasFocusedPassword, password.count < 8 {
                hasBlurredPassword = true
            }
        }
        .sheet(isPresented: $isPasswordResetPresented) {
            PasswordResetRequestView(initialEmail: email)
        }
    }

    private func submitEmailForm() {
        guard canSubmitEmailForm else {
            authentication.message = AuthenticationInputValidator.validate(email: email, password: password)
            return
        }
        Task {
            switch mode {
            case .signIn:
                await authentication.signIn(email: email, password: password)
            case .createAccount:
                await authentication.signUp(email: email, password: password)
            }
        }
    }

    private var canSubmitEmailForm: Bool {
        AuthenticationInputValidator.validate(email: email, password: password) == nil
    }

    private var emailValidationMessage: String? {
        guard !email.isEmpty else { return nil }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            return "Enter a valid email address."
        }
        return nil
    }

    private var passwordGuidanceText: String? {
        guard password.count < 8 else { return nil }
        return shouldShowPasswordError
            ? "Password must contain at least 8 characters."
            : "At least 8 characters"
    }

    private var shouldShowPasswordError: Bool {
        hasEditedPassword || hasBlurredPassword
    }

    private func isPositiveAuthenticationMessage(_ message: String) -> Bool {
        message.hasPrefix("Check your email") || message.hasPrefix("A new confirmation email")
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentAppleNonce
            else {
                authentication.message = "Apple did not return a usable identity token. Please try again."
                return
            }

            Task {
                await authentication.signInWithApple(
                    identityToken: identityToken,
                    rawNonce: nonce,
                    fullName: credential.fullName
                )
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                authentication.message = error.localizedDescription
            }
        }
    }
}

private struct PasswordResetRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authentication: AuthenticationService
    @State private var email: String

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Reset your password")
                    .font(NoxaTheme.font(30, weight: .bold, relativeTo: .largeTitle))
                Text("We’ll email you a secure link that opens Noxa so you can choose a new password.")
                    .foregroundStyle(.secondary)

                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .noxaAuthenticationField()

                Button("Send Reset Link") {
                    Task {
                        await authentication.sendPasswordReset(to: email)
                    }
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(authentication.isBusy)

                if let message = authentication.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.hasPrefix("If an account") ? .green : .red)
                }

                Spacer()
            }
            .padding(20)
            .background(NoxaBackground())
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PasswordUpdateView: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a new password")
                    .font(NoxaTheme.font(30, weight: .bold, relativeTo: .largeTitle))
                Text("Use at least 8 characters.")
                    .foregroundStyle(.secondary)

                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                    .noxaAuthenticationField()
                SecureField("Confirm password", text: $confirmation)
                    .textContentType(.newPassword)
                    .noxaAuthenticationField()

                Button("Update Password") {
                    guard password == confirmation else {
                        authentication.message = "The passwords do not match."
                        return
                    }
                    Task {
                        await authentication.updateRecoveredPassword(password)
                    }
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(authentication.isBusy || password.isEmpty || confirmation.isEmpty)

                if let message = authentication.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(20)
            .background(NoxaBackground())
            .preferredColorScheme(.dark)
            .interactiveDismissDisabled()
        }
    }
}

private enum AppleNonce {
    static func make(length: Int = 32) -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else {
                fatalError("Unable to generate a secure Apple sign-in nonce.")
            }

            for byte in randomBytes where remaining > 0 {
                if byte < characters.count {
                    result.append(characters[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension View {
    func noxaAuthenticationField() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}
