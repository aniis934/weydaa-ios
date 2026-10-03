import SwiftUI

/// Liste déroulante de la recherche — portage de `SearchBox.kt` (Android) : l'historique local quand le champ est
/// vide, les suggestions du serveur dès 2 caractères (catégorie, wilaya, annonce). Carte flottante posée sur les
/// résultats, sous le champ : la seule ombre de l'écran (elle flotte vraiment au-dessus du contenu).
struct ListingsSearchPanel: View {
    private let query: String
    private let suggestions: [Suggestion]
    private let history: [String]
    private let onSuggestionPick: (Suggestion) -> Void
    private let onHistoryPick: (String) -> Void
    private let onClearHistory: () -> Void

    init(
        query: String,
        suggestions: [Suggestion],
        history: [String],
        onSuggestionPick: @escaping (Suggestion) -> Void,
        onHistoryPick: @escaping (String) -> Void,
        onClearHistory: @escaping () -> Void
    ) {
        self.query = query
        self.suggestions = suggestions
        self.history = history
        self.onSuggestionPick = onSuggestionPick
        self.onHistoryPick = onHistoryPick
        self.onClearHistory = onClearHistory
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        // Courte, la liste prend sa hauteur ; longue (clavier sorti, petit écran), elle défile dans la place libre.
        ViewThatFits(in: .vertical) {
            rows
            ScrollView {
                rows
            }
        }
        .background(WeydaColor.surface, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .shadow(color: PanelShadow.color, radius: PanelShadow.radius, x: 0, y: PanelShadow.offset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listings.suggestions")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if TextCheck.isBlank(query) {
                historyHeader
                ForEach(history, id: \.self) { text in
                    historyRow(text)
                }
            } else {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { entry in
                    suggestionRow(entry.element)
                }
            }
        }
        .padding(.vertical, WeydaSpace.xs)
    }

    private var historyHeader: some View {
        HStack(spacing: WeydaSpace.sm) {
            Text(L10n.searchHistory)
                .weydaText(.labelMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: WeydaSpace.sm)
            Button(action: onClearHistory) {
                Text(L10n.searchClearHistory)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.primary)
                    .padding(.horizontal, WeydaSpace.md)
                    .frame(minHeight: WeydaSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, WeydaSpace.lg)
        .padding(.trailing, WeydaSpace.xs)
    }

    private func historyRow(_ text: String) -> some View {
        PanelRow(
            symbol: "clock.arrow.circlepath",
            tint: WeydaColor.onSurfaceVariant,
            text: text,
            hint: nil,
            action: { onHistoryPick(text) }
        )
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        PanelRow(
            symbol: Self.symbol(for: suggestion.type),
            tint: WeydaColor.primary,
            text: suggestion.text,
            hint: Self.hint(for: suggestion.type),
            action: { onSuggestionPick(suggestion) }
        )
    }

    private static func symbol(for type: SuggestionType) -> String {
        switch type {
        case .category: return "square.grid.2x2"
        case .wilaya: return "mappin.and.ellipse"
        case .listing: return "magnifyingglass"
        }
    }

    private static func hint(for type: SuggestionType) -> String {
        switch type {
        case .category: return L10n.suggestionCategory
        case .wilaya: return L10n.suggestionWilaya
        case .listing: return L10n.suggestionListing
        }
    }
}

/// Une ligne de la liste : pictogramme, texte sur une ligne, nature de la suggestion au bout. Cible de 44 pt.
private struct PanelRow: View {
    let symbol: String
    let tint: Color
    let text: String
    let hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.md) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(tint)
                    .frame(width: WeydaSize.icon)
                    .accessibilityHidden(true)
                Text(text)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let hint {
                    Text(hint)
                        .weydaText(.labelSmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, WeydaSpace.lg)
            .frame(minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Ombre portée du panneau (Android : élévation « floating »).
private enum PanelShadow {
    static let color = Color(rgb: WeydaRamp.black, opacity: 0.14)
    static let radius: CGFloat = WeydaSpace.lg
    static let offset: CGFloat = WeydaSpace.xs
}
