import Combine
import SwiftUI

/// Onglet Annonces — point d'entrée du contrat (`RootView`) : crée le ViewModel avec les repositories du conteneur.
struct ListingsView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        ListingsHost(
            model: ListingsViewModel(
                annonces: container.annonces,
                categories: container.categories,
                geo: container.geo,
                attributes: container.attributes,
                search: container.search,
                favorites: container.favorites,
                savedSearches: container.savedSearches,
                online: container.connectivity.$isOnline.eraseToAnyPublisher()
            )
        )
    }
}

/// Possède le ViewModel, consomme les critères d'ouverture du routeur (`router.listingsLaunch`, remis à nil) et
/// branche les actions réservées aux membres (favori, alerte) : un visiteur est envoyé vers la connexion.
private struct ListingsHost: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: ListingsViewModel
    @FocusState private var searchFocused: Bool

    init(model: @autoclosure @escaping () -> ListingsViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        ListingsScreen(
            state: model.state,
            suggestions: model.suggestions,
            history: model.history,
            favoriteIds: model.favoriteIds,
            searchFocus: $searchFocused,
            filtersPresented: filtersPresented,
            actions: actions,
            onRefresh: refreshAction,
            onNoticeShown: noticeShownAction
        )
        .task(id: router.listingsLaunch) {
            await consumeLaunch()
        }
    }

    /// Premier affichage, puis chaque ouverture de l'onglet avec des critères (accueil, lien `/annonces?…`).
    /// `ListingsLaunch(q: "")` — mot-clé présent mais vide — ouvre la recherche clavier sorti (faux champ de l'accueil).
    private func consumeLaunch() async {
        let launch = router.consumeListingsLaunch()
        model.start(with: launch)
        if let launch, let keyword = launch.q, TextCheck.isBlank(keyword) {
            searchFocused = true
        }
    }

    /// Feuille de filtres : présentée d'après l'état ; la fermer (glisser, « Fermer ») le dit au ViewModel.
    private var filtersPresented: Binding<Bool> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.showFilters } },
            set: { shown in
                MainActor.assumeIsolated {
                    if !shown {
                        model.closeFilters()
                    }
                }
            }
        )
    }

    private var refreshAction: @MainActor @Sendable () async -> Void {
        let model = self.model
        return { await model.refresh() }
    }

    private var noticeShownAction: @MainActor @Sendable () -> Void {
        let model = self.model
        return { model.noticeShown() }
    }

    private var actions: ListingsActions {
        let model = self.model
        let router = self.router
        let session = container.sessionManager
        return ListingsActions(
            onQueryChange: { model.onQueryChange($0) },
            onSubmitSearch: { model.search() },
            onSuggestionPick: { model.onSuggestionPick($0) },
            onHistoryPick: { model.onHistoryPick($0) },
            onClearHistory: { model.clearHistory() },
            onCategorySelect: { model.onCategorySelect($0) },
            onSubcategoryToggle: { model.onSubcategoryToggle($0) },
            onRemoveFilter: { model.removeFilter($0) },
            onClearFilters: { model.clearFilters() },
            onOpenFilters: { model.openFilters() },
            onCloseFilters: { model.closeFilters() },
            onApplyFilters: { model.applyFilters($0) },
            onFilterWilayaChange: { model.onFilterWilayaChange($0) },
            onDraftAttributesChange: { subcategory, attributes in
                model.loadDependentOptions(subcategory: subcategory, attributes: attributes)
            },
            onSaveSearch: {
                if session.isLoggedIn {
                    model.saveSearch()
                } else {
                    router.requestLogin()
                }
            },
            onRetry: { model.search() },
            onLoadMore: { model.loadMore() },
            onRetryLoadMore: { model.retryLoadMore() },
            onDidYouMean: { model.onDidYouMean($0) },
            onToggleFavorite: { listing in
                if session.isLoggedIn {
                    // Favori optimiste : petit choc avec le cœur qui se remplit (ajout seulement).
                    if !model.favoriteIds.contains(listing.id) {
                        Haptics.impact()
                    }
                    model.toggleFavorite(listing)
                } else {
                    router.requestLogin()
                }
            }
        )
    }
}
