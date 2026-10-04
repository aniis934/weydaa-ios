import SwiftUI

// MARK: - Environnement posé par chaque pile d'onglet (`TabStack`, RootView)

/// Clés écrites à la main et `nonisolated` : l'isolation MainActor par défaut du module ne doit pas toucher leur
/// conformance à `EnvironmentKey`.
private nonisolated struct ScrollToTopSignalKey: EnvironmentKey {
    static var defaultValue: Int { 0 }
}

private nonisolated struct ListingZoomNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

extension EnvironmentValues {
    /// Compteur « onglet actif touché alors que sa pile est vide » (`AppRouter.scrollToTopRequests`) : chaque
    /// changement demande à la racine de l'onglet de remonter en haut (`scrollsToTop(on:proxy:to:)`).
    nonisolated var scrollToTopSignal: Int {
        get { self[ScrollToTopSignalKey.self] }
        set { self[ScrollToTopSignalKey.self] = newValue }
    }

    /// Espace de noms de la transition zoom des cartes d'annonce, un par onglet (nil hors d'une pile d'onglet).
    nonisolated var listingZoomNamespace: Namespace.ID? {
        get { self[ListingZoomNamespaceKey.self] }
        set { self[ListingZoomNamespaceKey.self] = newValue }
    }
}

// MARK: - Onglet touché deux fois : retour en haut

extension View {
    /// Remonte la liste en haut (`proxy.scrollTo(id, anchor:)`) à chaque changement de `signal` — à poser DANS le
    /// `ScrollViewReader`, avec `signal` = `@Environment(\.scrollToTopSignal)` de la racine d'onglet et `id` posé sur le
    /// premier élément. Défilement animé, immédiat sous « Réduire les animations ».
    func scrollsToTop<ID: Hashable>(
        on signal: Int,
        proxy: ScrollViewProxy,
        to id: ID,
        anchor: UnitPoint = .top
    ) -> some View {
        modifier(ScrollToTopModifier(signal: signal, proxy: proxy, target: id, anchor: anchor))
    }
}

private struct ScrollToTopModifier<ID: Hashable>: ViewModifier {
    let signal: Int
    let proxy: ScrollViewProxy
    let target: ID
    let anchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: signal) { _ in
                let animation: Animation? = reduceMotion ? nil : WeydaCurve.emphasized.animation(duration: WeydaDuration.long)
                withAnimation(animation) {
                    proxy.scrollTo(target, anchor: anchor)
                }
            }
    }
}

// MARK: - Transition zoom carte → fiche (iOS 18)

extension View {
    /// Source de la transition zoom : la carte touchée (`id` = la clé passée à `AppRoute.detail(…, zoomSource:)`,
    /// unique par rangée : `home.featured.<id>`, `listings.<id>`…). À poser sur le LIBELLÉ du `NavigationLink`. Sans
    /// effet avant iOS 18, hors d'une pile d'onglet, sous « Réduire les animations » et pendant les captures.
    func listingZoomSource(id: String) -> some View {
        modifier(ListingZoomSourceModifier(id: id))
    }

    /// Destination de la transition zoom (posée par `RouteDestination` quand la route porte une source).
    func listingZoomDestination(id: String?) -> some View {
        modifier(ListingZoomDestinationModifier(id: id))
    }
}

/// Faut-il zoomer ? Jamais sous « Réduire les animations » ni avec `-WeydaFreezeMotion` (captures).
private nonisolated enum ListingZoom {
    static func isEnabled(reduceMotion: Bool) -> Bool {
        !reduceMotion && !LaunchOptions.freezeMotion
    }
}

private struct ListingZoomSourceModifier: ViewModifier {
    let id: String
    @Environment(\.listingZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            zoomSource(content)
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    @ViewBuilder
    private func zoomSource(_ content: Content) -> some View {
        if let namespace, ListingZoom.isEnabled(reduceMotion: reduceMotion) {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct ListingZoomDestinationModifier: ViewModifier {
    let id: String?
    @Environment(\.listingZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            zoomDestination(content)
        } else {
            content
        }
    }

    @available(iOS 18.0, *)
    @ViewBuilder
    private func zoomDestination(_ content: Content) -> some View {
        if let id, let namespace, ListingZoom.isEnabled(reduceMotion: reduceMotion) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
