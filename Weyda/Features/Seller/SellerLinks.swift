import Foundation

/// Liens du profil public d'un vendeur (logique pure).
nonisolated enum SellerLinks {
    /// Page du vendeur sur le site, dans la langue de l'app (partage) : `https://weydaa.com/<fr|ar|en>/profil/<id>` —
    /// jamais l'hôte de l'API ; la même page ouvre l'app par lien universel (`DeepLinks`). nil sans identifiant.
    static func webURL(sellerId: String, language: String = WeydaLocale.language) -> URL? {
        let id = sellerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return DeepLinks.siteURL.appending(path: language).appending(path: "profil").appending(path: id)
    }
}
