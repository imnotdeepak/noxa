import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct AuthenticationView: View {
    enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
    }

    @EnvironmentObject private var authentication: AuthenticationService
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var currentAppleNonce: String?
    @State private var isPasswordResetPresented = false

    init(initialMode: Mode = .signIn) {
        _mode = State(initialValue: initialMode)
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
                         : "Save your Noxa setup and keep your progress synced.")
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

                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .submitLabel(.go)
                            .noxaAuthenticationField()
                            .onSubmit(submitEmailForm)
                    }

                    if let credentialValidationMessage {
                        Text(credentialValidationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
                    .disabled(authentication.isBusy || !canSubmitEmailForm)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            isPasswordResetPresented = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .disabled(authentication.isBusy)
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
                    .disabled(authentication.isBusy)

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
                        .disabled(authentication.isBusy)
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
        .preferredColorScheme(.dark)
        .onChange(of: mode) { _ in
            authentication.message = nil
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

    private var credentialValidationMessage: String? {
        guard !email.isEmpty || !password.isEmpty else { return nil }
        return AuthenticationInputValidator.validate(email: email, password: password)
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
