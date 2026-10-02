import Foundation

/// Destination d'un lien du site ouvert dans l'application (le reste repart au navigateur) — miroir de
/// `DeepLinkTarget` (Android).
nonisolated enum DeepLinkTarget: Hashable, Sendable {
    /// Fiche d'une annonce, par identifiant ou par slug (l'API accepte les deux).
    case listing(idOrSlug: String)
    case editListing(id: String)
    /// Profil public d'un vendeur.
    case seller(id: String)
    /// Fil d'une conversation (lien des e-mails « nouveau message »).
    case conversation(id: String)
    /// Recherche d'annonces avec ses paramètres d'URL (`/annonces?…`, `/c/{slug}`).
    case listings(params: [String: String])
    /// Lien « mot de passe oublié » : écran natif de nouveau mot de passe.
    case resetPassword(token: String)
    case post
    case messages
    case profile
    case myListings
    case favorites
}

/// Tri des liens reçus par l'app — portage de `ui/navigation/DeepLinks.kt` (Android). Logique pure.
///
/// Deux portes d'entrée : les liens universels (`https://weydaa.com/…` et `https://www.weydaa.com/…`, actifs
/// une fois le fichier AASA publié) et le schéma de l'app (`weydaa://annonce/{id}`, mêmes chemins que le site,
/// langue facultative). L'URL SEO d'une annonce est `/{locale}/{catégorie}/{slug}` et les slugs de catégorie ne
/// sont pas énumérables : le système nous remettra donc AUSSI des pages du site qui ne sont pas des annonces —
/// dont le lien de réinitialisation du mot de passe envoyé par e-mail. Sans tri, elles s'ouvraient toutes sur
/// « annonce introuvable » (constaté sur Android). Les pages sans écran natif (légales, administration,
/// modération) retournent au navigateur : voir `opensInBrowser`.
nonisolated enum DeepLinks {
    /// Adresse publique du site (liens partagés, pages légales, chemins des notifications) — jamais l'hôte de
    /// l'API, qui peut être local en Debug.
    static let siteURL = URL(string: "https://weydaa.com")!
    /// Schéma propre à l'app (à déclarer dans `CFBundleURLTypes` le jour où il sert).
    static let appScheme = "weydaa"

    private static let hosts: Set<String> = ["weydaa.com", "www.weydaa.com"]
    private static let locales: Set<String> = ["fr", "ar", "en"]

    /// Premier segment des pages du site qui ne sont pas des annonces : miroir de `STATIC_ROOTS`
    /// (src/lib/analytics-path.ts), sans `annonce` qui, lui, en est une. À tenir à jour avec le site.
    private static let staticRoots: Set<String> = [
        "a-propos", "admin", "annonces", "auth", "c", "categories", "cgu", "confidentialite",
        "contact", "dashboard", "deposer", "mentions-legales", "moderateur", "profil", "suppression-compte",
    ]

    /// Paramètres de `/annonces?…` repris par l'écran Annonces (mêmes clés que les alertes).
    private static let listingParams = [
        "q", "category", "subcategory", "wilaya", "commune", "priceType", "priceMin", "priceMax", "featured",
    ]

    // MARK: - Portage direct d'Android

    static func isWeydaHost(scheme: String?, host: String?) -> Bool {
        guard scheme?.lowercased() == "https", let host else { return false }
        return hosts.contains(host.lowercased())
    }

    /// Vrai pour `/{locale}/annonce/{id}` et `/{locale}/{catégorie}/{slug}` — exactement trois segments.
    static func isListingLink(scheme: String?, host: String?, pathSegments: [String]) -> Bool {
        isWeydaHost(scheme: scheme, host: host) && isListingPath(pathSegments)
    }

    /// Écran natif visé par un lien du site, ou nil s'il n'en a pas (le lien repart alors au navigateur) :
    /// annonce, édition, profil vendeur, recherche, catégorie, dépôt, tableau de bord, messagerie, nouveau mot de
    /// passe. L'app empile elle-même l'écran visé sur la pile courante (brouillon ou message en cours gardés).
    static func resolve(
        scheme: String?,
        host: String?,
        pathSegments: [String],
        query: (String) -> String? = { _ in nil }
    ) -> DeepLinkTarget? {
        guard isWeydaHost(scheme: scheme, host: host) else { return nil }
        return route(pathSegments, query: query)
    }

    // MARK: - Points d'entrée iOS

    /// Lien universel (`NSUserActivity.webpageURL`) ou ouvert par le schéma de l'app (`onOpenURL`).
    static func resolve(_ url: URL) -> DeepLinkTarget? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parameters = queryParameters(components.percentEncodedQuery)
        let lookup: (String) -> String? = { parameters[$0] }
        var segments = pathSegments(of: components)
        if components.scheme?.lowercased() == appScheme {
            // `weydaa://annonce/x` : l'« hôte » est le premier segment du chemin ; la langue est facultative.
            if let host = components.host, !host.isEmpty { segments.insert(host.lowercased(), at: 0) }
            if let first = segments.first, !locales.contains(first) { segments.insert("fr", at: 0) }
            return route(segments, query: lookup)
        }
        return resolve(scheme: components.scheme, host: components.host, pathSegments: segments, query: lookup)
    }

    /// Lien du site sans écran natif (page légale, administration…) : à rendre au navigateur.
    static func opensInBrowser(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return isWeydaHost(scheme: components.scheme, host: components.host) && resolve(url) == nil
    }

    /// Chemin reçu d'une notification push (`/fr/dashboard/messages/{id}`), rattaché au site comme sur Android.
    static func resolve(sitePath path: String) -> DeepLinkTarget? {
        guard path.hasPrefix("/"), let url = URL(string: siteURL.absoluteString + path) else { return nil }
        return resolve(url)
    }

    /// Segments décodés du chemin, sans les vides (`/fr/annonce/x/` → fr, annonce, x) — comme
    /// `Uri.pathSegments` : découpés AVANT décodage, un `%2F` reste dans son segment.
    static func pathSegments(of url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        return pathSegments(of: components)
    }

    // MARK: - Interne

    private static func route(_ segments: [String], query: (String) -> String?) -> DeepLinkTarget? {
        guard let locale = segments.first, locales.contains(locale) else { return nil }
        let rest = Array(segments.dropFirst())
        if rest.count == 2, rest[0] == "annonce" { return .listing(idOrSlug: rest[1]) }
        if rest.count == 3, rest[0] == "annonce", rest[2] == "modifier" { return .editListing(id: rest[1]) }
        if rest.count == 2, rest[0] == "profil" { return .seller(id: rest[1]) }
        if rest.count == 2, rest[0] == "c" { return .listings(params: ["category": rest[1]]) }
        if rest == ["annonces"] { return .listings(params: searchParameters(query)) }
        if rest == ["categories"] { return .listings(params: [:]) }
        if rest == ["deposer"] { return .post }
        if rest == ["dashboard"] || rest == ["dashboard", "settings"] { return .profile }
        if rest == ["dashboard", "messages"] { return .messages }
        if rest.count == 3, rest[0] == "dashboard", rest[1] == "messages" { return .conversation(id: rest[2]) }
        if rest == ["dashboard", "annonces"] { return .myListings }
        if rest == ["dashboard", "favorites"] { return .favorites }
        if rest == ["auth", "reinitialiser-mdp"] {
            guard let token = TextCheck.nonBlank(query("token")) else { return nil }
            return .resetPassword(token: token)
        }
        if isListingPath(segments) { return .listing(idOrSlug: segments[2]) }
        return nil
    }

    private static func isListingPath(_ segments: [String]) -> Bool {
        guard segments.count == 3, locales.contains(segments[0]) else { return false }
        return !staticRoots.contains(segments[1]) && !TextCheck.isBlank(segments[2])
    }

    private static func searchParameters(_ query: (String) -> String?) -> [String: String] {
        var parameters: [String: String] = [:]
        for key in listingParams {
            if let value = TextCheck.nonBlank(query(key)) { parameters[key] = value }
        }
        return parameters
    }

    private static func pathSegments(of components: URLComponents) -> [String] {
        components.percentEncodedPath
            .split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }
            .filter { !$0.isEmpty }
    }

    /// Première valeur de chaque clé, `+` lu comme une espace (formulaires et `URLSearchParams` du site,
    /// comme `Uri.getQueryParameter`).
    private static func queryParameters(_ percentEncodedQuery: String?) -> [String: String] {
        guard let query = percentEncodedQuery, !query.isEmpty else { return [:] }
        var parameters: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = pieces.first else { continue }
            let key = decodeQueryComponent(rawKey)
            if parameters[key] == nil {
                parameters[key] = pieces.count > 1 ? decodeQueryComponent(pieces[1]) : ""
            }
        }
        return parameters
    }

    private static func decodeQueryComponent(_ raw: Substring) -> String {
        let spaced = raw.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
