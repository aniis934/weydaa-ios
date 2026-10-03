import SwiftUI

/// Attente de forme inconnue (envoi d'un formulaire, première ouverture d'un écran sans squelette) : le W s'écrit
/// et se résorbe, au centre. Quand la forme du contenu est connue, préférer les squelettes (`Skeletons.swift`) :
/// rien ne saute à l'arrivée des données. Portage de `LoadingState` (StateViews.kt).
struct LoadingState: View {
    init() {}

    var body: some View {
        WeydaLoader()
            .frame(width: WeydaSize.stateIcon, height: WeydaSize.stateIcon)
            .padding(WeydaSpace.xxxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Attente en ligne : bas de liste pendant la pagination.
struct InlineLoader: View {
    init() {}

    var body: some View {
        WeydaLoader()
            .frame(width: WeydaSize.iconLarge, height: WeydaSize.iconLarge)
            .padding(WeydaSpace.lg)
            .frame(maxWidth: .infinity)
    }
}

/// Erreur de chargement : pictogramme sur pastille rouge pâle, « Chargement impossible », le message
/// (`ErrorMapper.message(for:)`), « Réessayer ». Occupe toute la place et se centre.
struct ErrorState: View {
    private let message: String
    private let onRetry: () -> Void

    init(message: String, onRetry: @escaping () -> Void) {
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        MessageState(
            systemImage: "exclamationmark.triangle",
            title: L10n.errorTitle,
            message: message,
            tint: WeydaColor.error,
            container: WeydaColor.errorContainer,
            actionTitle: L10n.retry,
            action: onRetry
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// État vide : un état sans issue est un cul-de-sac — donner une action quand il y en a une d'utile
/// (« Réinitialiser » les filtres, « Voir toutes les annonces »…). Pictogramme : un SF Symbol.
struct EmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        MessageState(
            systemImage: systemImage,
            title: title,
            message: message,
            tint: WeydaColor.onSurfaceVariant,
            container: WeydaColor.surfaceContainer,
            actionTitle: actionTitle,
            action: action
        )
    }
}

/// Gabarit commun des écrans sans contenu (Android : MessageState) : pastille, titre, explication, action.
private struct MessageState: View {
    let systemImage: String
    let title: String
    let message: String?
    let tint: Color
    let container: Color
    let actionTitle: String?
    let action: (() -> Void)?

    /// Pastille de 88 pt et largeur de lecture du message (320 pt), comme Android.
    private static let badgeSide: CGFloat = WeydaSize.stateIcon * 2
    private static let messageWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: WeydaRadius.panel, style: .continuous)
                .fill(container)
                .frame(width: Self.badgeSide, height: Self.badgeSide)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.largeTitle)
                        .foregroundStyle(tint)
                }
                .accessibilityHidden(true)
            Text(title)
                .weydaText(.titleMedium)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.center)
                .padding(.top, WeydaSpace.lg)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Self.messageWidth)
                    .padding(.top, WeydaSpace.sm)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.onPrimary)
                        .padding(.horizontal, WeydaSpace.sm)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(WeydaColor.primary)
                .padding(.top, WeydaSpace.xl)
            }
        }
        .padding(.horizontal, WeydaSpace.xxxl)
        .padding(.vertical, WeydaSpace.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// Titre de section. Il porte la gouttière des écrans (`WeydaSpace.screen`) et la respiration du dessus
/// (`WeydaSpace.section`) : se pose bord à bord, aligné sur les cartes qu'il annonce. Action : bouton texte
/// (« Voir tout »), ou sans libellé un chevron « › » (retourné en arabe), lu « Voir tout » par VoiceOver.
struct SectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    init(title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: WeydaSpace.sm) {
            Text(title)
                .weydaText(.titleLarge)
                .foregroundStyle(WeydaColor.onBackground)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let action {
                if let actionTitle {
                    Button(action: action) {
                        Text(actionTitle)
                            .weydaText(.labelLarge)
                            .foregroundStyle(WeydaColor.primary)
                            .lineLimit(1)
                            .padding(.horizontal, WeydaSpace.sm)
                            .frame(minHeight: WeydaSize.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: action) {
                        Image(systemName: "chevron.forward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(WeydaColor.onSurface)
                            .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.seeAll)
                }
            }
        }
        // Même hauteur avec ou sans action : l'espace au-dessus du titre ne change pas d'une section à l'autre.
        .frame(minHeight: WeydaSize.touchTarget)
        .padding(.leading, WeydaSpace.screen)
        .padding(.trailing, WeydaSpace.xs)
        .padding(.top, WeydaSpace.section - WeydaSpace.sm)
        .padding(.bottom, WeydaSpace.xs)
    }
}
