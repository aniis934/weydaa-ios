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

/// Feuille de messagerie ouverte depuis la fiche (une seule à la fois).
nonisolated enum DetailMessagingSheet: String, Identifiable, Sendable {
    case contact
    case offer

    var id: String { rawValue }
}

/// Possède le ViewModel (`@StateObject`, créé une fois) et traduit les actions de l'écran : connexion demandée au
/// visiteur (`router.requestLogin()`), navigation, appel, feuilles « Contacter » et « Faire une offre » puis ouverture
/// du fil (`.chat`).
private struct DetailHost: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var model: DetailViewModel
    /// Feuille du tour de captures déjà ouverte (Debug) : une seule fois.
    @State private var tourSheetShown: Bool = false
    private let connectivity: ConnectivityMonitor

    init(model: @autoclosure @escaping () -> DetailViewModel, connectivity: ConnectivityMonitor) {
        _model = StateObject(wrappedValue: model())
        self.connectivity = connectivity
    }

    var body: some View {
        DetailScreen(state: model.state, isReportPresented: $model.isReportPresented, actions: actions)
            // La fiche porte sa propre barre d'actions (offre, numéro, contact) : la barre d'onglets s'efface,
            // comme sur Android et chez Leboncoin, sinon trois rangées de boutons s'empilent en bas d'écran.
            .toolbar(.hidden, for: .tabBar)
            .task {
                await model.loadIfNeeded()
                #if DEBUG
                openSheetForTour()
                #endif
            }
            .onReceive(connectivity.$isOnline.dropFirst()) { online in
                retryIfBackOnline(online)
            }
            // Le fil s'ouvre une fois la feuille refermée (pousser un écran sous une feuille qui se ferme saccade).
            .sheet(
                item: messagingSheetBinding,
                onDismiss: {
                    openPendingConversation()
                },
                content: { sheet in
                    messagingSheet(sheet)
                }
            )
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
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                model.openContact()
            },
            makeOffer: {
                guard model.state.isLoggedIn else {
                    router.requestLogin()
                    return
                }
                model.openOfferDialog()
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

    /// Retour du réseau alors que la fiche est en erreur : nouvel essai, sans attendre « Réessayer ».
    private func retryIfBackOnline(_ online: Bool) {
        guard online, model.state.isError, !model.state.isNotFound else { return }
        Task { await model.load() }
    }

    // MARK: - Contacter / faire une offre

    /// Feuille ouverte d'après l'état ; un glissement vers le bas la ferme (sauf saisie commencée ou envoi en cours).
    private var messagingSheetBinding: Binding<DetailMessagingSheet?> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { DetailHost.sheetKind(for: model.state) } },
            set: { value in
                MainActor.assumeIsolated {
                    guard value == nil else { return }
                    model.dismissMessaging()
                }
            }
        )
    }

    private static func sheetKind(for state: DetailState) -> DetailMessagingSheet? {
        if state.contactMessage != nil { return .contact }
        if state.offerDialog != nil { return .offer }
        return nil
    }

    @ViewBuilder
    private func messagingSheet(_ sheet: DetailMessagingSheet) -> some View {
        switch sheet {
        case .contact:
            ContactSellerSheet(
                listingTitle: model.state.listing?.title ?? "",
                message: contactMessageBinding,
                isBusy: model.state.isContacting,
                errorMessage: model.state.contactError,
                onSend: {
                    _ = model.sendFirstMessage()
                },
                onCancel: {
                    model.dismissContact()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.contact.sheet")
        case .offer:
            OfferAmountSheet(
                title: L10n.offerMake,
                askingPrice: model.state.offerDialog?.askingPrice,
                currentOffer: nil,
                amount: offerAmountBinding,
                isBusy: model.state.isOfferBusy,
                errorMessage: model.state.offerError,
                onConfirm: {
                    _ = model.confirmOffer()
                },
                onCancel: {
                    model.dismissOfferDialog()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.offer.sheet")
        }
    }

    /// Lue et écrite sur le fil principal (comme les liaisons d'`AppRouter`).
    private var contactMessageBinding: Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.contactMessage ?? "" } },
            set: { value in MainActor.assumeIsolated { model.updateContactMessage(value) } }
        )
    }

    private var offerAmountBinding: Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.offerDialog?.amount ?? "" } },
            set: { value in MainActor.assumeIsolated { model.updateOfferAmount(value) } }
        )
    }

    /// Message envoyé ou offre faite (ou déjà ouverte : 409 avec l'id du fil) : le fil s'ouvre sur l'onglet courant.
    private func openPendingConversation() {
        guard let id = model.state.openConversationId else { return }
        model.conversationOpened()
        router.push(.chat(conversationId: id, archived: false))
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
