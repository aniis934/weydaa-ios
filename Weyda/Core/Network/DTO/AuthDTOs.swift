import Foundation

// Portage de data/remote/dto/AuthDtos.kt — auth mobile (docs/API-CONTRACT.md §3) : POST /api/auth/token,
// /refresh, /google, /register, /forgot-password, /reset-password, /api/email-verify[/confirm],
// GET/PUT /api/users/me, /password, /stats, DELETE /api/users/me/account.
// Requêtes : `Encodable` généré (un champ `nil` est omis, comme `explicitNulls = false`).
// `StoredUserDto` n'est pas porté : sur iOS, `User` est lui-même `Codable` (format de stockage local).

nonisolated struct LoginRequestDTO: Encodable, Hashable, Sendable {
    var email: String
    var password: String
}

nonisolated struct RefreshRequestDTO: Encodable, Hashable, Sendable {
    var refreshToken: String
}

/// `POST /api/auth/google` : id_token Google + langue de l'interface (e-mails localisés si création).
nonisolated struct GoogleLoginRequestDTO: Encodable, Hashable, Sendable {
    var idToken: String
    var locale: String = "fr"
}

nonisolated struct RegisterRequestDTO: Encodable, Hashable, Sendable {
    var name: String
    var email: String
    var password: String
    var phone: String? = nil
    var phoneCountryCode: String? = nil
}

nonisolated struct ForgotPasswordRequestDTO: Encodable, Hashable, Sendable {
    var email: String
    var locale: String = "fr"
}

/// `POST /api/auth/reset-password` : jeton du lien de l'e-mail + nouveau mot de passe.
nonisolated struct ResetPasswordRequestDTO: Encodable, Hashable, Sendable {
    var token: String
    var password: String
}

/// `POST /api/email-verify/confirm` : code à 6 chiffres.
nonisolated struct CodeRequestDTO: Encodable, Hashable, Sendable {
    var code: String
}

nonisolated struct UpdateProfileRequestDTO: Encodable, Hashable, Sendable {
    var name: String
    var email: String? = nil
    var phone: String? = nil
    var phoneCountryCode: String? = nil
    var bio: String? = nil
}

nonisolated struct ChangePasswordRequestDTO: Encodable, Hashable, Sendable {
    var currentPassword: String
    var newPassword: String
    var confirmPassword: String
}

/// `DELETE /api/users/me/account` (loi 18-07). Compte avec mot de passe : `password`. Compte créé avec Google
/// (sans mot de passe) : `googleIdToken`, un id_token Google frais du même compte, revérifié par le serveur.
nonisolated struct DeleteAccountRequestDTO: Encodable, Hashable, Sendable {
    var password: String? = nil
    var googleIdToken: String? = nil
}

/// `user` de la réponse token : seule source de `emailVerified` (GET /users/me ne le renvoie pas).
nonisolated struct AuthUserDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String? = nil
    var email: String = ""
    var avatar: String? = nil
    var role: String = "USER"
    var emailVerified: Bool = false
}

nonisolated extension AuthUserDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        name = container.lenientString("name")
        email = container.lenientString("email") ?? ""
        avatar = container.lenientString("avatar")
        role = container.lenientString("role") ?? "USER"
        emailVerified = container.lenientBool("emailVerified") ?? false
    }
}

/// Réponse de `POST /api/auth/token`, `/token/refresh` et `/google`.
nonisolated struct TokenResponseDTO: Decodable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String = "Bearer"
    /// Secondes avant expiration du jeton d'accès (1 h côté serveur).
    var expiresIn: Int = 3600
    var refreshExpiresIn: Int = 30 * 24 * 3600
    var user: AuthUserDTO
    /// POST /api/auth/google seulement : compte créé à la volée.
    var isNewUser: Bool = false
}

nonisolated extension TokenResponseDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        accessToken = try container.requiredString("accessToken")
        refreshToken = try container.requiredString("refreshToken")
        tokenType = container.lenientString("tokenType") ?? "Bearer"
        expiresIn = container.lenientInt("expiresIn") ?? 3600
        refreshExpiresIn = container.lenientInt("refreshExpiresIn") ?? 30 * 24 * 3600
        user = try container.decode(AuthUserDTO.self, forKey: "user")
        isNewUser = container.lenientBool("isNewUser") ?? false
    }
}

/// GET /api/users/me (forme complète) et PUT /api/users/me (quelques champs seulement → défauts).
nonisolated struct MeDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String? = nil
    var email: String = ""
    var phone: String? = nil
    var phoneCountryCode: String? = nil
    var isRecommended: Bool = false
    var recommendedAt: String? = nil
    var bio: String? = nil
    var avatar: String? = nil
    var role: String = "USER"
    var createdAt: String? = nil
    /// PUT : présent si l'e-mail a changé et que l'envoi du code a échoué.
    var emailVerificationWarning: String? = nil
    /// Faux pour un compte créé avec Google : ni changement de mot de passe, ni suppression par mot de passe.
    var hasPassword: Bool? = nil
}

nonisolated extension MeDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        name = container.lenientString("name")
        email = container.lenientString("email") ?? ""
        phone = container.lenientString("phone")
        phoneCountryCode = container.lenientString("phoneCountryCode")
        isRecommended = container.lenientBool("isRecommended") ?? false
        recommendedAt = container.lenientString("recommendedAt")
        bio = container.lenientString("bio")
        avatar = container.lenientString("avatar")
        role = container.lenientString("role") ?? "USER"
        createdAt = container.lenientString("createdAt")
        emailVerificationWarning = container.lenientString("emailVerificationWarning")
        hasPassword = container.lenientBool("hasPassword")
    }
}

/// `POST /api/auth/register` → 201 `{ id, name, email }`.
nonisolated struct RegisterResponseDTO: Decodable, Hashable, Sendable {
    var id: String
    var name: String? = nil
    var email: String = ""
}

nonisolated extension RegisterResponseDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = try container.requiredString("id")
        name = container.lenientString("name")
        email = container.lenientString("email") ?? ""
    }
}

/// `{ success, message?, expiresIn? }` (email-verify, forgot-password, password, suppressions…).
nonisolated struct SimpleResponseDTO: Decodable, Hashable, Sendable {
    var success: Bool = true
    var message: String? = nil
    var expiresIn: Int? = nil
}

nonisolated extension SimpleResponseDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        success = container.lenientBool("success") ?? true
        message = container.lenientString("message")
        expiresIn = container.lenientInt("expiresIn")
    }
}

/// `GET /api/users/me/stats`.
nonisolated struct UserStatsDTO: Decodable, Hashable, Sendable {
    var totalViews: Int = 0
    var activeCount: Int = 0
    var pendingCount: Int = 0
    var soldCount: Int = 0
    var expiredCount: Int = 0
    var favoritesReceived: Int = 0
    var messagesReceived: Int = 0
}

nonisolated extension UserStatsDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        totalViews = container.lenientInt("totalViews") ?? 0
        activeCount = container.lenientInt("activeCount") ?? 0
        pendingCount = container.lenientInt("pendingCount") ?? 0
        soldCount = container.lenientInt("soldCount") ?? 0
        expiredCount = container.lenientInt("expiredCount") ?? 0
        favoritesReceived = container.lenientInt("favoritesReceived") ?? 0
        messagesReceived = container.lenientInt("messagesReceived") ?? 0
    }
}
