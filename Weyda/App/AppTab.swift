import Foundation

/// Les cinq onglets — mêmes onglets et même ordre que la barre du bas Android (BottomTabs).
nonisolated enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case listings
    case post
    case messages
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: L10n.navHome
        case .listings: L10n.navListings
        case .post: L10n.navPost
        case .messages: L10n.navMessages
        case .account: L10n.navProfile
        }
    }

    /// SF Symbol (la barre d'onglets prend d'elle-même la variante pleine de l'onglet actif).
    var symbol: String {
        switch self {
        case .home: "house"
        case .listings: "magnifyingglass"
        case .post: "plus.circle"
        case .messages: "envelope"
        case .account: "person"
        }
    }
}
