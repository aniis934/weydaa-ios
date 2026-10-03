import Foundation

/// D'où part une connexion par un compte Apple ou Google.
nonisolated enum SocialRoute: Hashable, Sendable {
    /// Page de Google (session web du système), puis `POST api/auth/google`.
    case google
    /// id_token Google déjà obtenu (Android : `signInWithGoogle(idToken)`).
    case googleToken(String)
    /// Autorisation Apple demandée par le code — en API simulée, sans fenêtre système.
    case appleAuthorization
    /// Autorisation rendue par le bouton système « Continuer avec Apple ».
    case apple(AppleCredential)

    var isGoogle: Bool {
        switch self {
        case .google, .googleToken: true
        case .appleAuthorization, .apple: false
        }
    }
}

/// Connexions Apple et Google des écrans Connexion et Inscription : la même route serveur crée le compte s'il
/// n'existe pas (Android : `signInWithGoogle` des deux ViewModels). Coordinateurs du système et langue des e-mails
/// injectés : les tests passent par l'API simulée, sans fenêtre.
final class SocialSignIn {
    let apple: AppleSignInCoordinator
    let google: GoogleSignInCoordinator
    private let auth: AuthRepository
    /// Langue des e-mails du serveur (Android : `appLocale()`).
    private let locale: String

    init(
        auth: AuthRepository,
        apple: AppleSignInCoordinator,
        google: GoogleSignInCoordinator,
        locale: String = WeydaLocale.language
    ) {
        self.auth = auth
        self.apple = apple
        self.google = google
        self.locale = locale
    }

    /// Coordinateurs de l'app (API simulée en Debug avec `-WeydaMockAPI YES`).
    convenience init(auth: AuthRepository) {
        self.init(auth: auth, apple: AppleSignInCoordinator(), google: GoogleSignInCoordinator())
    }

    /// Bouton Google masqué sans identifiant client (Android : sans `serverClientId`).
    var showsGoogle: Bool { google.isConfigured }

    /// API simulée : le bouton Apple simule l'autorisation au lieu d'ouvrir la feuille du système.
    var isAppleSimulated: Bool { apple.isSimulated }

    /// Autorisation (si besoin) puis session ouverte. Fenêtre fermée → `CancellationError` (rien à afficher).
    func signIn(_ route: SocialRoute) async throws -> User {
        switch route {
        case .google:
            let idToken = try await google.signIn()
            return try await auth.loginWithGoogle(idToken: idToken, locale: locale)
        case .googleToken(let idToken):
            return try await auth.loginWithGoogle(idToken: idToken, locale: locale)
        case .appleAuthorization:
            let credential = try await apple.signIn()
            return try await loginWithApple(credential)
        case .apple(let credential):
            return try await loginWithApple(credential)
        }
    }

    /// Le nonce CLAIR part au serveur (Apple n'en a vu que le SHA-256) ; le nom n'existe qu'à la 1re autorisation.
    private func loginWithApple(_ credential: AppleCredential) async throws -> User {
        try await auth.loginWithApple(
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            nonce: credential.rawNonce,
            givenName: credential.givenName,
            familyName: credential.familyName,
            locale: locale
        )
    }
}
