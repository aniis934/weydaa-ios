import Foundation
import os
import Security

/// Session dans le trousseau iOS — rôle de `SessionStore` + `TokenCipher` (Android, jetons chiffrés par le
/// Keystore). Jetons ET utilisateur en JSON, chacun dans un élément « mot de passe générique » du service
/// `com.weydaa.app.session`, lisibles après le premier déverrouillage, jamais sauvegardés vers un autre
/// appareil (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
///
/// Tolérant comme Android : une lecture impossible vaut « rien d'enregistré », une écriture impossible est
/// journalisée et la session continue en mémoire. Jamais d'exception, jamais de plantage au démarrage.
final class KeychainSessionStorage: SessionStorage {
    private enum Account {
        static let tokens = "tokens"
        static let user = "user"
    }

    /// Drapeau UserDefaults posé au premier lancement d'une installation (voir `purgeIfFreshInstall`).
    private static let installMarkerKey = "WeydaSessionKeychainInstalled"

    private let service: String
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.weydaa.app", category: "session")

    init(service: String = "com.weydaa.app.session", defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    /// Le trousseau SURVIT à la désinstallation, pas les UserDefaults : au premier lancement d'une nouvelle
    /// installation (drapeau absent), on efface la session laissée par la précédente — comme Android, où
    /// désinstaller efface tout. À appeler avant `SessionManager.restore()`.
    ///
    /// Rien n'est fait tant que les données protégées sont indisponibles : lancé avant le premier
    /// déverrouillage (pré-chargement par iOS), UserDefaults paraît vide et l'on effacerait à tort une
    /// session valide.
    func purgeIfFreshInstall(protectedDataAvailable: Bool) {
        guard protectedDataAvailable, !defaults.bool(forKey: Self.installMarkerKey) else { return }
        deleteItems(account: nil)
        defaults.set(true, forKey: Self.installMarkerKey)
    }

    // MARK: - SessionStorage

    func readTokens() -> AuthTokens? {
        read(AuthTokens.self, account: Account.tokens)
    }

    func writeTokens(_ tokens: AuthTokens?) {
        write(tokens, account: Account.tokens)
    }

    func readUser() -> User? {
        read(User.self, account: Account.user)
    }

    func writeUser(_ user: User?) {
        write(user, account: Account.user)
    }

    func clear() {
        deleteItems(account: nil)
    }

    // MARK: - JSON

    private func read<Value: Decodable>(_ type: Value.Type, account: String) -> Value? {
        guard let data = readData(account: account) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("Session illisible dans le trousseau (\(account, privacy: .public))")
            return nil
        }
    }

    private func write<Value: Encodable>(_ value: Value?, account: String) {
        guard let value else {
            deleteItems(account: account)
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            // Jamais d'ancienne valeur laissée en place quand la nouvelle ne peut pas s'écrire.
            deleteItems(account: account)
            logger.error("Session non encodable (\(account, privacy: .public))")
            return
        }
        writeData(data, account: account)
    }

    // MARK: - Trousseau

    private func baseQuery(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }

    private func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { report(status, operation: "lecture") }
            return nil
        }
        return item as? Data
    }

    private func writeData(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess {
            // Absent, ou élément d'une autre forme (autres attributs, version antérieure) : remplacé.
            if status != errSecItemNotFound { _ = SecItemDelete(query as CFDictionary) }
            let item = query.merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess { report(status, operation: "écriture") }
    }

    /// `account` nil = tous les éléments du service (déconnexion, nouvelle installation).
    private func deleteItems(account: String?) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { report(status, operation: "effacement") }
    }

    private func report(_ status: OSStatus, operation: String) {
        logger.error("Trousseau : \(operation, privacy: .public) impossible (OSStatus \(status, privacy: .public))")
    }
}
