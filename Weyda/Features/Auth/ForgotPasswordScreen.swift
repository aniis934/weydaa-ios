import SwiftUI

/// « Mot de passe oublié » (étape `forgotPassword` de la feuille) — portage de `ForgotPasswordRoute` /
/// `ForgotPasswordScreen` (Android) : l'e-mail, puis la confirmation « Email envoyé » (pensez aux spams).
struct ForgotPasswordView: View {
    @EnvironmentObject private var container: AppContainer
    private let onLogin: () -> Void

    init(onLogin: @escaping () -> Void) {
        self.onLogin = onLogin
    }

    var body: some View {
        ForgotPasswordHost(model: ForgotPasswordViewModel(auth: container.auth), onLogin: onLogin)
    }
}

private struct ForgotPasswordHost: View {
    @StateObject private var model: ForgotPasswordViewModel
    private let onLogin: () -> Void

    init(model: @autoclosure @escaping () -> ForgotPasswordViewModel, onLogin: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.onLogin = onLogin
    }

    var body: some View {
        ForgotPasswordScreen(
            state: model.state,
            email: emailBinding,
            onSubmit: submitAction,
            onLogin: onLogin
        )
    }

    private var submitAction: () -> Void {
        let model = self.model
        return { _ = model.submit() }
    }

    private var emailBinding: Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.email } },
            set: { value in MainActor.assumeIsolated { model.onEmailChange(value) } }
        )
    }
}

/// Formulaire puis confirmation, sans état propre (hors focus).
struct ForgotPasswordScreen: View {
    private let state: ForgotPasswordState
    @Binding private var email: String
    private let onSubmit: () -> Void
    private let onLogin: () -> Void
    @FocusState private var focus: ForgotPasswordField?

    init(
        state: ForgotPasswordState,
        email: Binding<String>,
        onSubmit: @escaping () -> Void,
        onLogin: @escaping () -> Void
    ) {
        self.state = state
        _email = email
        self.onSubmit = onSubmit
        self.onLogin = onLogin
    }

    var body: some View {
        AuthScaffold(screen: "forgotPassword") {
            if let sentTo = state.sentTo {
                AuthConfirmation(
                    systemImage: "envelope.badge",
                    title: L10n.authForgotSentTitle,
                    message: L10n.authForgotSentBody(sentTo)
                )
                ForgotLoginButton(title: L10n.authLoginLink, action: onLogin)
            } else {
                form
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        AuthHeader(title: L10n.authForgotTitle, subtitle: L10n.authForgotBody)
        AuthTextField(
            L10n.authEmail,
            text: $email,
            focus: $focus,
            field: .email,
            error: state.emailError,
            kind: .email,
            isEnabled: !state.isSubmitting
        )
        .submitLabel(.send)
        .onSubmit(submit)
        if let message = state.errorMessage {
            ErrorBanner(message: message)
                .padding(.bottom, WeydaSpace.md)
        }
        SubmitButton(
            L10n.authForgotButton,
            isEnabled: state.canSubmit,
            isLoading: state.isSubmitting,
            action: submit
        )
        .padding(.top, WeydaSpace.sm)
    }

    private func submit() {
        focus = nil
        onSubmit()
    }
}

/// Bouton secondaire pleine largeur à contour (Android : `OutlinedButton` « Se connecter » après l'envoi).
private struct ForgotLoginButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: AppleSignInButton.height)
                .contentShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(WeydaColor.outline, lineWidth: 1)
                }
        }
        .buttonStyle(WeydaPressStyle())
        .accessibilityIdentifier("auth.login")
    }
}
