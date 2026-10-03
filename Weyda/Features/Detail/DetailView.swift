import Combine
import SwiftUI

/// Fiche d'une annonce (`AppRoute.detail`) — point d'entrée fixé par le contrat de la phase 2. Crée le ViewModel
/// avec les repositories du conteneur ; `DetailHost` le garde en vie et branche les actions.
struct DetailView: View {
    @EnvironmentObject private var container: AppContainer
    private let idOrSlug: String

    init(idOrSlug: String) {
        self.idOrSlug = idOrSlug
    }

    var body: some View {
        DetailHost(
            model: DetailViewModel(
                idOrSlug: idOrSlug,
                annonces: container.annonces,
                favorites: container.favorites,
                reviews: container.reviews,
                attributes: container.attributes,
                conversations: container.conversations,
                reports: container.reports,
                sessionUser: container.sessionManager.$user.eraseToAnyPublisher()
            ),
            connectivity: container.connectivity
        )
    }
}

/// Contact provisoire (avant la messagerie de la phase 5) : la page de l'annonce sur le site, où la conversation
/// et l'offre existent déjà.
nonisolated struct DetailWebFallback: Equatable, Sendable {
    let title: String
    let url: URL
}

/// Possède le ViewModel (`@StateObject`, créé une fois) et traduit les actions de l'écran : connexion demandée au
/// visiteur (`router.requestLogin()`), navigation, appel, contact provisoire.
private struct DetailHost: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model: DetailViewModel
    @State private var webFallback: DetailWebFallback? = nil
    @State private var isWebFallbackPresented: Bool = false
    /// Feuille du tour de captures déjà ouverte (Debug) : une seule fois.
    @State private var tourSheetShown: Bool = false
    private let connectivity: ConnectivityMonitor

    init(model: @autoclosure @escaping () -> DetailViewModel, connectivity: ConnectivityMonitor) {
        _model = StateObject(wrappedValue: model())
        self.connectivity = connectivity
    }

    var body: some View {
        DetailScreen(state: model.state, isReportPresented: $model.isReportPresented, actions: actions)
            .task {
                await model.loadIfNeeded()
                #if DEBUG
                openSheetForTour()
                #endif
            }
            .onReceive(connectivity.$isOnline.dropFirst()) { online in
                retryIfBackOnline(online)
            }
            .alert(
                webFallback?.title ?? "",
                isPresented: $isWebFallbackPresented,
                presenting: webFallback
            ) { fallback in
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.authContinue) {
                    openURL(fallback.url)
                }
            } message: { _ in
                Text(L10n.legalOpensBrowser)
            }
    }

    private var actions: DetailActions {
        let model = self.model
        let router = self.router
        let dismiss = self.dismiss
        let openURL = self.openURL
        return DetailActions(
            retry: {
                Task { await model.load() }
            },
            refresh: {
                await model.refresh()
            },
            back: {
                dismiss()
            },
            toggleFavorite: {
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                Task { await model.toggleFavorite() }
            },
            report: {
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                model.openReport()
            },
            submitReport: { reason, details in
                Task { await model.confirmReport(reason: reason, details: details) }
            },
            openSeller: { sellerId in
                router.push(.seller(id: sellerId))
            },
            edit: {
                guard let id = model.state.listing?.id else { return }
                router.push(.editListing(id: id))
            },
            contact: {
                openWebFallback(title: L10n.detailContact)
            },
            makeOffer: {
                openWebFallback(title: L10n.offerMake)
            },
            phone: {
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                if let phone = model.state.revealedPhone {
                    // Numéro déjà révélé : le toucher appelle (l'app est sur iPhone : il y a toujours un composeur).
                    if let url = DetailLinks.callURL(for: phone) {
                        openURL(url)
                    }
                } else {
                    Task { await model.revealPhone() }
                }
            },
            noticeShown: {
                model.noticeShown()
            }
        )
    }

    /// « Contacter » / « Faire une offre » : un visiteur va à la connexion. Connecté, la messagerie native n'existe
    /// pas encore (phase 5) : plutôt qu'un faux « message envoyé » ou un bouton mort, on propose — en le disant
    /// (« S'ouvre dans le navigateur ») — la page de l'annonce sur le site, où conversation et offre fonctionnent.
    private func openWebFallback(title: String) {
        guard model.state.isLoggedIn else {
            router.requestLogin()
            return
        }
        guard let listing = model.state.listing, let url = DetailLinks.webURL(for: listing) else { return }
        webFallback = DetailWebFallback(title: title, url: url)
        isWebFallbackPresented = true
    }

    /// Retour du réseau alors que la fiche est en erreur : nouvel essai, sans attendre « Réessayer ».
    private func retryIfBackOnline(_ online: Bool) {
        guard online, model.state.isError, !model.state.isNotFound else { return }
        Task { await model.load() }
    }

    #if DEBUG
    /// Tour de captures (Debug, API simulée) : `-WeydaDetailSheet report` ouvre la feuille « Signaler » une fois
    /// la fiche chargée — elle est réservée aux membres, et l'API simulée n'a pas de session.
    private func openSheetForTour() {
        guard !tourSheetShown,
              LaunchOptions.mockAPI,
              UserDefaults.standard.string(forKey: "WeydaDetailSheet") == "report",
              model.state.canReport else { return }
        tourSheetShown = true
        model.isReportPresented = true
    }
    #endif
}
