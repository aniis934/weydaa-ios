import SwiftUI

/// Écran d'entrée de la feuille de connexion (`AuthFlowView`, présentée par `RootView`) — les routes `auth/*` de
/// `Screen.kt` (Android), regroupées dans une feuille comme le veut iOS. Valeur pure : elle sert aussi d'étape à la
/// pile de navigation de la feuille.
nonisolated enum AuthEntry: Hashable, Identifiable, Sendable {
    case login
    case register
    case forgotPassword
    case verifyEmail
    /// Lien « mot de passe oublié » de l'e-mail : `/{locale}/auth/reinitialiser-mdp?token=…`.
    case resetPassword(token: String)

    var id: String {
        switch self {
        case .login: "login"
        case .register: "register"
        case .forgotPassword: "forgot"
        case .verifyEmail: "verify"
        case .resetPassword(let token): "reset:\(token)"
        }
    }

    /// `-WeydaRoute` du tour de captures : `login`, `register`, `forgot`, `verify`, `reset:<jeton>` ; nil sinon (la
    /// route est alors une route d'écran, `LaunchRoute.parse`).
    static func launchEntry(_ raw: String) -> AuthEntry? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("reset:") {
            let token = String(text.dropFirst("reset:".count)).trimmingCharacters(in: .whitespaces)
            return TextCheck.isBlank(token) ? nil : .resetPassword(token: token)
        }
        switch text.lowercased() {
        case "login": return .login
        case "register": return .register
        case "forgot": return .forgotPassword
        case "verify": return .verifyEmail
        default: return nil
        }
    }
}

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
    /// Feuille de connexion présentée par `RootView` (nil = fermée ; la feuille la remet à nil en se fermant).
    @Published var authFlow: AuthEntry? = nil
    /// Pile de chaque onglet (vide = la racine de l'onglet).
    @Published private(set) var stacks: [AppTab: [AppRoute]] = [:]

    /// `launchRoute` : `-WeydaRoute` (tour de captures), appliqué avant le premier écran. Une route de connexion
    /// (`login`, `register`, `forgot`, `verify`, `reset:<jeton>`) ouvre la feuille au-dessus de l'onglet Profil.
    init(initialTab: AppTab = LaunchOptions.initialTab ?? .home, launchRoute: String? = LaunchOptions.route) {
        selectedTab = initialTab
        guard let launchRoute else { return }
        if let entry = AuthEntry.launchEntry(launchRoute) {
            selectedTab = .account
            authFlow = entry
        } else if let parsed = LaunchRoute.parse(launchRoute) {
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

    /// Un visiteur touche une action réservée aux membres (favori, contacter, voir le numéro, signaler), ou « Se
    /// connecter » : la feuille de connexion s'ouvre par-dessus l'écran courant, qui reste en place dessous — une
    /// fois connecté, la feuille se ferme et l'action se refait d'un appui (Android : `openLogin`, puis retour à
    /// l'écran d'origine).
    func requestLogin() {
        presentedWebPage = nil
        authFlow = .login
    }

    /// « Vérifier » (bandeau e-mail non vérifié du Profil, du dépôt…) : la feuille, directement à l'étape du code.
    func requestEmailVerification() {
        presentedWebPage = nil
        authFlow = .verifyEmail
    }

    // MARK: - Liens profonds

    /// Lien du site ou du schéma `weydaa://` (DeepLinks) : l'écran visé est empilé sur l'onglet courant (rien n'est
    /// perdu), les onglets sont sélectionnés — portage de `NavHostController.open` (WeydaRoot.kt). Le lien « nouveau
    /// mot de passe » ouvre la feuille de connexion à cette étape ; tout autre lien ferme une feuille ouverte (l'écran
    /// visé doit être visible).
    func open(_ target: DeepLinkTarget) {
        presentedWebPage = nil
        if case .resetPassword(let token) = target {
            authFlow = .resetPassword(token: token)
            return
        }
        authFlow = nil
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
            break  // traité plus haut (feuille de connexion)
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
