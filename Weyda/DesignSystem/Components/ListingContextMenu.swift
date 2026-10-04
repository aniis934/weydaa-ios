import SwiftUI

/// Entrées du menu d'appui long d'une carte d'annonce. Valeur pure, construite par l'écran (il sait qui est connecté).
nonisolated struct ListingCardMenu: Sendable {
    /// Page de l'annonce sur le site (« Partager ») ; nil = pas d'entrée Partager.
    let shareURL: URL?
    /// « Ajouter aux favoris » / « Retirer des favoris » proposé (un visiteur y a droit : l'appui ouvre la connexion).
    let canFavorite: Bool
    /// Vendeur à ouvrir (« Voir le vendeur ») ; nil = pas d'entrée (vendeur inconnu, ou annonce de l'utilisateur).
    let sellerId: String?

    init(shareURL: URL?, canFavorite: Bool, sellerId: String?) {
        self.shareURL = shareURL
        self.canFavorite = canFavorite
        self.sellerId = sellerId
    }

    /// Menu par défaut d'une carte : lien du site dans la langue de l'app, favori proposé, vendeur sauf si c'est
    /// l'utilisateur connecté (`currentUserId`).
    init(listing: Listing, currentUserId: String?, canFavorite: Bool = true) {
        let seller: String? = TextCheck.nonBlank(listing.sellerId) ?? TextCheck.nonBlank(listing.seller?.id)
        self.shareURL = DetailLinks.webURL(for: listing)
        self.canFavorite = canFavorite
        self.sellerId = seller == currentUserId ? nil : seller
    }
}

extension View {
    /// Menu d'appui long d'une carte d'annonce (aperçu = la carte à largeur fixe) : favori, Partager, Voir le vendeur.
    /// À poser sur le `NavigationLink` À L'APPEL (pas dans la carte : `.weydaCard` et l'accessibilité de la carte restent
    /// intacts). `onSeller` nil = pas d'entrée « Voir le vendeur » (écran du vendeur lui-même).
    func listingContextMenu(
        _ listing: Listing,
        menu: ListingCardMenu,
        isFavorite: Bool,
        onFavorite: @escaping () -> Void,
        onSeller: ((String) -> Void)?
    ) -> some View {
        contextMenu {
            ListingContextMenuItems(
                menu: menu,
                isFavorite: isFavorite,
                onFavorite: onFavorite,
                onSeller: onSeller
            )
        } preview: {
            ListingContextMenuPreview(listing: listing, isFavorite: isFavorite)
        }
    }
}

private struct ListingContextMenuItems: View {
    private let menu: ListingCardMenu
    private let isFavorite: Bool
    private let onFavorite: () -> Void
    private let onSeller: ((String) -> Void)?

    init(menu: ListingCardMenu, isFavorite: Bool, onFavorite: @escaping () -> Void, onSeller: ((String) -> Void)?) {
        self.menu = menu
        self.isFavorite = isFavorite
        self.onFavorite = onFavorite
        self.onSeller = onSeller
    }

    var body: some View {
        if menu.canFavorite {
            Button(action: onFavorite) {
                Label(isFavorite ? L10n.favoriteRemove : L10n.favoriteAdd, systemImage: isFavorite ? "heart.slash" : "heart")
            }
        }
        if let url = menu.shareURL {
            ShareLink(item: url) {
                Label(L10n.share, systemImage: "square.and.arrow.up")
            }
        }
        if let sellerId = menu.sellerId, let onSeller {
            Button {
                onSeller(sellerId)
            } label: {
                Label(L10n.menuSeeSeller, systemImage: "person.crop.circle")
            }
        }
    }
}

/// Aperçu du menu : la carte du carrousel, à sa largeur fixe, sans bouton favori actif (l'aperçu ne se touche pas).
private struct ListingContextMenuPreview: View {
    private let listing: Listing
    private let isFavorite: Bool

    init(listing: Listing, isFavorite: Bool) {
        self.listing = listing
        self.isFavorite = isFavorite
    }

    var body: some View {
        ListingCard(listing: listing, isFavorite: isFavorite)
            .frame(width: WeydaSize.carouselCard)
            .padding(WeydaSpace.sm)
            .background(WeydaColor.background)
    }
}
