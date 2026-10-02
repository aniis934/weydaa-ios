import Foundation

// Portage de data/remote/dto/ReportDtos.kt — signalement (src/app/api/reports/route.ts, `reportSchema`) :
// POST { annonceId?, reportedUserId?, conversationId?, reason, details? } → 201 ligne Report. 401 `unauthorized`,
// 403 `emailNotVerified`, 409 `alreadyReported`, 404 `notFound`, 400 `invalidData`.

nonisolated struct ReportRequestDTO: Encodable, Hashable, Sendable {
    /// Annonce signalée — ou `reportedUserId` pour signaler un utilisateur (au moins l'un des deux).
    var annonceId: String? = nil
    var reportedUserId: String? = nil
    /// Fil d'où part le signalement d'un utilisateur (contexte pour la modération).
    var conversationId: String? = nil
    /// `ReportReason.rawValue` : `SPAM` | `INAPPROPRIATE` | `FRAUD` | `DUPLICATE` | `OTHER`.
    var reason: String
    /// Précisions facultatives, `ReportReason.detailsMax` caractères au maximum côté serveur.
    var details: String? = nil
}

nonisolated struct ReportDTO: Decodable, Hashable, Sendable {
    var id: String = ""
    var annonceId: String = ""
    var reason: String = ""
    var details: String? = nil
    var resolved: Bool = false
    var createdAt: String = ""
}

nonisolated extension ReportDTO {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DTOKey.self)
        id = container.lenientString("id") ?? ""
        annonceId = container.lenientString("annonceId") ?? ""
        reason = container.lenientString("reason") ?? ""
        details = container.lenientString("details")
        resolved = container.lenientBool("resolved") ?? false
        createdAt = container.lenientString("createdAt") ?? ""
    }
}
