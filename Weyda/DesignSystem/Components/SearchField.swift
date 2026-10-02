import SwiftUI

/// Barre de recherche — portage de `WeydaSearchField` (SearchField.kt). Capsule pleine posée sur le fond : elle
/// se lit comme un bouton, pas comme un formulaire. La loupe passe au vert dès la saisie et la croix d'effacement
/// apparaît en fondu. Clavier : touche « Rechercher », sans correction automatique (noms de modèles, marques).
/// Focus : `.focused($isFocused)` posé sur ce composant (le champ en est le seul élément focalisable).
struct WeydaSearchField: View {
    @Binding private var text: String
    private let placeholder: String
    private let onSubmit: () -> Void

    init(text: Binding<String>, placeholder: String, onSubmit: @escaping () -> Void) {
        _text = text
        self.placeholder = placeholder
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(text.isEmpty ? WeydaColor.onSurfaceVariant : WeydaColor.primary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .weydaText(.bodyLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .tint(WeydaColor.primary)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.searchClear)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .padding(.leading, WeydaSpace.lg)
        .padding(.trailing, text.isEmpty ? WeydaSpace.lg : WeydaSpace.xxs)
        .frame(minHeight: SearchCapsule.height)
        .background(WeydaColor.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(WeydaColor.outlineVariant, lineWidth: 1)
        }
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: text.isEmpty)
    }
}

/// Faux champ de recherche de l'accueil : même capsule que `WeydaSearchField`, mais un bouton (il ouvre la
/// recherche de l'onglet Annonces).
struct SearchEntryButton: View {
    private let placeholder: String
    private let action: () -> Void

    init(placeholder: String, action: @escaping () -> Void) {
        self.placeholder = placeholder
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                Text(placeholder)
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WeydaSpace.lg)
            .frame(minHeight: SearchCapsule.height)
            .background(WeydaColor.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(WeydaColor.outlineVariant, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(WeydaPressStyle(pressedScale: 0.98))
        .accessibilityLabel(placeholder)
    }
}

/// Hauteur de la capsule de recherche : 48 pt, un peu plus que la cible minimale (premier élément de l'écran).
private enum SearchCapsule {
    static let height: CGFloat = WeydaSize.touchTarget + WeydaSpace.xs
}
