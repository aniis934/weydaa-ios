import SwiftUI

/// Fil d'une conversation (`AppRoute.chat`) — point d'entrée fixé par le contrat de la phase 5. Écran de membre : un
/// visiteur voit l'invitation à se connecter (`AccountMemberGate` → `router.requestLogin()`), et l'écran se retire si
/// la session se ferme. Le ViewModel est créé une fois par compte, avec les repositories du conteneur.
struct ChatView: View {
    @EnvironmentObject private var container: AppContainer
    private let conversationId: String
    private let archived: Bool

    init(conversationId: String, archived: Bool) {
        self.conversationId = conversationId
        self.archived = archived
    }

    var body: some View {
        AccountMemberGate(title: L10n.navMessages) { user in
            ChatHost(
                model: ChatViewModel(
                    conversationId: conversationId,
                    archived: ChatView.opensArchived(archived),
                    userId: user.id,
                    conversations: container.conversations,
                    notifications: container.notifications,
                    reports: container.reports,
                    realtime: ChatRealtime.live(container.realtime),
                    reviewPrompter: container.reviewPrompter
                ),
                emailVerified: user.emailVerified
            )
        }
    }

    /// Fil ouvert depuis les Archives : menu « Désarchiver ». Tour de captures (Debug, API simulée) :
    /// `-WeydaChatDemo archived` l'impose, la route de lancement `chat:<id>` n'ayant pas ce drapeau.
    private static func opensArchived(_ archived: Bool) -> Bool {
        #if DEBUG
        if LaunchOptions.mockAPI && LaunchOptions.chatDemo == "archived" {
            return true
        }
        #endif
        return archived
    }
}

/// Feuille ouverte par-dessus le fil.
nonisolated enum ChatSheet: String, Identifiable, Sendable {
    case report
    case offer

    var id: String { rawValue }
}

/// Confirmation en attente (une seule feuille d'actions pour l'écran).
nonisolated enum ChatConfirmation: String, Sendable {
    case block
    case delete
}

/// Possède le ViewModel (`@StateObject`, créé une fois) et branche l'écran : navigation, feuilles (offre, signalement),
/// confirmations (bloquer, supprimer : feuilles d'actions iOS, phase 8 ; débloquer reste sans confirmation), bannière
/// (« Annuler » un archivage), demande de note (offre acceptée par le vendeur), apparition / disparition (temps réel,
/// fil « visible » pour les push).
private struct ChatHost: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: ChatViewModel
    private let emailVerified: Bool

    init(model: @autoclosure @escaping () -> ChatViewModel, emailVerified: Bool) {
        _model = StateObject(wrappedValue: model())
        self.emailVerified = emailVerified
    }

    var body: some View {
        ChatScreen(state: model.state, emailVerified: emailVerified, actions: actions)
            // Le fil porte son composeur en bas : la barre d'onglets s'efface (comme la fiche et les messageries).
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                appear()
            }
            .onDisappear {
                model.disappear()
            }
            .sheet(item: sheetBinding) { sheet in
                sheetContent(sheet)
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: confirmationBinding,
                titleVisibility: .visible,
                presenting: confirmation
            ) { item in
                confirmationButtons(item)
            } message: { item in
                Text(ChatHost.confirmationMessage(item))
            }
            // Offre acceptée par le vendeur : demande de note quand c'est le bon moment (`ReviewPrompter`).
            .requestsReview(when: model.asksForReview)
    }

    // MARK: - Actions

    private var actions: ChatActions {
        let model = self.model
        let router = self.router
        return ChatActions(
            retry: {
                _ = model.load()
            },
            loadOlder: {
                _ = model.loadOlder()
            },
            draftChanged: { value in
                model.updateDraft(value)
            },
            send: {
                _ = model.send()
            },
            askDelete: { message in
                model.askDelete(message)
            },
            makeOffer: {
                model.openOfferDialog(.new)
            },
            counterOffer: {
                model.openOfferDialog(.counter)
            },
            respondOffer: { action in
                _ = model.respondToOffer(action)
            },
            openListing: {
                guard let id = model.state.annonceId else { return }
                router.push(.detail(idOrSlug: id))
            },
            openProfile: {
                guard model.state.hasPartnerProfile, let id = model.state.partner?.id else { return }
                router.push(.seller(id: id))
            },
            toggleArchive: {
                _ = model.toggleArchive()
            },
            block: {
                model.askBlock()
            },
            unblock: {
                _ = model.setBlocked(false)
            },
            report: {
                model.openReport()
            },
            bannerAction: { (action: BannerAction) in
                _ = model.bannerAction(action)
            },
            bannerDismissed: {
                model.bannerDismissed()
            }
        )
    }

    private func appear() {
        // Retours haptiques quand l'action aboutit (pas à l'appui) : petit choc pour un message, réussite pour une
        // offre envoyée, une contre-offre ou une acceptation ; rien pour un refus.
        model.onMessageSent = {
            Haptics.impact()
        }
        model.onOfferSent = { action in
            if action != .decline {
                Haptics.success()
            }
        }
        let loading = model.appear()
        #if DEBUG
        showDemoIfRequested(after: loading)
        #else
        _ = loading
        #endif
    }

    #if DEBUG
    /// Tour de captures (Debug, API simulée) : `-WeydaChatDemo typing` montre l'interlocuteur « en ligne » qui écrit,
    /// sans temps réel (inerte en API simulée).
    private func showDemoIfRequested(after loading: Task<Void, Never>?) {
        guard LaunchOptions.mockAPI, LaunchOptions.chatDemo == "typing" else { return }
        let model = self.model
        Task { @MainActor in
            await loading?.value
            model.showTypingDemo()
        }
    }
    #endif

    // MARK: - Feuilles

    private var sheetBinding: Binding<ChatSheet?> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { ChatHost.presentedSheet(for: model) } },
            set: { value in
                MainActor.assumeIsolated {
                    guard value == nil else { return }
                    if model.isReportPresented {
                        model.isReportPresented = false
                    } else {
                        model.dismissOfferDialog()
                    }
                }
            }
        )
    }

    private static func presentedSheet(for model: ChatViewModel) -> ChatSheet? {
        if model.isReportPresented { return .report }
        if model.state.offerDialog != nil { return .offer }
        return nil
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ChatSheet) -> some View {
        switch sheet {
        case .report:
            ReportSheet(
                targetsUser: true,
                isBusy: model.state.isReportBusy,
                errorMessage: model.state.reportError,
                onSubmit: { reason, details in
                    _ = model.confirmReport(reason: reason, details: details)
                },
                onCancel: {
                    model.isReportPresented = false
                }
            )
        case .offer:
            OfferAmountSheet(
                title: offerSheetTitle,
                askingPrice: model.state.offerDialog?.askingPrice,
                currentOffer: model.state.offerDialog?.currentOffer,
                amount: offerAmountBinding,
                isBusy: model.state.isOfferBusy,
                errorMessage: model.state.offerError,
                onConfirm: {
                    _ = model.confirmOfferDialog()
                },
                onCancel: {
                    model.dismissOfferDialog()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.offer.sheet")
        }
    }

    private var offerSheetTitle: String {
        model.state.offerDialog?.action == .counter ? L10n.offerCounterTitle : L10n.offerMake
    }

    /// Lue et écrite sur le fil principal (comme les liaisons d'`AppRouter`).
    private var offerAmountBinding: Binding<String> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.offerDialog?.amount ?? "" } },
            set: { value in MainActor.assumeIsolated { model.updateOfferAmount(value) } }
        )
    }

    // MARK: - Confirmations

    private var confirmation: ChatConfirmation? {
        if model.state.pendingDelete != nil { return .delete }
        if model.state.isBlockConfirmPending { return .block }
        return nil
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .delete: L10n.chatDeleteMessage
        case .block: L10n.chatBlockUser
        case nil: ""
        }
    }

    /// Ouverte tant qu'une confirmation attend. Un appui sur l'un de ses boutons (ou à côté de la feuille) la referme
    /// et SwiftUI repasse la liaison à « faux » — peut-être AVANT d'exécuter l'action du bouton, qui lit encore
    /// l'élément en attente : l'effacement est donc reporté au tour suivant (sans effet si le bouton l'a déjà fait).
    private var confirmationBinding: Binding<Bool> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { ChatHost.hasConfirmation(model) } },
            set: { presented in
                guard !presented else { return }
                Task { @MainActor in
                    model.dismissConfirmations()
                }
            }
        )
    }

    private static func hasConfirmation(_ model: ChatViewModel) -> Bool {
        model.state.pendingDelete != nil || model.state.isBlockConfirmPending
    }

    /// Le bouton destructif (rouge), puis « Annuler » (à part, en bas de la feuille d'actions).
    @ViewBuilder
    private func confirmationButtons(_ item: ChatConfirmation) -> some View {
        switch item {
        case .delete:
            Button(L10n.chatDelete, role: .destructive) {
                _ = model.confirmDelete()
            }
            .accessibilityIdentifier("chat.confirm.delete")
        case .block:
            Button(L10n.chatBlockUser, role: .destructive) {
                _ = model.confirmBlock()
            }
            .accessibilityIdentifier("chat.confirm.block")
        }
        Button(L10n.cancel, role: .cancel) {
            model.dismissConfirmations()
        }
    }

    private static func confirmationMessage(_ item: ChatConfirmation) -> String {
        switch item {
        case .delete: L10n.chatDeleteConfirmBody
        case .block: L10n.chatBlockConfirmBody
        }
    }
}
