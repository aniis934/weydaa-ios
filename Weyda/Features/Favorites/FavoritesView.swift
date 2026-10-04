import Combine
import SwiftUI

/// « Mes favoris » (écran poussé depuis le Profil, lien `/dashboard/favorites`) — portage de `FavoritesRoute`
/// (FavoritesScreen.kt). Écran de membre (`AccountMemberGate`) : un visiteur voit l'invitation à se connecter ; le
/// contenu est recréé pour un autre compte.
struct FavoritesView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.favoritesTitle) { user in
            FavoritesHost(
                model: FavoritesViewModel(
                    favorites: container.favorites,
                    session: container.sessionManager.$user.eraseToAnyPublisher()
                ),
                currentUserId: user.id
            )
        }
    }
}

/// Possède le ViewModel ; branche les actions sur le ViewModel et le routeur. Relit la liste en silence à chaque
/// retour sur l'écran (un favori remis depuis une fiche y reparaît).
private struct FavoritesHost: View {
    @StateObject private var model: FavoritesViewModel
    @EnvironmentObject private var router: AppRouter
    private let currentUserId: String?

    init(model: @autoclosure @escaping () -> FavoritesViewModel, currentUserId: String?) {
        _model = StateObject(wrappedValue: model())
        self.currentUserId = currentUserId
    }

    var body: some View {
        FavoritesScreen(state: model.state, currentUserId: currentUserId, actions: actions)
            // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
            .refreshable { @MainActor [model] in
                await model.pullToRefresh()
            }
            .onAppear {
                _ = model.appear()
            }
    }

    private var actions: FavoritesActions {
        let model = self.model
        let router = self.router
        return FavoritesActions(
            onOpen: { (listing: Listing) in
                // Même clé que la source posée sur la carte : la fiche zoome depuis elle (iOS 18).
                router.push(.detail(idOrSlug: listing.id, zoomSource: FavoritesScreen.zoomKey(for: listing)))
            },
            onRemove: { (listing: Listing) in
                _ = model.remove(listing)
            },
            onSeller: { (sellerId: String) in
                router.push(.seller(id: sellerId))
            },
            onRetry: {
                _ = model.load()
            },
            onBrowse: {
                // L'onglet Annonces, revenu à ses résultats (Android : `navigateToTab(Listings)`).
                router.popToRoot(.listings)
                router.select(.listings)
            },
            onBannerAction: { (action: BannerAction) in
                _ = model.bannerAction(action)
            },
            onBannerDismiss: {
                model.bannerDismissed()
            }
        )
    }
}

/// Actions de « Mes favoris » (branchées par l'hôte sur le ViewModel et le routeur).
struct FavoritesActions {
    var onOpen: (Listing) -> Void
    var onRemove: (Listing) -> Void
    /// « Voir le vendeur » du menu d'appui long.
    var onSeller: (String) -> Void
    var onRetry: () -> Void
    var onBrowse: () -> Void
    /// « Annuler » de la bannière « Retiré des favoris ».
    var onBannerAction: (BannerAction) -> Void
    var onBannerDismiss: () -> Void
}
