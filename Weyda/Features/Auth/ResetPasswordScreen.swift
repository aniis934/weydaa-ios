import SwiftUI

/// Nouveau mot de passe (étape `resetPassword` de la feuille, lien de l'e-mail `/{locale}/auth/reinitialiser-mdp?token=…`)
/// — portage de `ResetPasswordRoute` / `ResetPasswordScreen` (Android) : nouveau mot de passe et confirmation, puis
/// « Mot de passe modifié » et « Se connecter ». Lien sans jeton : message, aucun champ.
struct ResetPasswordView: View {
    @EnvironmentObject private var container: AppContainer
    private let token: String
    private let onLogin: () -> Void

    init(token: String, onLogin: @escaping () -> Void) {
        self.token = token
        self.onLogin = onLogin
    }

    var body: some View {
        ResetPasswordHost(model: ResetPasswordViewModel(token: token, auth: container.auth), onLogin: onLogin)
    }
}

private struct ResetPasswordHost: View {
    @StateObject private var model: ResetPasswordViewModel
    private let onLogin: () -> Void

    init(model: @autoclosure @escaping () -> ResetPasswordViewModel, onLogin: @escaping () -> Void) {
        _model = StateObject(wrappedValue: model())
        self.onLogin = onLogin
    }

    var body: some View {
        ResetPasswordScreen(
            state: model.state,
            password: binding(.password),
            confirm: binding(.confirm),
            onSubmit: submitAction,
            onLogin: onLogin
        )
    }

    private var submitAction: () -> Void {
        let model = self.model
        return { _ = model.submit() }
    }

    private func binding(_ field: ResetPasswordField) -> Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.value(of: field) } },
            set: { value in MainActor.assumeIsolated { model.update(field, to: value) } }
        )
    }
}

/// Formulaire puis confirmation, sans état propre (hors focus). Les deux champs sont des « nouveaux mots de passe » :
/// le trousseau en propose un fort et remplit la confirmation.
struct ResetPasswordScreen: View {
    private let state: ResetPasswordState
    @Binding private var password: String
    @Binding private var confirm: String
    private let onSubmit: () -> Void
    private let onLogin: () -> Void
    @FocusState private var focus: ResetPasswordField?

    init(
        state: ResetPasswordState,
        password: Binding<String>,
        confirm: Binding<String>,
        onSubmit: @escaping () -> Void,
        onLogin: @escaping () -> Void
    ) {
        self.state = state
        _password = password
        _confirm = confirm
        self.onSubmit = onSubmit
        self.onLogin = onLogin
    }

    var body: some View {
        AuthScaffold(screen: "resetPassword") {
            if state.isDone {
                AuthConfirmation(
                    systemImage: "checkmark.circle.fill",
                    title: L10n.resetSuccessTitle,
                    message: L10n.resetSuccessBody
                )
                SubmitButton(L10n.authLoginButton, action: onLogin)
            } else {
                AuthHeader(title: L10n.resetTitle, subtitle: L10n.resetSubtitle)
                if state.invalidLink {
                    ErrorBanner(message: L10n.resetInvalidLink)
                } else {
                    form
                }
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        PasswordField(
            L10n.resetNewPassword,
            text: $password,
            focus: $focus,
            field: .password,
            error: state.passwordError,
            supporting: L10n.authPasswordRules,
            isNew: true,
            isEnabled: !state.isSubmitting
        )
        .submitLabel(.next)
        .onSubmit { focus = .confirm }
        PasswordField(
            L10n.resetConfirmPassword,
            text: $confirm,
            focus: $focus,
            field: .confirm,
            error: state.confirmError,
            isNew: true,
            isEnabled: !state.isSubmitting
        )
        .submitLabel(.go)
        .onSubmit(submit)
        if let message = state.errorMessage {
            ErrorBanner(message: message)
                .padding(.bottom, WeydaSpace.md)
        }
        SubmitButton(
            L10n.resetSubmit,
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
