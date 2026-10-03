import SwiftUI

/// Navigation de l'app : l'onglet courant et une pile par onglet — le NavController de `WeydaRoot.kt` (Android),
/// découpé à la manière d'iOS (chaque onglet garde sa pile quand on passe à un autre). Créé par `WeydaApp`,
/// posé dans l'environnement : `@EnvironmentObject private var router: AppRouter`.
///
/// Dans un écran : `router.push(.detail(idOrSlug: listing.id))` ou `NavigationLink(value: AppRoute.detail(…))`
/// (les deux passent par la même pile) ; onglet Annonces avec des critères : `router.openListings(…)`.
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .home
    /// Critères d'ouverture de l'onglet Annonces, consommés (remis à nil) par cet onglet.
    @Published var listingsLaunch: ListingsLaunch? = nil
    /// Page légale présentée en feuille par `RootView` (SFSafariViewController).
    @Published var presentedWebPage: WebPage? = nil
    /// Pile de chaque onglet (vide = la racine de l'onglet).
    @Published private(set) var stacks: [AppTab: [AppRoute]] = [:]

    /// `launchRoute` : `-WeydaRoute` (tour de captures), appliqué avant le premier écran.
    init(initialTab: AppTab = LaunchOptions.initialTab ?? .home, launchRoute: String? = LaunchOptions.route) {
        selectedTab = initialTab
        if let launchRoute, let parsed = LaunchRoute.parse(launchRoute) {
            apply(parsed)
        }
    }

    // MARK: - Piles

    func stack(for tab: AppTab) -> [AppRoute] {
        stacks[tab] ?? []
    }

    /// Empile sur l'onglet courant. Une page légale est présentée en feuille (SFSafariViewController se présente,
    /// il ne se pousse pas). La même route deux fois de suite (double appui pendant la transition) est ignorée,
    /// comme `guardedNavigate` d'Android.
    func push(_ route: AppRoute) {
        if case .webPage(let page) = route {
            presentedWebPage = page
            return
        }
        var routes = stack(for: selectedTab)
        guard routes.last != route else { return }
        routes.append(route)
        stacks[selectedTab] = routes
    }

    /// Retire l'écran du dessus de l'onglet courant (les écrans ont aussi `@Environment(\.dismiss)`).
    func pop() {
        var routes = stack(for: selectedTab)
        guard !routes.isEmpty else { return }
        routes.removeLast()
        stacks[selectedTab] = routes
    }

    func popToRoot(_ tab: AppTab) {
        guard !stack(for: tab).isEmpty else { return }
        stacks[tab] = []
    }

    /// Pile liée à la `NavigationStack` d'un onglet : retour, glissement et `NavigationLink(value:)` écrivent ici.
    func path(for tab: AppTab) -> Binding<[AppRoute]> {
        // `assumeIsolated` : SwiftUI lit et écrit les liaisons sur le fil principal ; l'appel reste correct que le
        // SDK déclare ou non ces fermetures `@Sendable`.
        Binding(
            get: { MainActor.assumeIsolated { self.stack(for: tab) } },
            set: { newValue in MainActor.assumeIsolated { self.setStack(newValue, for: tab) } }
        )
    }

    /// Écriture venue de la pile de navigation ; le double appui sur un lien (même route empilée deux fois) est ignoré.
    func setStack(_ newStack: [AppRoute], for tab: AppTab) {
        let current = stack(for: tab)
        if newStack.count == current.count + 1, newStack.last == current.last, newStack.starts(with: current) {
            return
        }
        guard newStack != current else { return }
        stacks[tab] = newStack
    }

    // MARK: - Onglets

    /// Sélection de la barre d'onglets : toucher l'onglet déjà actif remonte sa pile à la racine (convention iOS,
    /// et `navigateToTab` d'Android).
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { MainActor.assumeIsolated { self.selectedTab } },
            set: { tab in MainActor.assumeIsolated { self.select(tab) } }
        )
    }

    func select(_ tab: AppTab) {
        if tab == selectedTab {
            popToRoot(tab)
        } else {
            selectedTab = tab
        }
    }

    /// Bascule sur l'onglet Annonces, revenu à sa racine (les résultats, pas une fiche ouverte avant), avec ces
    /// critères — recherche ou catégorie de l'accueil, lien `/annonces?…`.
    func openListings(_ launch: ListingsLaunch) {
        presentedWebPage = nil
        listingsLaunch = launch
        popToRoot(.listings)
        selectedTab = .listings
    }

    /// Lit les critères d'ouverture de l'onglet Annonces et les efface (à appeler par cet onglet).
    @discardableResult
    func consumeListingsLaunch() -> ListingsLaunch? {
        let launch = listingsLaunch
        if launch != nil { listingsLaunch = nil }
        return launch
    }

    // MARK: - Connexion

    /// Un visiteur touche une action réservée aux membres (favori, contacter, voir le numéro, signaler). Phase 2 :
    /// l'onglet Profil, revenu à sa racine, affiche `LoginRequired`. Phase 3 : la feuille de connexion (et la
    /// reprise de l'action une fois connecté).
    func requestLogin() {
        presentedWebPage = nil
        popToRoot(.account)
        selectedTab = .account
    }

    // MARK: - Liens profonds

    /// Lien du site ou du schéma `weydaa://` (DeepLinks) : l'écran visé est empilé sur l'onglet courant (rien n'est
    /// perdu), les onglets sont sélectionnés — portage de `NavHostController.open` (WeydaRoot.kt). La garde
    /// « connexion requise » des écrans de compte arrive avec la phase 3.
    func open(_ target: DeepLinkTarget) {
        presentedWebPage = nil
        switch target {
        case .listing(let idOrSlug):
            push(.detail(idOrSlug: idOrSlug))
        case .editListing(let id):
            push(.editListing(id: id))
        case .seller(let id):
            push(.seller(id: id))
        case .conversation(let id):
            push(.chat(conversationId: id, archived: false))
        case .listings(let params):
            openListings(ListingsLaunch(params: params))
        case .resetPassword:
            // Écran « nouveau mot de passe » : phase 3 (compte). D'ici là, l'onglet Profil.
            selectedTab = .account
        case .post:
            selectedTab = .post
        case .messages:
            selectedTab = .messages
        case .profile:
            selectedTab = .account
        case .myListings:
            push(.myListings)
        case .favorites:
            push(.favorites)
        }
    }

    // MARK: - Démarrage

    private func apply(_ launch: LaunchRoute) {
        switch launch {
        case .tab(let tab):
            selectedTab = tab
        case .listings(let criteria):
            openListings(criteria)
        case .route(let route):
            if let tab = LaunchRoute.preferredTab(for: route) {
                selectedTab = tab
            }
            push(route)
        }
    }
}
