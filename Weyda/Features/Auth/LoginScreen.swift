import AuthenticationServices
import SwiftUI

/// Connexion (étape `login` de la feuille) — portage de `LoginRoute` / `LoginScreen` (Android) : e-mail, mot de passe,
/// « Mot de passe oublié ? », puis Apple et Google (qui créent le compte s'il n'existe pas) et le lien vers
/// l'inscription. Une connexion réussie ouvre la session : la feuille, qui la suit, se ferme d'elle-même.
struct LoginView: View {
    @EnvironmentObject private var container: AppContainer
    private let onRegister: () -> Void
    private let onForgotPassword: () -> Void
    private let onOpenPage: (WebPage) -> Void

    init(
        onRegister: @escaping () -> Void,
        onForgotPassword: @escaping () -> Void,
        onOpenPage: @escaping (WebPage) -> Void
    ) {
        self.onRegister = onRegister
        self.onForgotPassword = onForgotPassword
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        LoginHost(
            model: LoginViewModel(auth: container.auth, social: SocialSignIn(auth: container.auth)),
            onRegister: onRegister,
            onForgotPassword: onForgotPassword,
            onOpenPage: onOpenPage
        )
    }
}

/// Possède le ViewModel ; liaisons de texte lues et écrites sur le fil principal (comme celles d'`AppRouter`).
private struct LoginHost: View {
    @StateObject private var model: LoginViewModel
    private let onRegister: () -> Void
    private let onForgotPassword: () -> Void
    private let onOpenPage: (WebPage) -> Void

    init(
        model: @autoclosure @escaping () -> LoginViewModel,
        onRegister: @escaping () -> Void,
        onForgotPassword: @escaping () -> Void,
        onOpenPage: @escaping (WebPage) -> Void
    ) {
        _model = StateObject(wrappedValue: model())
        self.onRegister = onRegister
        self.onForgotPassword = onForgotPassword
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        LoginScreen(
            state: model.state,
            email: binding(.email),
            password: binding(.password),
            showsGoogle: model.social.showsGoogle,
            isAppleSimulated: model.social.isAppleSimulated,
            actions: actions
        )
        // Saisie en cours : la feuille ne se ferme plus d'un glissement (« Fermer » reste là).
        .interactiveDismissDisabled(model.state.keepsSheetOpen)
    }

    private var actions: LoginActions {
        let model = self.model
        return LoginActions(
            submit: { _ = model.submit() },
            register: onRegister,
            forgotPassword: onForgotPassword,
            social: AuthSocialActions(
                appleRequest: { request in model.prepareApple(request) },
                appleCompletion: { result in _ = model.completeApple(result) },
                appleSimulated: { _ = model.continueWithSimulatedApple() },
                google: { _ = model.continueWithGoogle() },
                openPage: onOpenPage
            )
        )
    }

    private func binding(_ field: LoginField) -> Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.value(of: field) } },
            set: { value in MainActor.assumeIsolated { model.update(field, to: value) } }
        )
    }
}

/// Actions de l'écran de connexion.
struct LoginActions {
    var submit: () -> Void
    var register: () -> Void
    var forgotPassword: () -> Void
    var social: AuthSocialActions
}

/// Formulaire de connexion, sans état propre (hors focus) : « Suivant » passe au mot de passe, « Aller » envoie.
struct LoginScreen: View {
    private let state: LoginState
    @Binding private var email: String
    @Binding private var password: String
    private let showsGoogle: Bool
    private let isAppleSimulated: Bool
    private let actions: LoginActions
    @FocusState private var focus: LoginField?

    init(
        state: LoginState,
        email: Binding<String>,
        password: Binding<String>,
        showsGoogle: Bool,
        isAppleSimulated: Bool,
        actions: LoginActions
    ) {
        self.state = state
        _email = email
        _password = password
        self.showsGoogle = showsGoogle
        self.isAppleSimulated = isAppleSimulated
        self.actions = actions
    }

    var body: some View {
        AuthScaffold(screen: "login") {
            AuthHeader(title: L10n.authLoginTitle, subtitle: L10n.authLoginSubtitle)
            AuthTextField(
                L10n.authEmail,
                text: $email,
                focus: $focus,
                field: .email,
                error: state.emailError,
                kind: .email,
                isEnabled: !state.isBusy
            )
            .submitLabel(.next)
            .onSubmit { focus = .password }
            PasswordField(
                L10n.authPassword,
                text: $password,
                focus: $focus,
                field: .password,
                error: state.passwordError,
                isEnabled: !state.isBusy
            )
            .submitLabel(.go)
            .onSubmit(submit)
            forgotLink
            if let message = state.errorMessage {
                ErrorBanner(message: message)
                    .padding(.bottom, WeydaSpace.md)
            }
            SubmitButton(
                L10n.authLoginButton,
                isEnabled: state.canSubmit,
                isLoading: state.isSubmitting,
                action: submit
            )
            AuthSocialSection(
                isAppleSimulated: isAppleSimulated,
                showsGoogle: showsGoogle,
                isSubmitting: state.isSubmitting,
                isAppleSubmitting: state.isAppleSubmitting,
                isGoogleSubmitting: state.isGoogleSubmitting,
                actions: actions.social
            )
            AuthSwitchLine(prompt: L10n.authNoAccount, action: L10n.authRegisterLink, onTap: actions.register)
        }
    }

    /// « Mot de passe oublié ? » au bord de fin, sous le champ (Android : TextButton aligné à la fin).
    private var forgotLink: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: actions.forgotPassword) {
                Text(L10n.authForgotLink)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.primary)
                    .frame(minHeight: WeydaSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("auth.forgot")
        }
        .padding(.top, -WeydaSpace.sm)
        .padding(.bottom, WeydaSpace.xs)
    }

    /// Le clavier se range : le bandeau d'erreur éventuel reste visible.
    private func submit() {
        focus = nil
        actions.submit()
    }
}
