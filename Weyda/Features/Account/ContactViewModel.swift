import Foundation

/// Champs de « Nous contacter » (focus enchaîné, liaisons de texte).
nonisolated enum ContactField: Hashable, Sendable {
    case name
    case email
    case subject
    case message
}

/// État de « Nous contacter » — portage de `ContactUiState` (ContactScreen.kt).
nonisolated struct ContactState: Equatable, Sendable {
    var name: String = ""
    var email: String = ""
    var subject: String = ""
    var message: String = ""
    var nameError: String? = nil
    var emailError: String? = nil
    var subjectError: String? = nil
    var messageError: String? = nil
    var isSending: Bool = false
    /// Message parti : l'écran affiche la confirmation.
    var isSent: Bool = false
    var errorMessage: String? = nil

    // `contactSchema` du site (src/lib/validations.ts), longueurs en unités UTF-16 comme Zod.
    static let nameMin = 2
    static let nameMax = 100
    static let subjectMin = 3
    static let subjectMax = 200
    static let messageMin = 10
    static let messageMax = 5000
}

/// « Nous contacter » (`POST /api/contact`, comme la page Contact du site) — portage de `ContactViewModel` : la
/// demande arrive dans l'espace d'administration, la réponse part par e-mail. Nom et e-mail pré-remplis pour un
/// compte connecté ; ouvert aussi aux visiteurs. Comme Android, pas de repository : la route seule suffit.
final class ContactViewModel: ObservableObject {
    @Published private(set) var state: ContactState

    private let api: any WeydaAPI

    init(api: any WeydaAPI, user: User?) {
        self.api = api
        self.state = ContactState(name: user?.name ?? "", email: user?.email ?? "")
    }

    /// Saisie bornée au maximum du serveur (Android : `take`).
    func onName(_ value: String) {
        state.name = RepositorySupport.truncatedUTF16(value, max: ContactState.nameMax)
        state.nameError = nil
        state.errorMessage = nil
    }

    /// Une adresse ne contient pas d'espace : ceux qui s'y glissent (copier-coller) sont retirés aux bords.
    func onEmail(_ value: String) {
        state.email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        state.emailError = nil
        state.errorMessage = nil
    }

    func onSubject(_ value: String) {
        state.subject = RepositorySupport.truncatedUTF16(value, max: ContactState.subjectMax)
        state.subjectError = nil
        state.errorMessage = nil
    }

    func onMessage(_ value: String) {
        state.message = RepositorySupport.truncatedUTF16(value, max: ContactState.messageMax)
        state.messageError = nil
        state.errorMessage = nil
    }

    func value(of field: ContactField) -> String {
        switch field {
        case .name: state.name
        case .email: state.email
        case .subject: state.subject
        case .message: state.message
        }
    }

    func update(_ field: ContactField, to value: String) {
        switch field {
        case .name: onName(value)
        case .email: onEmail(value)
        case .subject: onSubject(value)
        case .message: onMessage(value)
        }
    }

    /// Règles du site (nom ≥ 2, e-mail, sujet ≥ 3, message ≥ 10, blancs de bord retirés), puis l'envoi. Succès :
    /// sujet et message effacés, confirmation. Échec : message global + erreurs de champ du serveur.
    @discardableResult
    func send() -> Task<Void, Never>? {
        let current = state
        guard !current.isSending else { return nil }
        let name = Self.trimmed(current.name)
        let email = Self.trimmed(current.email)
        let subject = Self.trimmed(current.subject)
        let message = Self.trimmed(current.message)
        let nameError: String? = name.utf16.count < ContactState.nameMin ? ValidationMessage.nameMin.text : nil
        let emailError: String? = Validators.email(email)?.text
        let subjectError: String? = subject.utf16.count < ContactState.subjectMin ? ValidationMessage.subjectMin.text : nil
        let messageError: String? = message.utf16.count < ContactState.messageMin ? ValidationMessage.messageMin.text : nil
        guard nameError == nil, emailError == nil, subjectError == nil, messageError == nil else {
            state.nameError = nameError
            state.emailError = emailError
            state.subjectError = subjectError
            state.messageError = messageError
            return nil
        }
        state.isSending = true
        state.errorMessage = nil
        let api = self.api
        let body = ContactRequestDTO(name: name, email: email, subject: subject, message: message)
        return Task { [weak self] in
            do {
                _ = try await api.contact(body)
                guard let self else { return }
                self.state.isSending = false
                self.state.isSent = true
                self.state.subject = ""
                self.state.message = ""
            } catch {
                guard let self else { return }
                let fields = ErrorMapper.fieldMessages(for: error)
                self.state.isSending = false
                self.state.errorMessage = ErrorMapper.message(for: error)
                self.state.nameError = fields["name"]
                self.state.emailError = fields["email"]
                self.state.subjectError = fields["subject"]
                self.state.messageError = fields["message"]
            }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
