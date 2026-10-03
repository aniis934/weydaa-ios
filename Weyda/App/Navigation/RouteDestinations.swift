import SwiftUI

/// L'écran de chaque route — les points d'entrée fixés par le contrat de la phase 2. Les routes des phases
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
        case .chat, .myListings, .favorites, .savedSearches, .notifications, .editProfile, .changePassword,
             .accountData, .contact, .editListing:
            ComingSoonView(route: route)
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
