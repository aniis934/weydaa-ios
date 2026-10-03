import SwiftUI

/// « Changer le mot de passe » — portage de `ChangePasswordRoute` / `ChangePasswordScreen` : mot de passe actuel,
/// nouveau, confirmation. Succès : la session est fermée (déconnexion de tous les appareils, comme Android) ;
/// `AccountMemberGate` retire alors l'écran et l'onglet Profil invite à se reconnecter.
struct ChangePasswordView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.changePasswordTitle) { _ in
            ChangePasswordHost(model: ChangePasswordViewModel(users: container.users))
        }
    }
}

private struct ChangePasswordHost: View {
    @StateObject private var model: ChangePasswordViewModel

    init(model: @autoclosure @escaping () -> ChangePasswordViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        ChangePasswordScreen(
            state: model.state,
            currentPassword: binding(.currentPassword),
            newPassword: binding(.newPassword),
            confirmation: binding(.confirmation),
            onSubmit: { _ = model.submit() }
        )
    }

    /// Lue et écrite sur le fil principal (comme les liaisons d'`AppRouter`).
    private func binding(_ field: ChangePasswordField) -> Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.value(of: field) } },
            set: { value in MainActor.assumeIsolated { model.update(field, to: value) } }
        )
    }
}

/// Formulaire sans état propre (hors focus). Le trousseau propose un mot de passe fort pour le nouveau.
struct ChangePasswordScreen: View {
    private let state: ChangePasswordState
    @Binding private var currentPassword: String
    @Binding private var newPassword: String
    @Binding private var confirmation: String
    private let onSubmit: () -> Void
    @FocusState private var focus: ChangePasswordField?

    init(
        state: ChangePasswordState,
        currentPassword: Binding<String>,
        newPassword: Binding<String>,
        confirmation: Binding<String>,
        onSubmit: @escaping () -> Void
    ) {
        self.state = state
        _currentPassword = currentPassword
        _newPassword = newPassword
        _confirmation = confirmation
        self.onSubmit = onSubmit
    }

    var body: some View {
        AuthScaffold(screen: "changePassword") {
            Text(L10n.changePasswordBody)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, WeydaSpace.xl)
            PasswordField(
                L10n.changePasswordCurrent,
                text: $currentPassword,
                focus: $focus,
                field: .currentPassword,
                error: state.currentError,
                isEnabled: !state.isSubmitting
            )
            .submitLabel(.next)
            .onSubmit { focus = .newPassword }
            PasswordField(
                L10n.changePasswordNew,
                text: $newPassword,
                focus: $focus,
                field: .newPassword,
                error: state.newError,
                supporting: L10n.authPasswordRules,
                isNew: true,
                isEnabled: !state.isSubmitting
            )
            .submitLabel(.next)
            .onSubmit { focus = .confirmation }
            PasswordField(
                L10n.changePasswordConfirm,
                text: $confirmation,
                focus: $focus,
                field: .confirmation,
                error: state.confirmationError,
                isNew: true,
                isEnabled: !state.isSubmitting
            )
            .submitLabel(.go)
            .onSubmit { submit() }
            if let message = state.errorMessage {
                ErrorBanner(message: message)
                    .padding(.bottom, WeydaSpace.md)
            }
            SubmitButton(
                L10n.changePasswordSubmit,
                isEnabled: state.canSubmit,
                isLoading: state.isSubmitting,
                action: { submit() }
            )
            .padding(.top, WeydaSpace.sm)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        .navigationTitle(L10n.changePasswordTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        focus = nil
        onSubmit()
    }
}
