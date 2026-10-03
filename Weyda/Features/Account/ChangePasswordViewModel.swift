import Foundation

/// Champs de « Changer le mot de passe ».
nonisolated enum ChangePasswordField: Hashable, Sendable {
    case currentPassword
    case newPassword
    case confirmation
}

/// État de « Changer le mot de passe » — portage de `ChangePasswordUiState` (ProfileViewModels.kt).
nonisolated struct ChangePasswordState: Equatable, Sendable {
    var currentPassword: String = ""
    var newPassword: String = ""
    var confirmation: String = ""
    var currentError: String? = nil
    var newError: String? = nil
    var confirmationError: String? = nil
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    /// Succès : la session a été fermée côté app (`sessionVersion` changé côté serveur).
    var done: Bool = false

    var canSubmit: Bool {
        !isSubmitting && !currentPassword.isEmpty && !newPassword.isEmpty && !confirmation.isEmpty
    }
}

/// Changer le mot de passe — portage de `ChangePasswordViewModel`. Succès : le serveur invalide toutes les sessions
/// du compte et `UserRepository` ferme la session locale ; l'écran se retire et le Profil invite à se reconnecter.
final class ChangePasswordViewModel: ObservableObject {
    @Published private(set) var state = ChangePasswordState()

    private let users: UserRepository

    init(users: UserRepository) {
        self.users = users
    }

    func onCurrentChange(_ value: String) {
        state.currentPassword = value
        state.currentError = nil
        state.errorMessage = nil
    }

    /// Le nouveau mot de passe change : sa confirmation est à revoir aussi.
    func onNewChange(_ value: String) {
        state.newPassword = value
        state.newError = nil
        state.confirmationError = nil
        state.errorMessage = nil
    }

    func onConfirmationChange(_ value: String) {
        state.confirmation = value
        state.confirmationError = nil
        state.errorMessage = nil
    }

    func value(of field: ChangePasswordField) -> String {
        switch field {
        case .currentPassword: state.currentPassword
        case .newPassword: state.newPassword
        case .confirmation: state.confirmation
        }
    }

    func update(_ field: ChangePasswordField, to value: String) {
        switch field {
        case .currentPassword: onCurrentChange(value)
        case .newPassword: onNewChange(value)
        case .confirmation: onConfirmationChange(value)
        }
    }

    /// Règles locales (mot de passe actuel requis, nouveau : 8 caractères, une majuscule, un chiffre ; confirmation
    /// identique), puis `PUT /api/users/me/password`.
    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard !current.isSubmitting else { return nil }
        let currentError = Validators.passwordRequired(current.currentPassword)?.text
        let newError = Validators.password(current.newPassword)?.text
        let confirmationError: String? = current.confirmation != current.newPassword ? L10n.changePasswordMismatch : nil
        guard currentError == nil, newError == nil, confirmationError == nil else {
            state.currentError = currentError
            state.newError = newError
            state.confirmationError = confirmationError
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.users.changePassword(
                    current: current.currentPassword,
                    new: current.newPassword,
                    confirm: current.confirmation
                )
                // Les trois mots de passe quittent la mémoire dès qu'ils ont servi.
                self.state = ChangePasswordState(done: true)
            } catch {
                let fields = ErrorMapper.fieldMessages(for: error)
                self.state.isSubmitting = false
                self.state.errorMessage = ErrorMapper.message(for: error)
                self.state.currentError = fields["currentPassword"]
                self.state.newError = fields["newPassword"]
            }
        }
    }
}
