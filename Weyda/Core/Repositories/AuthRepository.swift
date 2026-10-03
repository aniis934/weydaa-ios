import Foundation

/// Connexion / inscription / vérification d'e-mail / mot de passe oublié — portage d'`AuthRepository`. Les routes
/// de jetons passent par le client SANS Bearer (`LiveWeydaAPI.authClient`), les autres par le client authentifié.
final class AuthRepository {
    private let api: any WeydaAPI
    private let session: SessionManager
    /// E-mail inscrit avec succès depuis ce lancement (voir `register`).
    private var registeredEmail: String?

    init(api: any WeydaAPI, session: SessionManager) {
        self.api = api
        self.session = session
    }

    var user: User? { session.user }

    /// La session vient de tomber sans action de l'utilisateur (voir `SessionManager.lastSignOutExpired`).
    var sessionExpired: Bool { session.lastSignOutExpired }

    var isLoggedIn: Bool { session.isLoggedIn }

    /// E-mail normalisé (blancs retirés, minuscules) ; 401 `invalidCredentials`, 423 `accountLocked` + `Retry-After`.
    func login(email: String, password: String) async throws -> User {
        let response = try await api.login(LoginRequestDTO(email: Self.normalized(email), password: password))
        session.signIn(response)
        return response.user.toDomain()
    }

    /// Connexion / inscription Google : l'id_token vient de la session web sécurisée du système.
    func loginWithGoogle(idToken: String, locale: String) async throws -> User {
        let response = try await api.loginWithGoogle(GoogleLoginRequestDTO(idToken: idToken, locale: locale))
        session.signIn(response)
        return response.user.toDomain()
    }

    /// Connexion / inscription Apple (`POST api/auth/apple`, lot serveur A — pas encore déployé). Le nom n'est
    /// fourni par Apple qu'à la première autorisation ; `nonce` = le nonce CLAIR dont le hachage a été demandé.
    func loginWithApple(
        identityToken: String,
        authorizationCode: String? = nil,
        nonce: String,
        givenName: String? = nil,
        familyName: String? = nil,
        locale: String
    ) async throws -> User {
        let given = RepositorySupport.trimmedOrNil(givenName)
        let family = RepositorySupport.trimmedOrNil(familyName)
        let name: AppleNameDTO? = (given == nil && family == nil) ? nil : AppleNameDTO(givenName: given, familyName: family)
        let body = AppleLoginRequestDTO(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: nonce,
            name: name,
            locale: locale
        )
        let response = try await api.loginWithApple(body)
        session.signIn(response)
        return response.user.toDomain()
    }

    /// Inscription puis connexion automatique (l'e-mail reste à vérifier : code à 6 chiffres envoyé). Un téléphone
    /// saisi part avec l'indicatif +213.
    func register(name: String, email: String, password: String, phone: String?) async throws -> User {
        let normalizedEmail = Self.normalized(email)
        let cleanPhone = RepositorySupport.trimmedOrNil(phone)
        let body = RegisterRequestDTO(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: normalizedEmail,
            password: password,
            phone: cleanPhone,
            phoneCountryCode: cleanPhone == nil ? nil : "+213"
        )
        do {
            _ = try await api.register(body)
        } catch let error as APIError where error.code == "emailExists" && normalizedEmail == registeredEmail {
            // Nouvel essai après « compte créé mais connexion échouée » (coupure réseau, 429) : le serveur répond
            // « e-mail déjà utilisé » pour un compte qui est le NÔTRE — on se connecte simplement.
            return try await login(email: normalizedEmail, password: password)
        }
        registeredEmail = normalizedEmail
        return try await login(email: normalizedEmail, password: password)
    }

    /// Secondes de validité du code envoyé (600 si le serveur ne le dit pas).
    func resendVerificationCode() async throws -> Int {
        try await api.resendVerificationCode().expiresIn ?? 600
    }

    /// Code accepté → l'utilisateur de session passe en « vérifié ». 400 `incorrectCode` (+ `remainingAttempts`).
    func confirmEmail(code: String) async throws {
        _ = try await api.confirmEmail(CodeRequestDTO(code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
        session.updateUser { current in
            var verified = current
            verified.emailVerified = true
            return verified
        }
    }

    /// Nouveau mot de passe depuis le lien de l'e-mail (client sans Bearer : l'utilisateur n'est pas connecté).
    func resetPassword(token: String, password: String) async throws {
        _ = try await api.resetPassword(ResetPasswordRequestDTO(token: token, password: password))
    }

    /// Toujours 200 côté serveur (anti-énumération) : succès = « si ce compte existe, un e-mail est parti ».
    func forgotPassword(email: String, locale: String) async throws {
        _ = try await api.forgotPassword(ForgotPasswordRequestDTO(email: Self.normalized(email), locale: locale))
    }

    func logout() {
        session.signOut()
    }

    private static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Profil, statistiques et annonces de l'utilisateur connecté (`/api/users/me*`) — portage d'`UserRepository`.
final class UserRepository {
    private let api: any WeydaAPI
    private let session: SessionManager

    init(api: any WeydaAPI, session: SessionManager) {
        self.api = api
        self.session = session
    }

    /// Langue du compte (`User.locale`) = langue de l'application : le serveur l'utilise pour les e-mails et
    /// notifications envoyés à ce compte. Échec silencieux ; renvoie vrai si le serveur l'a enregistrée.
    @discardableResult
    func syncLocale(_ locale: String) async -> Bool {
        do {
            _ = try await api.updateLocale(LocaleUpdateRequestDTO(locale: locale))
            return true
        } catch {
            return false
        }
    }

    /// Profil complet ; met à jour l'utilisateur de session (téléphone, bio, recommandé…). `emailVerified` est lu
    /// au moment d'ÉCRIRE, pas avant l'appel : une vérification aboutie pendant ce temps n'est pas perdue.
    func me() async throws -> User {
        let dto = try await api.me()
        session.updateUser { current in dto.toDomain(emailVerified: current.emailVerified) }
        return session.user ?? dto.toDomain(emailVerified: false)
    }

    /// PUT ne renvoie que quelques champs : fusion avec l'utilisateur courant. Un changement d'e-mail remet
    /// `emailVerified` à faux côté serveur (nouveau code envoyé). L'indicatif choisi sur le site est conservé
    /// (+213 par défaut).
    func updateProfile(name: String, email: String?, phone: String?, bio: String?) async throws -> User {
        let current = session.user
        let newEmail = RepositorySupport.trimmedOrNil(email)?.lowercased()
        let cleanPhone = RepositorySupport.trimmedOrNil(phone)
        let body = UpdateProfileRequestDTO(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: newEmail == current?.email ? nil : newEmail,
            phone: cleanPhone,
            phoneCountryCode: cleanPhone == nil ? nil : (TextCheck.nonBlank(current?.phoneCountryCode) ?? "+213"),
            bio: RepositorySupport.trimmedOrNil(bio)
        )
        let dto = try await api.updateMe(body)
        let emailChanged = current != nil && !TextCheck.isBlank(dto.email) && dto.email != current?.email
        // Fusion sur l'utilisateur COURANT au moment d'écrire (même raison que `me`).
        func merge(_ base: User) -> User {
            var merged = base
            merged.name = dto.name ?? base.name
            merged.email = TextCheck.ifBlank(dto.email, base.email)
            merged.phone = dto.phone
            merged.phoneCountryCode = dto.phoneCountryCode
            merged.bio = dto.bio
            merged.emailVerified = emailChanged ? false : base.emailVerified
            return merged
        }
        session.updateUser(merge)
        return session.user ?? merge(current ?? dto.toDomain(emailVerified: false))
    }

    /// Succès = `sessionVersion` changé côté serveur → déconnexion locale, l'interface renvoie à la connexion.
    func changePassword(current: String, new: String, confirm: String) async throws {
        _ = try await api.changePassword(
            ChangePasswordRequestDTO(currentPassword: current, newPassword: new, confirmPassword: confirm)
        )
        session.signOut()
    }

    func stats() async throws -> UserStats {
        try await api.myStats().toDomain()
    }

    /// Mes annonces (tous statuts, ou un seul), `limit` borné à 1–48.
    func myListings(status: ListingStatus? = nil, page: Int = 1, limit: Int = 24) async throws -> ListingPage {
        try await api.myAnnonces(status: status?.rawValue, page: page, limit: RepositorySupport.clamp(limit, 1, 48)).toDomain()
    }
}
