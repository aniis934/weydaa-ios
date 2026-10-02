import Foundation

/// Écran ouvert au démarrage par `-WeydaRoute <route>` (tour de captures, tests d'interface) : l'app s'ouvre
/// directement dessus, sans enchaîner les appuis. Formats acceptés :
///   detail:<id> · seller:<id> · about · web:<page> (cgu, terms…) · tab:<onglet> (home, listings, post,
///   messages, account ou profile) · listings[:q=…&category=…&subcategory=…&wilaya=16&featured=1]
///   et, pour les phases suivantes : chat:<id> · myListings · favorites · savedSearches · notifications
///   · editProfile · changePassword · accountData · contact · editListing:<id>
nonisolated enum LaunchRoute: Hashable, Sendable {
    case tab(AppTab)
    case listings(ListingsLaunch)
    case route(AppRoute)

    /// nil si le texte n'est pas reconnu (l'app s'ouvre alors normalement).
    static func parse(_ raw: String) -> LaunchRoute? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        let argument: String
        if let colon = text.firstIndex(of: ":") {
            name = String(text[..<colon])
            argument = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            name = text
            argument = ""
        }
        switch name.lowercased() {
        case "tab":
            guard let tab = appTab(named: argument) else { return nil }
            return .tab(tab)
        case "listings":
            return .listings(ListingsLaunch(query: argument))
        case "detail":
            guard let id = TextCheck.nonBlank(argument) else { return nil }
            return .route(.detail(idOrSlug: id))
        case "seller":
            guard let id = TextCheck.nonBlank(argument) else { return nil }
            return .route(.seller(id: id))
        case "chat":
            guard let id = TextCheck.nonBlank(argument) else { return nil }
            return .route(.chat(conversationId: id, archived: false))
        case "editlisting":
            guard let id = TextCheck.nonBlank(argument) else { return nil }
            return .route(.editListing(id: id))
        case "web":
            guard let page = webPage(named: argument) else { return nil }
            return .route(.webPage(page))
        case "about": return .route(.about)
        case "mylistings": return .route(.myListings)
        case "favorites": return .route(.favorites)
        case "savedsearches": return .route(.savedSearches)
        case "notifications": return .route(.notifications)
        case "editprofile": return .route(.editProfile)
        case "changepassword": return .route(.changePassword)
        case "accountdata": return .route(.accountData)
        case "contact": return .route(.contact)
        default: return nil
        }
    }

    /// Onglet qui porte la route au démarrage : le compte pour ses écrans, Messages pour un fil ; nil = l'onglet
    /// de départ (Accueil, ou `-WeydaTab`).
    static func preferredTab(for route: AppRoute) -> AppTab? {
        switch route {
        case .about, .myListings, .favorites, .savedSearches, .editProfile, .changePassword, .accountData,
             .contact, .editListing:
            return .account
        case .chat:
            return .messages
        case .detail, .seller, .webPage, .notifications:
            return nil
        }
    }

    static func appTab(named name: String) -> AppTab? {
        switch name.lowercased() {
        case "home": return .home
        case "listings": return .listings
        case "post": return .post
        case "messages": return .messages
        case "account", "profile": return .account
        default: return nil
        }
    }

    /// Par son chemin du site (`cgu`) ou par son nom (`terms`).
    private static func webPage(named name: String) -> WebPage? {
        let key = name.lowercased()
        return WebPage.allCases.first { $0.rawValue == key || String(describing: $0).lowercased() == key }
    }
}
