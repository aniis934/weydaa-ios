import SwiftUI
import UIKit

/// Bandeau « Pas de connexion internet » — celui de `WeydaRoot.kt` (Android). Lit `container.connectivity` ;
/// invisible (hauteur nulle) en ligne, il glisse en place à la coupure et VoiceOver l'annonce. À poser en haut de
/// l'écran : `.safeAreaInset(edge: .top, spacing: 0) { OfflineBanner() }`.
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
    @State private var visible: Bool = false

    init(connectivity: ConnectivityMonitor) {
        self.connectivity = connectivity
    }

    var body: some View {
        VStack(spacing: 0) {
            if !connectivity.isOnline {
                OfflineBannerLabel()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .weydaAnimation(.easeInOut(duration: WeydaDuration.medium), value: connectivity.isOnline)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: connectivity.isOnline) { online in
            // Annonce seulement depuis l'écran affiché (les onglets en arrière-plan gardent leurs vues).
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
