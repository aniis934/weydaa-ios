import Foundation

/// Raccourcis de l'icône (appui long sur l'icône de l'app) : Déposer, Rechercher, Messages. Valeur pure ; les articles
/// sont posés à chaque lancement (titres traduits) et l'appui passe par la navigation entrante comme un lien.
nonisolated enum ShortcutAction: String, CaseIterable, Sendable {
    case post
    case search
    case messages

    /// Préfixe du type d'un `UIApplicationShortcutItem` (`com.weydaa.app.shortcut.post`…).
    static let typePrefix = "com.weydaa.app.shortcut."

    /// Type de l'article de raccourci.
    var type: String { Self.typePrefix + rawValue }

    /// Depuis le type d'un article (nil = article inconnu, ancien ou d'une autre version).
    init?(shortcutType: String) {
        guard shortcutType.hasPrefix(Self.typePrefix) else { return nil }
        self.init(rawValue: String(shortcutType.dropFirst(Self.typePrefix.count)))
    }

    var title: String {
        switch self {
        case .post: L10n.navPost
        case .search: L10n.shortcutSearch
        case .messages: L10n.navMessages
        }
    }

    /// SF Symbol de l'article.
    var symbol: String {
        switch self {
        case .post: "plus.circle"
        case .search: "magnifyingglass"
        case .messages: "envelope"
        }
    }

    /// Écran ouvert : Déposer, Messages, ou l'onglet Annonces champ de recherche focalisé.
    func target() -> DeepLinkTarget {
        switch self {
        case .post:
            return .post
        case .messages:
            return .messages
        case .search:
            return .listings(params: [ListingsLaunch.focusSearchParam: ListingsLaunch.focusSearchValue])
        }
    }
}
