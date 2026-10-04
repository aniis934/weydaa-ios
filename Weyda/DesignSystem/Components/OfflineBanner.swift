import SwiftUI
import UIKit

extension View {
    /// Bandeau « hors ligne » AU-DESSUS du contenu (pile verticale, jamais dans `.safeAreaInset(edge: .top)` : sur iOS 26 il
    /// passerait sous l'effet de bord de la barre). Remplace `.safeAreaInset(edge: .top, spacing: 0) { OfflineBanner() }`
    /// dans chaque écran. En ligne : le contenu seul, comme avant ; à la coupure, le bandeau glisse en place et le contenu
    /// descend avec lui (`weydaAnimation` : rien ne bouge sous « Réduire les animations ») ; VoiceOver l'annonce.
    func weydaOfflineBanner() -> some View {
        modifier(OfflineBannerStackModifier())
    }
}

/// Bandeau « Pas de connexion internet » — celui de `WeydaRoot.kt` (Android). Lit `container.connectivity` ;
/// invisible (hauteur nulle) en ligne, il glisse en place à la coupure et VoiceOver l'annonce. Forme « brique » pour un
/// écran qui a déjà sa pile : `VStack(spacing: 0) { OfflineBanner(); … }` ; sinon `.weydaOfflineBanner()`.
struct OfflineBanner: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        OfflineBannerHost(connectivity: container.connectivity)
    }
}

/// Observe le moniteur lui-même : `AppContainer` ne republie pas les changements de ses dépendances.
private struct OfflineBannerHost: View {
    @ObservedObject private var connectivity: ConnectivityMonitor

    init(connectivity: ConnectivityMonitor) {
        self.connectivity = connectivity
    }

    var body: some View {
        OfflineBannerSlot(isOnline: connectivity.isOnline)
            .weydaAnimation(.easeInOut(duration: WeydaDuration.medium), value: connectivity.isOnline)
            .modifier(OfflineAnnouncement(isOnline: connectivity.isOnline))
    }
}

// MARK: - Pile « bandeau + contenu »

private struct OfflineBannerStackModifier: ViewModifier {
    @EnvironmentObject private var container: AppContainer

    init() {}

    func body(content: Content) -> some View {
        OfflineBannerStack(connectivity: container.connectivity, content: content)
    }
}

/// Le bandeau puis le contenu, l'un sous l'autre : le bandeau reste SOUS la barre de navigation (le contenu ne passe
/// plus dessous tant qu'il est affiché). L'animation porte sur toute la pile : le contenu descend en même temps.
private struct OfflineBannerStack<Wrapped: View>: View {
    @ObservedObject private var connectivity: ConnectivityMonitor
    private let content: Wrapped

    init(connectivity: ConnectivityMonitor, content: Wrapped) {
        self.connectivity = connectivity
        self.content = content
    }

    var body: some View {
        let isOnline: Bool = connectivity.isOnline
        VStack(spacing: 0) {
            OfflineBannerSlot(isOnline: isOnline)
                .background(alignment: .top) {
                    OfflineBarBackdrop(isVisible: !isOnline)
                }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .weydaAnimation(.easeInOut(duration: WeydaDuration.medium), value: isOnline)
        .modifier(OfflineAnnouncement(isOnline: isOnline))
    }
}

/// Hors ligne, le contenu ne touche plus le haut de l'écran : son fond ne remonte plus sous la barre. Ce fond-ci prend
/// le relais (fond de l'écran, jusqu'à la barre d'état). En ligne : rien, le fond du contenu remonte comme avant.
private struct OfflineBarBackdrop: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            WeydaColor.background
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Briques communes

/// Emplacement du bandeau : hauteur nulle en ligne. Rogné : le fond du bandeau ne déborde pas sous la barre, et il
/// glisse depuis le bord haut de son emplacement.
private struct OfflineBannerSlot: View {
    let isOnline: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !isOnline {
                OfflineBannerLabel()
                    .accessibilityIdentifier("offline.banner")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// Annonce VoiceOver de la coupure, seulement depuis l'écran affiché (les onglets en arrière-plan gardent leurs vues).
private struct OfflineAnnouncement: ViewModifier {
    private let isOnline: Bool
    @State private var visible: Bool = false

    init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onChange(of: isOnline) { online in
                if !online && visible {
                    UIAccessibility.post(notification: .announcement, argument: L10n.offlineBanner)
                }
            }
    }
}

/// Le bandeau lui-même (aussi montré tel quel dans la démonstration des composants).
struct OfflineBannerLabel: View {
    init() {}

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            Image(systemName: "wifi.slash")
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            Text(L10n.offlineBanner)
                .weydaText(.labelLarge)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(WeydaColor.onErrorContainer)
        .padding(.vertical, WeydaSpace.sm)
        .padding(.horizontal, WeydaSpace.screen)
        .frame(maxWidth: .infinity)
        .background(WeydaColor.errorContainer)
        .accessibilityElement(children: .combine)
    }
}
