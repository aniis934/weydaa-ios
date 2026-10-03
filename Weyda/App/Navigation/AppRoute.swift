import Foundation

/// Écran poussé sur la pile d'un onglet — les routes de `Screen.kt` (Android) hors onglets. Valeur pure
/// (`nonisolated`) : elle vit dans les piles du routeur, les liens profonds et les arguments de lancement.
nonisolated enum AppRoute: Hashable, Sendable {
    /// Fiche d'une annonce (l'API accepte l'identifiant ou le slug).
    case detail(idOrSlug: String)
    /// Profil public d'un vendeur.
    case seller(id: String)
    /// Page légale du site, lue dans SFSafariViewController : `AppRouter.push` la présente en feuille.
    case webPage(WebPage)
    /// « À propos et informations légales ».
    case about
    // Phases suivantes : écran d'attente (`ComingSoonView`) en phase 2.
    case chat(conversationId: String, archived: Bool)
    case myListings
    case favorites
    case savedSearches
    case notifications
    case editProfile
    case changePassword
    case accountData
    case contact
    case editListing(id: String)
    /// « Utilisateurs bloqués » (compte, phase 5 — App Store 1.2).
    case blockedUsers
}

nonisolated extension AppRoute {
    /// Titre de l'écran (barre de navigation des écrans d'attente).
    var title: String {
        switch self {
        case .detail: L10n.navListings
        case .seller: L10n.sellerProfileTitle
        case .webPage(let page): page.title
        case .about: L10n.legalTitle
        case .chat: L10n.navMessages
        case .myListings: L10n.myListingsTitle
        case .favorites: L10n.favoritesTitle
        case .savedSearches: L10n.alertsTitle
        case .notifications: L10n.notificationsTitle
        case .editProfile: L10n.editProfileTitle
        case .changePassword: L10n.changePasswordTitle
        case .accountData: L10n.accountDataTitle
        case .contact: L10n.contactTitle
        case .editListing: L10n.postEditTitle
        case .blockedUsers: L10n.blockedUsersTitle
        }
    }

    /// Pictogramme SF Symbols de l'écran (écrans d'attente).
    var symbol: String {
        switch self {
        case .detail: "doc.text.image"
        case .seller: "person.crop.circle"
        case .webPage(let page): page.symbol
        case .about: "info.circle"
        case .chat: "bubble.left.and.bubble.right"
        case .myListings: "square.stack"
        case .favorites: "heart"
        case .savedSearches: "bell"
        case .notifications: "bell.badge"
        case .editProfile: "person.crop.circle"
        case .changePassword: "key"
        case .accountData: "tray.and.arrow.down"
        case .contact: "envelope"
        case .editListing: "square.and.pencil"
        case .blockedUsers: "person.crop.circle.badge.minus"
        }
    }
}

/// Ouverture de l'onglet Annonces avec des critères (accueil : recherche, catégorie, ville, « À la une » ;
/// liens profonds `/annonces?…`). Consommée — remise à nil — par l'onglet Annonces.
nonisolated struct ListingsLaunch: Hashable, Sendable {
    var q: String? = nil
    var category: String? = nil
    var subcategory: String? = nil
    var wilaya: Int? = nil
    var featured: Bool = false
}

nonisolated extension ListingsLaunch {
    /// Depuis les paramètres d'URL du site (`DeepLinkTarget.listings`) : q, category, subcategory, wilaya,
    /// featured (« 1 » ou « true »). Commune et prix ne sont pas portés par `ListingsLaunch` (phase 2).
    init(params: [String: String]) {
        self.init(
            q: TextCheck.nonBlank(params["q"]),
            category: TextCheck.nonBlank(params["category"]),
            subcategory: TextCheck.nonBlank(params["subcategory"]),
            wilaya: params["wilaya"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            featured: Self.isTrue(params["featured"])
        )
    }

    /// Depuis une requête d'URL (`q=clio&category=vehicules`), pour `-WeydaRoute listings:…`.
    init(query: String) {
        self.init(params: Self.parameters(query))
    }

    /// Première valeur de chaque clé ; « + » lu comme une espace, comme les formulaires du site.
    static func parameters(_ query: String) -> [String: String] {
        var text = Substring(query)
        if text.hasPrefix("?") { text = text.dropFirst() }
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = pieces.first, !rawKey.isEmpty else { continue }
            let key = decode(rawKey)
            if result[key] == nil {
                result[key] = pieces.count > 1 ? decode(pieces[1]) : ""
            }
        }
        return result
    }

    private static func decode(_ raw: Substring) -> String {
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    private static func isTrue(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return value == "1" || value == "true"
    }
}

/// Pages légales du site, lues dans l'app (même texte, tenu à jour à un seul endroit) — miroir de `LegalPage`
/// (AboutScreen.kt) : mêmes chemins, même ordre.
nonisolated enum WebPage: String, CaseIterable, Hashable, Sendable, Identifiable {
    case terms = "cgu"
    case privacy = "confidentialite"
    case notice = "mentions-legales"
    case about = "a-propos"
    case accountDeletion = "suppression-compte"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: L10n.legalTerms
        case .privacy: L10n.legalPrivacy
        case .notice: L10n.legalNotice
        case .about: L10n.legalAbout
        case .accountDeletion: L10n.legalAccountDeletion
        }
    }

    var symbol: String {
        switch self {
        case .terms: "doc.text"
        case .privacy: "hand.raised"
        case .notice: "building.columns"
        case .about: "info.circle"
        case .accountDeletion: "person.crop.circle.badge.xmark"
        }
    }

    /// URL publique dans la langue de l'app : `https://weydaa.com/<fr|ar|en>/<chemin>` (jamais l'hôte de l'API).
    func url(language: String = WeydaLocale.language) -> URL {
        DeepLinks.siteURL.appending(path: language).appending(path: rawValue)
    }
}
