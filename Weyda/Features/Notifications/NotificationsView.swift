import Combine
import SwiftUI

/// Notifications (écran poussé, interface fixée de la phase 5 : cloche de l'accueil, menu du Profil) — portage de
/// `NotificationsRoute` (NotificationsScreen.kt). Écran de membre (`AccountMemberGate` : un visiteur voit
/// l'invitation à se connecter, l'écran se retire si la session se ferme).
struct NotificationsView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.notificationsTitle) { _ in
            NotificationsHost(
                model: NotificationsViewModel(
                    notifications: container.notifications,
                    online: container.connectivity.$isOnline.eraseToAnyPublisher()
                )
            )
        }
    }
}

/// Possède le ViewModel ; une notification touchée est marquée lue puis ouvre sa cible (fiche, fil, profil,
/// Mes annonces) sur la pile courante. Relit la liste en silence au retour sur l'écran ; en le quittant, envoie la
/// suppression encore annulable (jamais perdue).
private struct NotificationsHost: View {
    @StateObject private var model: NotificationsViewModel
    @EnvironmentObject private var router: AppRouter

    init(model: @autoclosure @escaping () -> NotificationsViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        NotificationsScreen(state: model.state, actions: actions)
            // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
            .refreshable { @MainActor [model] in
                await model.pullToRefresh()
            }
            .onAppear {
                _ = model.appear()
            }
            .onDisappear {
                _ = model.disappear()
            }
    }

    private var actions: NotificationsActions {
        let model = self.model
        let router = self.router
        return NotificationsActions(
            onOpen: { (notification: AppNotification) in
                _ = model.open(notification)
                if let target = notification.target {
                    router.push(NotificationsNavigation.route(for: target))
                }
            },
            onDelete: { (notification: AppNotification) in
                _ = model.delete(notification)
            },
            onMarkAllRead: {
                _ = model.markAllRead()
            },
            onRetry: {
                _ = model.load()
            },
            onLoadMore: {
                _ = model.loadMore()
            },
            onBannerAction: { (action: BannerAction) in
                model.bannerAction(action)
            },
            onBannerDismissed: {
                _ = model.bannerDismissed()
            }
        )
    }
}
