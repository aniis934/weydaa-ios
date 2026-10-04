import Combine
import SwiftUI

/// Profil public d'un vendeur (`AppRoute.seller`) — point d'entrée fixé par le contrat de la phase 2.
struct SellerView: View {
    @EnvironmentObject private var container: AppContainer
    private let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        SellerHost(
            model: SellerViewModel(
                id: id,
                sellers: container.sellers,
                favorites: container.favorites,
                reviews: container.reviews,
                reports: container.reports,
                conversations: container.conversations,
                sessionUser: container.sessionManager.$user.eraseToAnyPublisher()
            ),
            connectivity: container.connectivity
        )
    }
}

/// Possède le ViewModel et traduit les actions : connexion demandée au visiteur pour le favori, le signalement et
/// le blocage (`router.requestLogin()`) ; feuille « Laisser un avis » (membre seulement).
private struct SellerHost: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: SellerViewModel
    /// Feuille d'avis du tour de captures déjà ouverte (Debug) : une seule fois.
    @State private var reviewDemoShown: Bool = false
    private let connectivity: ConnectivityMonitor

    init(model: @autoclosure @escaping () -> SellerViewModel, connectivity: ConnectivityMonitor) {
        _model = StateObject(wrappedValue: model())
        self.connectivity = connectivity
    }

    var body: some View {
        SellerScreen(
            state: model.state,
            isReportPresented: $model.isReportPresented,
            isBlockConfirmPresented: $model.isBlockConfirmPresented,
            isReviewPresented: $model.isReviewPresented,
            reviewRating: $model.reviewRating,
            reviewComment: $model.reviewComment,
            actions: actions
        )
        .task {
            await model.loadIfNeeded()
            #if DEBUG
            await showReviewDemoIfRequested()
            #endif
        }
        .onReceive(connectivity.$isOnline.dropFirst()) { online in
            // Retour du réseau alors que le profil est en erreur : nouvel essai, sans attendre « Réessayer ».
            guard online, model.state.errorMessage != nil else { return }
            Task { await model.load() }
        }
    }

    private var actions: SellerActions {
        let model = self.model
        let router = self.router
        return SellerActions(
            retry: {
                Task { await model.load() }
            },
            refresh: {
                await model.refresh()
            },
            loadMore: {
                Task { await model.loadMore() }
            },
            toggleFavorite: { listing in
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                Task { await model.toggleFavorite(listing) }
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
            requestBlock: {
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                model.requestBlock()
            },
            block: {
                Task { await model.setBlocked(true) }
            },
            unblock: {
                Task { await model.setBlocked(false) }
            },
            noticeShown: {
                model.noticeShown()
            },
            openReview: {
                // Le bouton n'est montré qu'à un membre éligible ; garde par prudence, comme Android.
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                Task { await model.openReview() }
            },
            submitReview: {
                Task { await model.confirmReview() }
            },
            cancelReview: {
                model.dismissReview()
            }
        )
    }

    #if DEBUG
    /// Tour de captures (Debug, API simulée) : `-WeydaReviewDemo open` (ou `filled`) ouvre la feuille d'avis une fois
    /// le profil et le droit de noter chargés — la note et le commentaire se rempliraient sinon au clavier.
    private func showReviewDemoIfRequested() async {
        guard !reviewDemoShown, LaunchOptions.mockAPI, let demo = LaunchOptions.reviewDemo else { return }
        reviewDemoShown = true
        await model.showReviewDemo(demo)
    }
    #endif
}
