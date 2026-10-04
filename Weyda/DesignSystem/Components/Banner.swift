import SwiftUI
import UIKit

/// Bannière brève posée en bas de l'écran — l'équivalent iOS du Snackbar d'Android : un message, un pictogramme
/// facultatif et, au besoin, une action (« Annuler »). Valeur pure : elle vit dans l'état des écrans.
///
/// `id` : deux bannières au même texte restent distinctes (le minuteur repart) ; créer la valeur UNE fois, dans le
/// ViewModel, jamais dans un `body`.
nonisolated struct WeydaBanner: Hashable, Sendable, Identifiable {
    /// Nature du message : pilote l'haptique à l'apparition (`success` / `error`) et la couleur du pictogramme.
    /// Une bannière `success` vibre d'elle-même : ne pas appeler `Haptics.success()` en plus.
    nonisolated enum Kind: Hashable, Sendable {
        case info
        case success
        case error
    }

    let id: UUID
    let message: String
    /// SF Symbol facultatif, en tête du message.
    let symbol: String?
    let kind: Kind
    /// Action proposée (« Annuler ») : un identifiant, rendu à l'écran par `onAction`.
    let action: BannerAction?

    init(_ message: String, symbol: String? = nil, kind: Kind = .info, action: BannerAction? = nil, id: UUID = UUID()) {
        self.id = id
        self.message = message
        self.symbol = symbol
        self.kind = kind
        self.action = action
    }

    /// Délai avant la fermeture automatique : 4 s, ~7 s quand une action est proposée (le temps de lire et d'appuyer).
    var duration: UInt64 {
        action == nil ? 4_000_000_000 : 7_000_000_000
    }

    /// Identifiant fixe des bannières venues de `floatingNotice` : le même texte ne relance pas le minuteur (règle
    /// d'avant la phase 8).
    static let legacyId = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
}

/// Action d'une bannière : `id` dit à l'écran QUOI annuler (`"favorite:<id>"`, `"alert:<id>"`…), `title` est le libellé.
nonisolated struct BannerAction: Hashable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    /// « Annuler » (`L10n.undo`).
    static func undo(_ id: String) -> BannerAction {
        BannerAction(id: id, title: L10n.undo)
    }
}

extension View {
    /// Bannière en bas de l'écran (au-dessus d'une barre d'actions ajoutée APRÈS ce modificateur) : lue par VoiceOver,
    /// fermée seule (4 s, ~7 s avec action — jamais une bannière à action quand VoiceOver tourne), glissée vers le bas
    /// pour la fermer. `onAction` reçoit l'action touchée (la bannière se ferme ensuite d'elle-même : `onDismiss`).
    func weydaBanner(
        _ banner: WeydaBanner?,
        onAction: @escaping (BannerAction) -> Void,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(WeydaBannerModifier(banner: banner, onAction: onAction, onDismiss: onDismiss))
    }

    /// Message bref d'avant la phase 8, sans action : une bannière `.info`. Les écrans migrent vers `weydaBanner` un
    /// par un ; `onShown` le retire de l'état.
    func floatingNotice(_ text: String?, onShown: @escaping () -> Void) -> some View {
        weydaBanner(
            text.map { WeydaBanner($0, id: WeydaBanner.legacyId) },
            onAction: { _ in },
            onDismiss: onShown
        )
    }
}

private struct WeydaBannerModifier: ViewModifier {
    let banner: WeydaBanner?
    let onAction: (BannerAction) -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let banner {
                    WeydaBannerView(banner: banner, onAction: onAction, onDismiss: onDismiss)
                        .padding(.bottom, WeydaSpace.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .weydaAnimation(.easeOut(duration: WeydaDuration.medium), value: banner)
            .task(id: banner) {
                guard let banner else { return }
                await present(banner)
            }
    }

    /// Annonce VoiceOver, haptique selon la nature, puis fermeture au bout du délai. Une nouvelle bannière (autre `id`)
    /// annule ce minuteur et relance le sien.
    private func present(_ banner: WeydaBanner) async {
        UIAccessibility.post(notification: .announcement, argument: banner.message)
        switch banner.kind {
        case .success:
            Haptics.success()
        case .error:
            Haptics.error()
        case .info:
            break
        }
        // VoiceOver : une bannière à action reste jusqu'à l'action ou au glissement (le temps d'y arriver).
        if banner.action != nil && UIAccessibility.isVoiceOverRunning {
            return
        }
        try? await Task.sleep(nanoseconds: banner.duration)
        if !Task.isCancelled {
            onDismiss()
        }
    }
}

/// La bannière : verre (iOS 26) ou matériau, message et action côte à côte — l'un sous l'autre aux tailles
/// d'accessibilité.
private struct WeydaBannerView: View {
    private let banner: WeydaBanner
    private let onAction: (BannerAction) -> Void
    private let onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var dragOffset: CGFloat = 0

    init(banner: WeydaBanner, onAction: @escaping (BannerAction) -> Void, onDismiss: @escaping () -> Void) {
        self.banner = banner
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    var body: some View {
        bannerBody
            .padding(.horizontal, WeydaSpace.screen)
            .offset(y: max(dragOffset, 0))
            .gesture(dismissDrag)
    }

    /// Glisser vers le bas ferme la bannière (au-delà de 24 pt) ; vers le haut, rien.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: WeydaSpace.sm)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > WeydaSpace.xxl {
                    onDismiss()
                }
            }
    }

    @ViewBuilder
    private var bannerBody: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(Glass.regular, in: BannerMetrics.shape)
        } else {
            content
                .background(.regularMaterial, in: BannerMetrics.shape)
                .overlay {
                    BannerMetrics.shape.strokeBorder(WeydaColor.outlineVariant.opacity(0.6), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        }
    }

    private var content: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: WeydaSpace.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: WeydaSpace.md))
        return layout {
            label
            if let action = banner.action {
                actionButton(action)
            }
        }
        .padding(.leading, WeydaSpace.lg)
        .padding(.trailing, banner.action == nil ? WeydaSpace.lg : WeydaSpace.sm)
        .padding(.vertical, WeydaSpace.sm)
        .frame(maxWidth: .infinity, minHeight: WeydaSize.touchTarget + WeydaSpace.xs, alignment: .leading)
        .contentShape(BannerMetrics.shape)
        // Message et bouton restent deux éléments (le bouton se touche aussi avec VoiceOver et dans les tests) ;
        // « notice » = le conteneur, cherché par les tours de captures.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notice")
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
            if let symbol = banner.symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(symbolColor)
                    .accessibilityHidden(true)
            }
            Text(banner.message)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .modifier(BannerAccessibilityAction(action: banner.action, onAction: onAction))
    }

    private func actionButton(_ action: BannerAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Text(action.title)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.primary)
                .lineLimit(1)
                .padding(.horizontal, WeydaSpace.md)
                .frame(minHeight: WeydaSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notice.action")
    }

    private var symbolColor: Color {
        switch banner.kind {
        case .success: WeydaColor.primary
        case .error: WeydaColor.error
        case .info: WeydaColor.onSurfaceVariant
        }
    }
}

/// « Annuler » proposé au rotor de VoiceOver sur le message lui-même (le bouton reste aussi atteignable).
private struct BannerAccessibilityAction: ViewModifier {
    let action: BannerAction?
    let onAction: (BannerAction) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text(action.title)) {
                onAction(action)
            }
        } else {
            content
        }
    }
}

private nonisolated enum BannerMetrics {
    /// Presque une capsule sur une ligne (hauteur ≈ 48 pt), sans rogner un message sur deux lignes.
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WeydaRadius.panel + WeydaSpace.xs, style: .continuous)
    }
}
