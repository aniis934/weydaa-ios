import Combine
import SwiftUI

/// Racine de l'onglet Messages (interface fixée de la phase 5) — portage de `ConversationsRoute`
/// (ConversationsScreen.kt) et de la garde de WeydaRoot.kt : un visiteur voit l'invitation à se connecter ; un
/// membre, ses conversations, recréées pour un autre compte (`.id`) — rien ne passe d'un utilisateur au suivant.
struct ConversationsView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var router: AppRouter

    init() {}

    var body: some View {
        if let user = session.user {
            ConversationsHost(
                model: ConversationsViewModel(
                    conversations: container.conversations,
                    session: session.$user.eraseToAnyPublisher(),
                    online: container.connectivity.$isOnline.eraseToAnyPublisher()
                ),
                push: container.push
            )
            .id(user.id)
        } else {
            LoginRequired(
                title: L10n.loginRequiredTitle,
                message: L10n.loginRequiredBody,
                onLogin: { router.requestLogin() }
            )
            .navigationTitle(L10n.navMessages)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.conversationsGuest")
        }
    }
}

/// Possède le ViewModel et le texte de la recherche locale ; branche les actions sur le ViewModel et le routeur.
/// Relit la liste en silence à chaque retour sur l'écran (un fil ouvert depuis la liste a changé l'ordre et les
/// accusés de lecture) et demande, au bon moment, l'autorisation d'envoyer des notifications.
private struct ConversationsHost: View {
    @StateObject private var model: ConversationsViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var query: String = ""
    private let push: PushRegistrar

    init(model: @autoclosure @escaping () -> ConversationsViewModel, push: PushRegistrar) {
        _model = StateObject(wrappedValue: model())
        self.push = push
    }

    var body: some View {
        ConversationsScreen(
            state: model.state,
            query: $query,
            archived: archivedBinding,
            actions: actions
        )
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor [model] in
            await model.pullToRefresh()
        }
        .onAppear {
            _ = model.appear()
            // Ouverture de Messages par un membre : le moment où la demande d'autorisation des notifications a un
            // sens (PushRegistrar ne la fait qu'une fois, refus respecté ; rien sans Firebase — captures, CI).
            push.requestAuthorizationIfNeeded()
        }
    }

    private var actions: ConversationsActions {
        let model = self.model
        let router = self.router
        return ConversationsActions(
            onOpen: { (conversation: Conversation) in
                router.push(.chat(conversationId: conversation.id, archived: model.state.archived))
            },
            onToggleArchive: { (conversation: Conversation) in
                _ = model.toggleArchive(conversation)
            },
            onRetry: {
                _ = model.load()
            },
            onLoadMore: {
                _ = model.loadMore()
            },
            onNoticeShown: {
                model.noticeShown()
            }
        )
    }

    /// Segment Conversations / Archives, lu dans l'état et écrit par le ViewModel (qui recharge la liste).
    private var archivedBinding: Binding<Bool> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.archived } },
            set: { archived in
                MainActor.assumeIsolated {
                    _ = model.setArchived(archived)
                }
            }
        )
    }
}
