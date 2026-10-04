import SwiftUI

/// L'écran de chaque route — les points d'entrée fixés par les contrats des phases 2 et 3. Les routes des phases
/// suivantes ouvrent un écran d'attente. Pas de `default` : une route ajoutée sans écran ne compile pas.
struct RouteDestination: View {
    private let route: AppRoute

    init(route: AppRoute) {
        self.route = route
    }

    var body: some View {
        switch route {
        case .detail(let idOrSlug):
            DetailView(idOrSlug: idOrSlug)
        case .seller(let id):
            SellerView(id: id)
        case .webPage(let page):
            WebPageView(page: page)
        case .about:
            AboutView()
        // Compte (phase 3) : les écrans de membre se gardent eux-mêmes (`AccountMemberGate`) ; « Nous contacter »
        // est ouvert aux visiteurs.
        case .myListings:
            MyListingsView()
        case .editProfile:
            EditProfileView()
        case .changePassword:
            ChangePasswordView()
        case .accountData:
            AccountDataView()
        case .contact:
            ContactView()
        // Dépôt (phase 4) : modifier une annonce = l'assistant, ouvert sur le récapitulatif (écran de membre).
        case .editListing(let id):
            PostListingView(editingId: id)
        // Messagerie et notifications (phase 5) : chaque écran se garde lui-même (membre connecté).
        case .chat(let conversationId, let archived):
            ChatView(conversationId: conversationId, archived: archived)
        case .notifications:
            NotificationsView()
        case .blockedUsers:
            BlockedUsersView()
        // Favoris et alertes (phase 6) : écrans de membre, gardés par eux-mêmes.
        case .favorites:
            FavoritesView()
        case .savedSearches:
            SavedSearchesView()
        }
    }
}

extension View {
    /// Branche les écrans de `AppRoute` sur la `NavigationStack` qui contient cette vue (une fois, à sa racine).
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            RouteDestination(route: route)
        }
    }
}
