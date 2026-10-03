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
/// le blocage (`router.requestLogin()`).
private struct SellerHost: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: SellerViewModel
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
            actions: actions
        )
        .task {
            await model.loadIfNeeded()
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
            }
        )
    }
}
