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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 44)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Noxa")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("Protect your\nattention.")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .tracking(-1)
                    Text("Sign in to continue to your focus tools.")
                        .foregroundStyle(.secondary)
                }

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

                    Button(action: submitEmailForm) {
                        HStack {
                            Text(mode.rawValue)
                            Spacer()
                            if authentication.isBusy {
                                ProgressView()
                                    .tint(.black)
                            }
                        }
                    }
                    .buttonStyle(AuthenticationPrimaryButtonStyle())
                    .disabled(authentication.isBusy)

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

                    SignInWithAppleButton(.signIn) { request in
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
                            .foregroundStyle(message.hasPrefix("Check your email") ? .green : .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: mode) { _ in
            authentication.message = nil
        }
        .sheet(isPresented: $isPasswordResetPresented) {
            PasswordResetRequestView(initialEmail: email)
        }
    }

    private func submitEmailForm() {
        Task {
            switch mode {
            case .signIn:
                await authentication.signIn(email: email, password: password)
            case .createAccount:
                await authentication.signUp(email: email, password: password)
            }
        }
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
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
                .buttonStyle(AuthenticationPrimaryButtonStyle())
                .disabled(authentication.isBusy)

                if let message = authentication.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.hasPrefix("If an account") ? .green : .red)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.black.ignoresSafeArea())
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
                    .font(.system(size: 30, weight: .bold, design: .rounded))
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
                .buttonStyle(AuthenticationPrimaryButtonStyle())
                .disabled(authentication.isBusy || password.isEmpty || confirmation.isEmpty)

                if let message = authentication.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.black.ignoresSafeArea())
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

private struct AuthenticationPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
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
