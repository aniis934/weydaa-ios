import SwiftUI

/// « Mes alertes » (écran poussé depuis le Profil) — portage de `SavedSearchesRoute` (SavedSearchesScreen.kt). Écran de
/// membre (`AccountMemberGate`) : un visiteur voit l'invitation à se connecter ; le contenu est recréé pour un autre
/// compte.
struct SavedSearchesView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.alertsTitle) { _ in
            SavedSearchesHost(
                model: SavedSearchesViewModel(
                    savedSearches: container.savedSearches,
                    search: container.search,
                    categories: container.categories,
                    geo: container.geo
                )
            )
        }
    }
}

/// Possède le ViewModel ; branche les actions sur le ViewModel et le routeur. Relit la liste en silence à chaque
/// retour sur l'écran (une alerte créée depuis l'onglet Annonces y paraît) ; en le quittant, envoie la suppression
/// encore en attente d'« Annuler ».
private struct SavedSearchesHost: View {
    @StateObject private var model: SavedSearchesViewModel
    @EnvironmentObject private var router: AppRouter

    init(model: @autoclosure @escaping () -> SavedSearchesViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        SavedSearchesScreen(
            state: model.state,
            limit: model.limit,
            actions: actions
        )
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor [model] in
            await model.pullToRefresh()
        }
        .onAppear {
            _ = model.appear()
        }
        .onDisappear {
            _ = model.disappear()
        }
    }

    private var actions: SavedSearchesActions {
        let model = self.model
        let router = self.router
        return SavedSearchesActions(
            onOpen: { (alert: SavedSearch) in
                // Les paramètres d'abord : l'onglet Annonces les lit à sa création s'il n'a jamais été affiché, ou dès
                // leur dépôt sinon ; puis l'onglet, revenu à ses résultats (pas une fiche ouverte avant).
                model.open(alert)
                router.popToRoot(.listings)
                router.select(.listings)
            },
            onDelete: { (alert: SavedSearch) in
                _ = model.delete(alert)
            },
            onRetry: {
                _ = model.load()
            },
            onSearch: {
                router.popToRoot(.listings)
                router.select(.listings)
            },
            onBannerAction: { (action: BannerAction) in
                model.bannerAction(action)
            },
            onBannerDismiss: {
                _ = model.bannerDismissed()
            }
        )
    }
}

/// Actions de « Mes alertes » (branchées par l'hôte sur le ViewModel et le routeur).
struct SavedSearchesActions {
    var onOpen: (SavedSearch) -> Void
    /// Suppression différée (bannière « Alerte supprimée » + « Annuler »), sans boîte de confirmation.
    var onDelete: (SavedSearch) -> Void
    var onRetry: () -> Void
    /// Vers l'onglet Annonces (une alerte se crée depuis une recherche).
    var onSearch: () -> Void
    /// « Annuler » de la bannière.
    var onBannerAction: (BannerAction) -> Void
    /// Bannière fermée : la suppression en attente part.
    var onBannerDismiss: () -> Void
}
