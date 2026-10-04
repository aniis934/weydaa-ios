import AuthenticationServices
import SwiftUI

/// Inscription (étape `register` de la feuille) — portage de `RegisterRoute` / `RegisterScreen` (Android) : nom,
/// e-mail, mot de passe (règles affichées), téléphone facultatif, puis Apple et Google, l'acceptation des conditions
/// et le lien vers la connexion. Compte créé → session ouverte → la feuille passe au code e-mail.
struct RegisterView: View {
    @EnvironmentObject private var container: AppContainer
    private let onLogin: () -> Void
    private let onOpenPage: (WebPage) -> Void

    init(onLogin: @escaping () -> Void, onOpenPage: @escaping (WebPage) -> Void) {
        self.onLogin = onLogin
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        RegisterHost(
            model: RegisterViewModel(auth: container.auth, social: SocialSignIn(auth: container.auth)),
            onLogin: onLogin,
            onOpenPage: onOpenPage
        )
    }
}

private struct RegisterHost: View {
    @StateObject private var model: RegisterViewModel
    private let onLogin: () -> Void
    private let onOpenPage: (WebPage) -> Void

    init(
        model: @autoclosure @escaping () -> RegisterViewModel,
        onLogin: @escaping () -> Void,
        onOpenPage: @escaping (WebPage) -> Void
    ) {
        _model = StateObject(wrappedValue: model())
        self.onLogin = onLogin
        self.onOpenPage = onOpenPage
    }

    var body: some View {
        RegisterScreen(
            state: model.state,
            name: binding(.name),
            email: binding(.email),
            password: binding(.password),
            phone: binding(.phone),
            showsGoogle: model.social.showsGoogle,
            isAppleSimulated: model.social.isAppleSimulated,
            actions: actions
        )
        // Saisie en cours : la feuille ne se ferme plus d'un glissement (« Fermer » reste là).
        .interactiveDismissDisabled(model.state.keepsSheetOpen)
        .onAppear {
            // Captures (Debug) : `-WeydaAuthDemo invalid` montre le formulaire en erreur.
            model.applyCaptureDemo(LaunchOptions.authDemo)
        }
    }

    private var actions: RegisterActions {
        let model = self.model
        return RegisterActions(
            submit: { _ = model.submit() },
            login: onLogin,
            social: AuthSocialActions(
                appleRequest: { request in model.prepareApple(request) },
                appleCompletion: { result in _ = model.completeApple(result) },
                appleSimulated: { _ = model.continueWithSimulatedApple() },
                google: { _ = model.continueWithGoogle() },
                openPage: onOpenPage
            )
        )
    }

    private func binding(_ field: RegisterField) -> Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.value(of: field) } },
            set: { value in MainActor.assumeIsolated { model.update(field, to: value) } }
        )
    }
}

/// Actions de l'écran d'inscription.
struct RegisterActions {
    var submit: () -> Void
    var login: () -> Void
    var social: AuthSocialActions
}

/// Formulaire d'inscription, sans état propre (hors focus). Le trousseau propose un mot de passe fort et
/// l'enregistre avec l'e-mail ; le pavé du téléphone n'a pas de touche « Aller » : on envoie par le bouton.
struct RegisterScreen: View {
    private let state: RegisterState
    @Binding private var name: String
    @Binding private var email: String
    @Binding private var password: String
    @Binding private var phone: String
    private let showsGoogle: Bool
    private let isAppleSimulated: Bool
    private let actions: RegisterActions
    @FocusState private var focus: RegisterField?

    init(
        state: RegisterState,
        name: Binding<String>,
        email: Binding<String>,
        password: Binding<String>,
        phone: Binding<String>,
        showsGoogle: Bool,
        isAppleSimulated: Bool,
        actions: RegisterActions
    ) {
        self.state = state
        _name = name
        _email = email
        _password = password
        _phone = phone
        self.showsGoogle = showsGoogle
        self.isAppleSimulated = isAppleSimulated
        self.actions = actions
    }

    var body: some View {
        AuthScaffold(screen: "register") {
            AuthHeader(title: L10n.authRegisterTitle, subtitle: L10n.authRegisterSubtitle)
            fields
            if let message = state.errorMessage {
                ErrorBanner(message: message)
                    .padding(.bottom, WeydaSpace.md)
            }
            SubmitButton(
                L10n.authRegisterButton,
                isEnabled: state.canSubmit,
                isLoading: state.isSubmitting,
                action: submit
            )
            .padding(.top, WeydaSpace.sm)
            AuthSocialSection(
                isAppleSimulated: isAppleSimulated,
                showsGoogle: showsGoogle,
                isSubmitting: state.isSubmitting,
                isAppleSubmitting: state.isAppleSubmitting,
                isGoogleSubmitting: state.isGoogleSubmitting,
                actions: actions.social
            )
            AuthSwitchLine(prompt: L10n.authHaveAccount, action: L10n.authLoginLink, onTap: actions.login)
        }
    }

    @ViewBuilder
    private var fields: some View {
        AuthTextField(
            L10n.authName,
            text: $name,
            focus: $focus,
            field: .name,
            error: state.nameError,
            kind: .name,
            isEnabled: !state.isBusy
        )
        .submitLabel(.next)
        .onSubmit { focus = .email }
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
            supporting: L10n.authPasswordRules,
            isNew: true,
            isEnabled: !state.isBusy
        )
        .submitLabel(.next)
        .onSubmit { focus = .phone }
        AuthTextField(
            L10n.authPhoneOptional,
            text: $phone,
            focus: $focus,
            field: .phone,
            error: state.phoneError,
            kind: .phone,
            isEnabled: !state.isBusy
        )
    }

    private func submit() {
        focus = nil
        actions.submit()
    }
}
