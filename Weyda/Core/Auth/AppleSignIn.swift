import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// Autorisation « Se connecter avec Apple » prête pour `AuthRepository.loginWithApple` ou pour la preuve de
/// suppression d'un compte Apple. `rawNonce` : le nonce CLAIR, dont Apple a reçu le SHA-256 (le serveur compare).
/// Le nom n'est fourni par Apple qu'à la PREMIÈRE autorisation ; l'e-mail peut être une adresse relais privée.
nonisolated struct AppleCredential: Sendable, Hashable {
    let identityToken: String
    let authorizationCode: String?
    let rawNonce: String
    let givenName: String?
    let familyName: String?
    let email: String?
}

/// Échec de Sign in with Apple sur l'appareil (l'annulation, elle, devient `CancellationError` : rien à afficher).
nonisolated enum AppleSignInError: Error, Sendable, Equatable {
    /// Service indisponible ou en échec : capacité « Sign in with Apple » absente du profil, pas de compte iCloud…
    case failed
    /// Réponse d'Apple sans jeton d'identité lisible.
    case invalidResponse
}

/// Octets du générateur cryptographique du système.
nonisolated enum SecureRandom {
    static func bytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: max(count, 0))
        // `nil` = le générateur par défaut (`kSecRandomDefault` est un synonyme de NULL).
        let status = SecRandomCopyBytes(nil, bytes.count, &bytes)
        if status != errSecSuccess {
            // Repli (jamais constaté) : le générateur de la bibliothèque standard, cryptographique lui aussi sur iOS.
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            }
        }
        return bytes
    }
}

/// Nonce d'une demande Apple : caractères aléatoires de l'alphabet base64url (64 symboles : aucun biais de modulo),
/// envoyés clairs au serveur ; Apple reçoit leur SHA-256 hexadécimal et le recopie dans le jeton d'identité, ce qui
/// empêche de rejouer un jeton intercepté sans le nonce.
nonisolated enum AppleNonce {
    static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// 32 caractères = 192 bits d'aléa (le serveur exige 16 à 256 caractères).
    static func random(length: Int = 32) -> String {
        String(SecureRandom.bytes(length).map { alphabet[Int($0 & 63)] })
    }

    /// SHA-256 en hexadécimal minuscule : la forme que compare le serveur (`sha256Hex`, lot A).
    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex: [Character] = Array("0123456789abcdef")
        var result = ""
        result.reserveCapacity(64)
        for byte in digest {
            result.append(hex[Int(byte >> 4)])
            result.append(hex[Int(byte & 0x0F)])
        }
        return result
    }
}

/// « Se connecter avec Apple » (sans équivalent Android). Deux usages :
/// - le bouton système de la connexion (`SignInWithAppleButton`) : `prepare(_:)` puis `credential(from:)` ;
/// - une autorisation demandée par le code, `signIn()` : suppression d'un compte Apple (Mes données).
/// Sans l'entitlement (il viendra avec le compte Apple Developer), le système répond par une erreur :
/// `AppleSignInError.failed`, traduite par `ErrorMapper`. En API simulée, la connexion réussit sans fenêtre système.
final class AppleSignInCoordinator {
    let isSimulated: Bool

    /// Nonce clair de la demande du bouton système en cours.
    private var pendingNonce: String?
    /// Demande de `signIn()` en cours : `ASAuthorizationController` ne retient ni son délégué ni son ancrage.
    private var activeController: ASAuthorizationController?
    private var activeDelegate: AppleAuthorizationDelegate?
    private var activePresenter: AuthPresentationContext?

    init(simulated: Bool = AuthSimulation.isEnabled) {
        isSimulated = simulated
    }

    /// Autorisation Apple demandée par le code. Annulation par l'utilisateur → `CancellationError` ; demande déjà en
    /// cours (double appui) → `CancellationError` aussi : rien à afficher.
    func signIn() async throws -> AppleCredential {
        let rawNonce = AppleNonce.random()
        if isSimulated {
            return Self.simulatedCredential(rawNonce: rawNonce)
        }
        guard activeController == nil else { throw CancellationError() }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(rawNonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let presenter = AuthPresentationContext()
        controller.presentationContextProvider = presenter
        defer {
            activeController = nil
            activeDelegate = nil
            activePresenter = nil
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleCredential, any Error>) in
            let delegate = AppleAuthorizationDelegate(rawNonce: rawNonce, resume: SingleResume(continuation))
            controller.delegate = delegate
            activeController = controller
            activeDelegate = delegate
            activePresenter = presenter
            controller.performRequests()
        }
    }

    /// Bouton système, au moment de l'appui : portée (nom, e-mail) et SHA-256 d'un nonce neuf.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let rawNonce = AppleNonce.random()
        pendingNonce = rawNonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(rawNonce)
    }

    /// Bouton système, à la fin : l'autorisation devient une `AppleCredential` (avec le nonce de `prepare`).
    func credential(from result: Result<ASAuthorization, any Error>) throws -> AppleCredential {
        let rawNonce = pendingNonce
        pendingNonce = nil
        switch result {
        case .failure(let error):
            throw Self.mapError(error)
        case .success(let authorization):
            guard let rawNonce, let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppleSignInError.invalidResponse
            }
            return try Self.credential(
                identityToken: apple.identityToken,
                authorizationCode: apple.authorizationCode,
                fullName: apple.fullName,
                email: apple.email,
                rawNonce: rawNonce
            )
        }
    }

    /// Réponse d'Apple → `AppleCredential` ; jeton absent ou illisible → `invalidResponse`.
    nonisolated static func credential(
        identityToken: Data?,
        authorizationCode: Data?,
        fullName: PersonNameComponents?,
        email: String?,
        rawNonce: String
    ) throws -> AppleCredential {
        guard let identityToken,
              let token = String(data: identityToken, encoding: .utf8),
              !TextCheck.isBlank(token) else {
            throw AppleSignInError.invalidResponse
        }
        let code = authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        return AppleCredential(
            identityToken: token,
            authorizationCode: TextCheck.nonBlank(code),
            rawNonce: rawNonce,
            givenName: TextCheck.nonBlank(fullName?.givenName),
            familyName: TextCheck.nonBlank(fullName?.familyName),
            email: TextCheck.nonBlank(email)
        )
    }

    /// Erreur du système → annulation silencieuse (`CancellationError`) ou `AppleSignInError.failed`.
    nonisolated static func mapError(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.Code.canceled.rawValue {
            return CancellationError()
        }
        return AppleSignInError.failed
    }

    /// Autorisation simulée (API simulée) : jeton factice, nonce réel.
    nonisolated static func simulatedCredential(rawNonce: String) -> AppleCredential {
        AppleCredential(
            identityToken: "mock-apple-identity-token",
            authorizationCode: "mock-apple-authorization-code",
            rawNonce: rawNonce,
            givenName: nil,
            familyName: nil,
            email: nil
        )
    }
}

/// Délégué d'UNE demande `signIn()` : la réponse devient une `AppleCredential` (données `Sendable`) avant de
/// reprendre l'appelant. Appelé sur le fil principal par le système.
private nonisolated final class AppleAuthorizationDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let rawNonce: String
    private let resume: SingleResume<AppleCredential>

    init(rawNonce: String, resume: SingleResume<AppleCredential>) {
        self.rawNonce = rawNonce
        self.resume = resume
        super.init()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
            resume.resume(with: .failure(AppleSignInError.invalidResponse))
            return
        }
        let result = Result<AppleCredential, any Error>(catching: {
            try AppleSignInCoordinator.credential(
                identityToken: apple.identityToken,
                authorizationCode: apple.authorizationCode,
                fullName: apple.fullName,
                email: apple.email,
                rawNonce: rawNonce
            )
        })
        resume.resume(with: result)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        resume.resume(with: .failure(AppleSignInCoordinator.mapError(error)))
    }
}
