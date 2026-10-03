import Foundation

/// Règles des offres — portage de `model/OfferRules.kt` (Android), lui-même miroir de `src/lib/offers.ts`.
///
/// Une négociation vit dans la conversation sous forme de messages `.offer`. L'état courant = le DERNIER
/// message d'offre du fil :
///   - `.new` / `.counter` → offre OUVERTE, en attente de réponse ;
///   - `.accepted` / `.declined` → négociation close, on peut en relancer une.
/// Les boutons n'apparaissent que sur cette dernière offre ouverte, et seulement pour la partie qui n'en est PAS
/// l'émettrice. Le serveur revérifie tout en transaction : ces règles évitent seulement de proposer une action
/// vouée à un 409.
nonisolated enum OfferRules {
    /// Codes de refus identiques au serveur.
    static let offerAlreadyOpen = "offerAlreadyOpen"
    static let noOpenOffer = "noOpenOffer"
    static let cannotRespondOwnOffer = "cannotRespondOwnOffer"
    static let annonceUnavailable = "annonceUnavailable"

    /// Le DERNIER message d'offre du fil s'il est exploitable (metadata valide), sinon nil — comme le serveur,
    /// qui lit la dernière ligne OFFER puis la juge. Remonter à une offre valide plus ancienne proposait (ou
    /// masquait) des actions que le serveur refusait ensuite en 409.
    static func latestOffer(_ messages: [ChatMessage]) -> ChatMessage? {
        guard let last = messages.last(where: { $0.type == .offer }), last.offer != nil else { return nil }
        return last
    }

    /// La dernière offre si elle attend encore une réponse.
    static func openOffer(_ messages: [ChatMessage]) -> ChatMessage? {
        guard let latest = latestOffer(messages), latest.offer?.kind.isOpen == true else { return nil }
        return latest
    }

    /// Raison de refus d'une action (codes du serveur ci-dessus), ou nil si elle est permise.
    static func deniedReason(
        _ action: OfferAction,
        userId: String,
        messages: [ChatMessage],
        annonce: ConversationAnnonce? = nil
    ) -> String? {
        // Même garde que « Faire une offre » sur l'annonce : rien sauf refuser sur une annonce vendue, expirée,
        // supprimée ou gratuite (refuser reste permis pour clore proprement).
        if action != .decline, let annonce, !annonce.acceptsOffers {
            return annonceUnavailable
        }
        guard let pending = openOffer(messages) else {
            return action == .new ? nil : noOpenOffer
        }
        if action == .new { return offerAlreadyOpen }
        if pending.senderId == userId { return cannotRespondOwnOffer }
        return nil
    }

    /// Actions proposables à `userId` dans l'état courant du fil.
    static func availableActions(
        userId: String,
        messages: [ChatMessage],
        annonce: ConversationAnnonce? = nil
    ) -> Set<OfferAction> {
        Set(OfferAction.allCases.filter { deniedReason($0, userId: userId, messages: messages, annonce: annonce) == nil })
    }

    /// Vrai si `message` est l'offre ouverte à laquelle `userId` peut répondre.
    static func isActionable(_ message: ChatMessage, by userId: String, messages: [ChatMessage]) -> Bool {
        guard message.offer?.kind.isOpen == true, message.senderId != userId else { return false }
        return openOffer(messages)?.id == message.id
    }
}
