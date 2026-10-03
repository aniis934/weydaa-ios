import Combine
import SwiftUI

/// Onglet Accueil — point d'entrée du contrat de la phase 2, portage de `HomeRoute` (ui/home/HomeScreen.kt) :
/// crée le ViewModel avec les repositories du conteneur et branche les gestes sur le routeur.
struct HomeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var router: AppRouter

    init() {}

    var body: some View {
        // Références lues ici : le ViewModel n'est créé qu'une fois (StateObject), et ses fermetures tiennent les
        // objets eux-mêmes plutôt que cette vue.
        let shared = container
        let navigation = router
        HomeHost(
            model: HomeViewModel(
                annonces: shared.annonces,
                categories: shared.categories,
                geo: shared.geo,
                favorites: shared.favorites,
                session: shared.sessionManager.$user.eraseToAnyPublisher(),
                online: shared.connectivity.$isOnline.eraseToAnyPublisher(),
                onLoginRequired: { navigation.requestLogin() }
            ),
            notifications: shared.notifications
        )
    }
}

/// Possède le ViewModel et l'état d'interface de l'accueil (feuille des catégories ouverte ou non).
private struct HomeHost: View {
    @StateObject private var model: HomeViewModel
    @ObservedObject private var notifications: NotificationsRepository
    @EnvironmentObject private var router: AppRouter
    @State private var showsCategories: Bool

    init(model: @autoclosure @escaping () -> HomeViewModel, notifications: NotificationsRepository) {
        _model = StateObject(wrappedValue: model())
        self.notifications = notifications
        _showsCategories = State(initialValue: HomeLaunchOption.opensCategories)
    }

    var body: some View {
        // Les tâches ne tiennent que le ViewModel (Sendable : isolé au MainActor), pas cette vue.
        let viewModel = model
        HomeScreen(
            state: viewModel.state,
            favoriteIds: viewModel.favoriteIds,
            notificationsUnread: unreadNotifications,
            actions: actions
        )
        // Posé AVANT la feuille : la liste des catégories ne doit pas hériter du « tirer pour rafraîchir ».
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(isPresented: $showsCategories) {
            CategoriesSheet(categories: viewModel.state.categories, onSelect: openFromSheet)
        }
    }

    /// Pastille de la cloche : seulement pour un compte connecté (nil = pas de cloche).
    private var unreadNotifications: Int? {
        model.isLoggedIn ? notifications.unreadCount : nil
    }

    private var actions: HomeActions {
        let navigation = router
        let viewModel = model
        return HomeActions(
            retry: { viewModel.retry() },
            openSearch: { navigation.openListings(ListingsLaunch(q: "")) },
            openCategory: { category in navigation.openListings(ListingsLaunch(category: category.slug)) },
            showAllCategories: { showsCategories = true },
            seeAllFeatured: { navigation.openListings(ListingsLaunch(featured: true)) },
            seeAllRecent: { navigation.openListings(ListingsLaunch()) },
            openWilaya: { wilaya in navigation.openListings(ListingsLaunch(wilaya: wilaya.id)) },
            toggleFavorite: { listing in viewModel.toggleFavorite(listing) },
            openNotifications: { navigation.push(.notifications) },
            post: { navigation.select(.post) }
        )
    }

    /// Choix dans la feuille : elle se ferme, puis l'onglet Annonces s'ouvre sur ces critères.
    private func openFromSheet(_ choice: CategorySheetChoice) {
        showsCategories = false
        router.openListings(choice.launch)
    }
}

/// Tour de captures : `-WeydaHomeSheet categories` ouvre la feuille des catégories dès l'affichage de l'accueil
/// (une feuille n'a pas de route `-WeydaRoute`). Sans effet hors Debug.
private nonisolated enum HomeLaunchOption {
    static var opensCategories: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "WeydaHomeSheet") == "categories"
        #else
        return false
        #endif
    }
}
