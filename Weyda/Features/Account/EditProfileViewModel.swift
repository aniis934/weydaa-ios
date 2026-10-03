import Foundation

/// Champs de « Modifier mon profil » (focus enchaîné, liaisons de texte).
nonisolated enum EditProfileField: Hashable, Sendable {
    case name
    case email
    case phone
    case bio
}

/// État de « Modifier mon profil » — portage d'`EditProfileUiState` (ProfileViewModels.kt).
nonisolated struct EditProfileState: Equatable, Sendable {
    var name: String = ""
    var email: String = ""
    var phone: String = ""
    var bio: String = ""
    var initialEmail: String = ""
    var nameError: String? = nil
    var emailError: String? = nil
    var phoneError: String? = nil
    var bioError: String? = nil
    var isSubmitting: Bool = false
    var errorMessage: String? = nil
    var saved: Bool = false
    /// Profil complet pas encore relu. `PUT /api/users/me` REMPLACE téléphone et bio (absents = effacés), or la
    /// session ne les connaît qu'après un `GET me` réussi (la réponse de connexion ne les porte pas) : enregistrer
    /// avant ce chargement effacerait les deux champs côté serveur.
    var isLoading: Bool = true
    var loadErrorMessage: String? = nil

    /// Longueur maximale de la bio (`updateProfileSchema`, 500 unités UTF-16 comme Zod).
    static let bioMax = 500

    var emailChanged: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != initialEmail
    }

    /// Les champs ne s'éditent qu'une fois le vrai profil affiché.
    var canEdit: Bool { !isLoading && loadErrorMessage == nil && !isSubmitting }

    var canSubmit: Bool { canEdit && !TextCheck.isBlank(name) && !TextCheck.isBlank(email) }

    /// « 57 / 500 » sous la bio.
    var bioCounter: String { "\(bio.utf16.count) / \(Self.bioMax)" }
}

/// Modifier le profil (nom, e-mail, téléphone +213, bio) — portage d'`EditProfileViewModel`. Pré-rempli depuis la
/// session pour un affichage immédiat ; le profil relu (`load`) fait foi et débloque l'envoi.
final class EditProfileViewModel: ObservableObject {
    @Published private(set) var state: EditProfileState

    private let users: UserRepository
    private var loadTask: Task<Void, Never>?
    private var hasStarted = false

    init(users: UserRepository, auth: AuthRepository) {
        self.users = users
        let user = auth.user
        self.state = EditProfileState(
            name: user?.name ?? "",
            email: user?.email ?? "",
            phone: user?.phone ?? "",
            bio: user?.bio ?? "",
            initialEmail: user?.email ?? ""
        )
    }

    /// Apparition de l'écran : relecture du profil complet, une fois.
    @discardableResult
    func loadIfNeeded() -> Task<Void, Never>? {
        guard !hasStarted else { return nil }
        hasStarted = true
        return load()
    }

    /// Relit le profil complet ; en cas d'échec l'envoi reste bloqué et l'écran propose de réessayer.
    @discardableResult
    func load() -> Task<Void, Never> {
        hasStarted = true
        loadTask?.cancel()
        state.isLoading = true
        state.loadErrorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let me = try await self.users.me()
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                self.state.name = me.name ?? ""
                self.state.email = me.email
                self.state.phone = me.phone ?? ""
                self.state.bio = me.bio ?? ""
                self.state.initialEmail = me.email
            } catch {
                guard !Task.isCancelled else { return }
                self.state.isLoading = false
                // Jamais d'édition sur un profil non relu, même pour une erreur sans message (annulation réseau).
                self.state.loadErrorMessage = ErrorMapper.message(for: error) ?? L10n.errorGeneric
            }
        }
        loadTask = task
        return task
    }

    func onNameChange(_ value: String) {
        state.name = value
        state.nameError = nil
        state.errorMessage = nil
    }

    func onEmailChange(_ value: String) {
        state.email = value
        state.emailError = nil
        state.errorMessage = nil
    }

    func onPhoneChange(_ value: String) {
        state.phone = value
        state.phoneError = nil
        state.errorMessage = nil
    }

    /// Saisie bornée un peu au-delà du maximum : le message d'erreur a de quoi s'afficher (Android : `take(550)`).
    func onBioChange(_ value: String) {
        state.bio = RepositorySupport.truncatedUTF16(value, max: EditProfileState.bioMax + 50)
        state.bioError = nil
        state.errorMessage = nil
    }

    func value(of field: EditProfileField) -> String {
        switch field {
        case .name: state.name
        case .email: state.email
        case .phone: state.phone
        case .bio: state.bio
        }
    }

    func update(_ field: EditProfileField, to value: String) {
        switch field {
        case .name: onNameChange(value)
        case .email: onEmailChange(value)
        case .phone: onPhoneChange(value)
        case .bio: onBioChange(value)
        }
    }

    /// Règles locales (nom, e-mail, mobile algérien, bio ≤ 500) puis `PUT /api/users/me` ; les erreurs de champ du
    /// serveur (Zod) reviennent sous les champs. Succès : `saved` (l'écran se ferme).
    @discardableResult
    func submit() -> Task<Void, Never>? {
        let current = state
        guard current.canEdit else { return nil }
        let nameError = Validators.name(current.name)?.text
        let emailError = Validators.email(current.email)?.text
        let phoneError = Validators.mobilePhone(current.phone)?.text
        let bioTooLong = current.bio.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > EditProfileState.bioMax
        let bioError: String? = bioTooLong ? ValidationMessage.bioMax.text : nil
        guard nameError == nil, emailError == nil, phoneError == nil, bioError == nil else {
            state.nameError = nameError
            state.emailError = emailError
            state.phoneError = phoneError
            state.bioError = bioError
            return nil
        }
        state.isSubmitting = true
        state.errorMessage = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.users.updateProfile(
                    name: current.name,
                    email: current.email,
                    phone: Validators.normalizePhone(current.phone),
                    bio: current.bio
                )
                self.state.isSubmitting = false
                self.state.saved = true
            } catch {
                let fields = ErrorMapper.fieldMessages(for: error)
                self.state.isSubmitting = false
                self.state.errorMessage = fields.isEmpty ? ErrorMapper.message(for: error) : nil
                self.state.nameError = fields["name"]
                self.state.emailError = fields["email"]
                self.state.phoneError = fields["phone"]
            }
        }
    }
}
