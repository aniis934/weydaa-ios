import Foundation

// Portage de data/remote/dto/ContactDtos.kt — contact, vues, tendances, « vouliez-vous dire », langue, push.

/// `POST /api/contact` (`contactSchema` du site : nom 2–100, e-mail, sujet 3–200, message 10–5000).
nonisolated struct ContactRequestDTO: Encodable, Hashable, Sendable {
    var name: String
    var email: String
    var subject: String
    var message: String
}

/// `POST /api/annonces/{id}/view` : vue comptée (faux si déjà comptée récemment, ou propriétaire).
nonisolated struct ViewCountDTO: Decodable, Hashable, Sendable {
    var counted: Bool = false
}

nonisolated extension ViewCountDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        counted = container.lenientBool("counted") ?? false
    }
}

/// `GET /api/annonces/trending` et `GET /api/recommendations` → `{ annonces: [...] }` (forme publique, sans téléphone).
nonisolated struct AnnonceListDTO: Decodable, Hashable, Sendable {
    var annonces: [AnnonceDTO] = []
}

nonisolated extension AnnonceListDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        annonces = container.lenientList(AnnonceDTO.self, "annonces")
    }
}

/// `GET /api/search/did-you-mean?q=` → correction proposée (ou nil).
nonisolated struct DidYouMeanDTO: Decodable, Hashable, Sendable {
    var suggestion: String? = nil
}

nonisolated extension DidYouMeanDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        suggestion = container.lenientString("suggestion")
    }
}

/// `PUT /api/users/me` `{ locale }` seul : langue des e-mails et notifications envoyés à ce compte.
nonisolated struct LocaleUpdateRequestDTO: Encodable, Hashable, Sendable {
    var locale: String
}

/// `POST /api/push/fcm` : jeton FCM de l'appareil, rattaché au compte connecté (langue des notifications).
/// `platform` (lot serveur B) : "ios" → le serveur ajoute l'alerte APNs traduite ; absent, il suppose "android".
nonisolated struct FcmTokenRequestDTO: Encodable, Hashable, Sendable {
    var token: String
    var locale: String
    var platform: String = "ios"
}
