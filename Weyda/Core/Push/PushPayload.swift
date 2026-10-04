import Foundation

/// Données utiles d'un push Weydaa, extraites TOUT DE SUITE du `userInfo` (dictionnaire non `Sendable`) en une valeur
/// qui peut changer de fil — portage de la lecture de `RemoteMessage.data` (`WeydaMessagingService`, Android).
///
/// Charge du serveur (lot B, `src/lib/fcm.ts`) : les clés `data` de FCM arrivent à la racine du payload APNs, à côté de
/// `aps` (alerte déjà traduite, son, `thread-id`, pastille) : `type`, `title`, `body`, `url` (chemin du site préfixé par la
/// langue de l'appareil : `/ar/dashboard/messages/<id>`), `conversationId`, `annonceId`, `notificationId`.
nonisolated struct PushPayload: Hashable, Sendable {
    /// `NotificationType` du serveur (MESSAGE, OFFER_RECEIVED…).
    let type: String?
    let title: String?
    let body: String?
    /// Chemin du site à ouvrir à l'appui (avec ou sans préfixe de langue), ou URL complète du site.
    let url: String?
    let conversationId: String?
    let annonceId: String?
    let notificationId: String?

    init(
        type: String? = nil,
        title: String? = nil,
        body: String? = nil,
        url: String? = nil,
        conversationId: String? = nil,
        annonceId: String? = nil,
        notificationId: String? = nil
    ) {
        self.type = type
        self.title = title
        self.body = body
        self.url = url
        self.conversationId = conversationId
        self.annonceId = annonceId
        self.notificationId = notificationId
    }
}

nonisolated extension PushPayload {
    /// Lecture tolérante du `userInfo` d'une notification : valeurs vides ignorées, nombres acceptés ; titre et corps
    /// repris de `aps.alert` quand la partie `data` ne les porte pas.
    init(userInfo: [AnyHashable: Any]) {
        func field(_ key: String) -> String? {
            Self.text(userInfo[AnyHashable(key)])
        }
        let alert = Self.alert(in: userInfo)
        self.init(
            type: field("type"),
            title: field("title") ?? alert.title,
            body: field("body") ?? alert.body,
            url: field("url"),
            conversationId: field("conversationId"),
            annonceId: field("annonceId"),
            notificationId: field("notificationId")
        )
    }

    /// Écran visé par l'appui : le chemin du site (`url`, routé comme un lien universel par `DeepLinks`), sinon le fil
    /// (`conversationId`), sinon la fiche (`annonceId`). Un chemin sans langue reçoit celle de l'app.
    func target(language: String = WeydaLocale.language) -> DeepLinkTarget? {
        if let url, let target = Self.resolve(link: url, language: language) {
            return target
        }
        if let conversationId {
            return .conversation(id: conversationId)
        }
        if let annonceId {
            return .listing(idOrSlug: annonceId)
        }
        return nil
    }

    /// Fil de discussion concerné : `conversationId`, ou celui du lien (`/…/dashboard/messages/<id>`).
    var threadId: String? {
        if let conversationId { return conversationId }
        if case .conversation(let id) = target() { return id }
        return nil
    }

    /// Bannière au premier plan ? Pas pour le fil déjà à l'écran : le message y arrive en direct (Android : aucune
    /// notification en double).
    func isShown(whileViewing visibleConversationId: String?) -> Bool {
        guard let visibleConversationId, let threadId else { return true }
        return threadId != visibleConversationId
    }

    /// `/dashboard/messages/x` → `/<langue>/dashboard/messages/x` ; un chemin déjà préfixé (`/ar/…`) est gardé tel quel.
    static func localizedPath(_ path: String, language: String) -> String {
        let first = String(path.dropFirst().prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        if WeydaLocale.supported.contains(first) { return path }
        let locale = WeydaLocale.supported.contains(language) ? language : "fr"
        return path == "/" ? "/\(locale)" : "/\(locale)\(path)"
    }

    // MARK: - Interne

    private static func resolve(link: String, language: String) -> DeepLinkTarget? {
        if link.hasPrefix("/") {
            return DeepLinks.resolve(sitePath: localizedPath(link, language: language))
        }
        guard let url = URL(string: link) else { return nil }
        return DeepLinks.resolve(url)
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return TextCheck.nonBlank(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    /// `aps.alert` : dictionnaire `{ title, body }` (envoi du serveur) ou simple chaîne.
    private static func alert(in userInfo: [AnyHashable: Any]) -> (title: String?, body: String?) {
        guard let aps = userInfo[AnyHashable("aps")] as? [String: Any] else { return (nil, nil) }
        if let alert = aps["alert"] as? [String: Any] {
            return (text(alert["title"]), text(alert["body"]))
        }
        return (nil, text(aps["alert"]))
    }
}
