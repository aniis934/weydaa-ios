import Foundation

/// Preuve demandée pour supprimer le compte : le mot de passe, ou une reconnexion fraîche au fournisseur qui a créé
/// le compte (Google : id_token ; Apple : jeton d'identité + nonce + code, que le serveur utilise aussi pour révoquer
/// l'accès Apple — exigence de l'App Store).
nonisolated enum AccountDeletionMethod: Hashable, Sendable {
    case password
    case google
    case apple

    /// Un mot de passe suffit toujours. Sinon le fournisseur lié au compte : Apple d'abord (toujours disponible sur
    /// iPhone, alors que Google demande un identifiant client), puis Google ; sans liste (serveur antérieur au lot A),
    /// Google, comme Android (« pas de mot de passe » = compte Google).
    static func resolve(hasPassword: Bool, providers: [String]?) -> AccountDeletionMethod {
        if hasPassword { return .password }
        let linked: Set<String> = Set((providers ?? []).map { $0.lowercased() })
        if linked.contains("apple") { return .apple }
        return .google
    }
}

/// Moyens de connexion du compte, relus sur le serveur (`GET /api/users/me` : `hasPassword`, `providers`).
nonisolated struct AccountSignInMethods: Hashable, Sendable {
    var hasPassword: Bool
    var providers: [String]?

    var deletionMethod: AccountDeletionMethod {
        AccountDeletionMethod.resolve(hasPassword: hasPassword, providers: providers)
    }
}

/// Champ de « Mes données » (focus).
nonisolated enum AccountDataField: Hashable, Sendable {
    case password
}

/// État de « Mes données » — portage d'`AccountDataUiState` (AccountDataScreen.kt).
nonisolated struct AccountDataState: Equatable, Sendable {
    var isExporting: Bool = false
    /// Dernier export téléchargé (`tmp/exports`), repartageable sans nouvel export (2 par 24 h).
    var exportFile: URL? = nil
    /// Export prêt dont la feuille de partage n'a pas encore été ouverte (consommé par `exportShared()`).
    var pendingShare: URL? = nil
    var exportError: String? = nil
    /// Preuve demandée pour la suppression ; d'abord d'après la session, puis d'après le serveur.
    var method: AccountDeletionMethod = .password
    var password: String = ""
    var isDeleting: Bool = false
    /// Boîte de confirmation affichée.
    var confirmDelete: Bool = false
    /// Échec de la suppression (mot de passe incorrect, reconnexion refusée…) ; nil = rien à signaler.
    var deleteError: String? = nil
    /// Compte effacé : la session est fermée, l'écran se retire (`AccountMemberGate`).
    var deleted: Bool = false

    /// « Supprimer » s'active avec un mot de passe saisi (compte à mot de passe) ou tout de suite (Google, Apple).
    var canAskDelete: Bool {
        guard !isDeleting else { return false }
        return method != .password || !TextCheck.isBlank(password)
    }
}

/// Portabilité (export JSON partagé) et droit à l'effacement (loi 18-07) — portage d'`AccountDataViewModel`.
/// La suppression se confirme par le mot de passe, ou par une reconnexion Google / Apple selon les moyens de
/// connexion du compte. Succès : `AccountDataRepository` ferme la session.
///
/// Les reconnexions et la relecture des moyens de connexion sont des fermetures : l'écran branche les vrais
/// coordinateurs du système, les tests des réponses écrites d'avance.
final class AccountDataViewModel: ObservableObject {
    @Published private(set) var state: AccountDataState

    private let accountData: AccountDataRepository
    private let loadSignInMethods: @MainActor () async throws -> AccountSignInMethods
    private let appleCredential: @MainActor () async throws -> AppleCredential
    private let googleIDToken: @MainActor () async throws -> String
    private var hasStarted = false

    /// `user` : l'utilisateur de session (son `hasPassword` choisit la preuve en attendant le serveur, comme Android).
    init(
        accountData: AccountDataRepository,
        user: User?,
        loadSignInMethods: @escaping @MainActor () async throws -> AccountSignInMethods,
        appleCredential: @escaping @MainActor () async throws -> AppleCredential,
        googleIDToken: @escaping @MainActor () async throws -> String
    ) {
        self.accountData = accountData
        self.loadSignInMethods = loadSignInMethods
        self.appleCredential = appleCredential
        self.googleIDToken = googleIDToken
        let method = AccountDeletionMethod.resolve(hasPassword: user?.hasPassword ?? true, providers: nil)
        self.state = AccountDataState(method: method)
    }

    /// Apparition de l'écran : moyens de connexion relus sur le serveur, une fois. Un échec garde la preuve déduite
    /// de la session (Android : `me().onSuccess` seulement).
    @discardableResult
    func loadIfNeeded() -> Task<Void, Never>? {
        guard !hasStarted else { return nil }
        hasStarted = true
        return Task { [weak self] in
            guard let self else { return }
            do {
                let methods = try await self.loadSignInMethods()
                self.state.method = methods.deletionMethod
            } catch {
                // Silencieux : la preuve déduite de la session reste valable.
            }
        }
    }

    // MARK: - Export

    /// Télécharge le JSON ; prêt → la feuille de partage s'ouvre (`pendingShare`). 429 au-delà de 2 exports / 24 h.
    @discardableResult
    func export() -> Task<Void, Never>? {
        guard !state.isExporting else { return nil }
        state.isExporting = true
        state.exportError = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await self.accountData.export()
                self.state.isExporting = false
                self.state.exportFile = file
                self.state.pendingShare = file
            } catch {
                self.state.isExporting = false
                self.state.exportError = ErrorMapper.message(for: error)
            }
        }
    }

    /// La feuille de partage est ouverte : elle ne se rouvrira pas d'elle-même (le fichier reste repartageable).
    func exportShared() {
        state.pendingShare = nil
    }

    // MARK: - Suppression

    func updatePassword(_ value: String) {
        state.password = value
        state.deleteError = nil
    }

    func askDelete() {
        guard state.canAskDelete else { return }
        state.deleteError = nil
        state.confirmDelete = true
    }

    func dismissDelete() {
        state.confirmDelete = false
    }

    /// Confirmé : preuve (mot de passe, ou reconnexion Google / Apple), puis `DELETE /api/users/me/account`. Une
    /// reconnexion annulée n'affiche rien ; un refus du serveur s'affiche sous le bouton, la session reste ouverte.
    @discardableResult
    func confirmDelete() -> Task<Void, Never>? {
        state.confirmDelete = false
        let current = state
        guard !current.isDeleting else { return nil }
        if current.method == .password && TextCheck.isBlank(current.password) { return nil }
        state.isDeleting = true
        state.deleteError = nil
        return Task { [weak self] in
            guard let self else { return }
            do {
                try await self.delete(using: current.method, password: current.password)
                // Le mot de passe quitte la mémoire dès qu'il a servi.
                self.state.isDeleting = false
                self.state.password = ""
                self.state.deleted = true
            } catch {
                self.state.isDeleting = false
                self.state.deleteError = ErrorMapper.message(for: error)
            }
        }
    }

    private func delete(using method: AccountDeletionMethod, password: String) async throws {
        switch method {
        case .password:
            try await accountData.deleteAccount(password: password)
        case .google:
            let idToken = try await googleIDToken()
            try await accountData.deleteGoogleAccount(idToken: idToken)
        case .apple:
            let credential = try await appleCredential()
            try await accountData.deleteAppleAccount(
                identityToken: credential.identityToken,
                nonce: credential.rawNonce,
                authorizationCode: credential.authorizationCode
            )
        }
    }
}
