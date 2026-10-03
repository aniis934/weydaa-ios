import Security
import XCTest
@testable import Weyda

/// Aller-retour réel dans le trousseau du simulateur (l'app sert d'hôte aux tests), sur un service DÉDIÉ et
/// une suite UserDefaults à part : la session de l'app n'est jamais touchée. Données FICTIVES.
final class KeychainSessionStorageTests: XCTestCase {
    private static let service = "com.weydaa.app.session.tests"
    private static let suiteName = "com.weydaa.app.session.tests"

    private static func tokenResponse() -> TokenResponseDTO {
        TokenResponseDTO(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            user: AuthUserDTO(id: "user_1", name: "Karim B.", email: "test@example.com", emailVerified: true)
        )
    }

    /// Le trousseau exige des droits que seule une app hôte signée possède : si la CI compile sans signature
    /// (errSecMissingEntitlement…), le test est IGNORÉ plutôt qu'en échec.
    private func requireKeychain() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "probe",
        ]
        _ = SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data("probe".utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        _ = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess {
            throw XCTSkip("Trousseau indisponible dans cet environnement (OSStatus \(status)).")
        }
    }

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private func cleanUp() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
        ]
        _ = SecItemDelete(query as CFDictionary)
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
    }

    @MainActor
    func testTokensAndUserRoundTripThroughTheKeychain() throws {
        try requireKeychain()
        defer { cleanUp() }
        let defaults = try makeDefaults()
        let storage = KeychainSessionStorage(service: Self.service, defaults: defaults)
        storage.clear()

        let response = Self.tokenResponse()
        let tokens = response.toTokens(now: Date(timeIntervalSince1970: 1_788_861_600))
        var user = response.user.toDomain()
        user.phone = "0555000000"
        user.memberSince = Date(timeIntervalSince1970: 1_700_000_000)
        storage.writeTokens(tokens)
        storage.writeUser(user)

        // Autre instance : relu dans le trousseau, pas dans un cache.
        let reread = KeychainSessionStorage(service: Self.service, defaults: defaults)
        XCTAssertEqual(reread.readTokens(), tokens)
        XCTAssertEqual(reread.readUser(), user)

        // Réécriture d'un élément existant.
        let rotated = AuthTokens(
            accessToken: "access-2",
            refreshToken: "refresh-2",
            accessExpiresAt: tokens.accessExpiresAt.addingTimeInterval(3600),
            refreshExpiresAt: tokens.refreshExpiresAt
        )
        storage.writeTokens(rotated)
        XCTAssertEqual(reread.readTokens(), rotated)

        storage.writeTokens(nil)
        XCTAssertNil(reread.readTokens())
        XCTAssertEqual(reread.readUser(), user)

        storage.clear()
        XCTAssertNil(reread.readUser())
    }

    @MainActor
    func testAFreshInstallPurgesTheSessionLeftByAPreviousOne() throws {
        try requireKeychain()
        defer { cleanUp() }
        let defaults = try makeDefaults()
        let storage = KeychainSessionStorage(service: Self.service, defaults: defaults)
        let response = Self.tokenResponse()
        storage.writeTokens(response.toTokens())
        storage.writeUser(response.user.toDomain())

        // Données protégées indisponibles (lancement avant le premier déverrouillage) : rien n'est effacé.
        storage.purgeIfFreshInstall(protectedDataAvailable: false)
        XCTAssertNotNil(storage.readTokens())

        // Premier lancement de la nouvelle installation : la session de la précédente disparaît.
        storage.purgeIfFreshInstall(protectedDataAvailable: true)
        XCTAssertNil(storage.readTokens())
        XCTAssertNil(storage.readUser())

        // Lancements suivants : la session est conservée.
        storage.writeTokens(response.toTokens())
        storage.purgeIfFreshInstall(protectedDataAvailable: true)
        XCTAssertNotNil(storage.readTokens())
    }

    @MainActor
    func testUnreadableDataCountsAsNothingStored() throws {
        try requireKeychain()
        defer { cleanUp() }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: "tokens",
            kSecValueData as String: Data("pas du JSON".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)

        let defaults = try makeDefaults()
        let storage = KeychainSessionStorage(service: Self.service, defaults: defaults)
        XCTAssertNil(storage.readTokens())

        // L'écriture suivante remplace l'élément illisible (instant rond : comparaison exacte des dates).
        let tokens = Self.tokenResponse().toTokens(now: Date(timeIntervalSince1970: 1_788_861_600))
        storage.writeTokens(tokens)
        XCTAssertEqual(storage.readTokens(), tokens)
    }

    @MainActor
    func testASessionSurvivesARelaunch() throws {
        try requireKeychain()
        defer { cleanUp() }
        let defaults = try makeDefaults()
        let noRefresh: @Sendable (String) async throws -> TokenResponseDTO = { _ in throw URLError(.cancelled) }

        let first = SessionManager(
            storage: KeychainSessionStorage(service: Self.service, defaults: defaults),
            refreshCall: noRefresh
        )
        first.signIn(Self.tokenResponse())

        let relaunched = SessionManager(
            storage: KeychainSessionStorage(service: Self.service, defaults: defaults),
            refreshCall: noRefresh
        )
        relaunched.restore()
        XCTAssertTrue(relaunched.isLoggedIn)
        XCTAssertEqual(relaunched.accessToken, "access-1")
        XCTAssertEqual(relaunched.user?.email, "test@example.com")
    }
}
