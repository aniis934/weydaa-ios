import SwiftUI

/// « Mes alertes », sans état propre — portage de `SavedSearchesScreen` (Android) : squelettes, erreur avec
/// « Réessayer », vide (comment créer une alerte + « Lancer une recherche »), ou la liste groupée façon Réglages : par
/// alerte son nom, ses critères en clair (puces), sa date de création ; appui = les annonces de l'alerte dans l'onglet
/// Annonces ; glisser vers le bord de fin = supprimer tout de suite, « Annuler » dans la bannière (comme Mail).
/// Compteur « n / 5 » en tête de section, note en pied, « Lancer une recherche » tant que la limite n'est pas atteinte.
/// Tirer pour rafraîchir : posé par l'hôte. Grand titre, comme les listes du Profil.
struct SavedSearchesScreen: View {
    private let state: SavedSearchesState
    private let limit: Int
    private let actions: SavedSearchesActions

    init(state: SavedSearchesState, limit: Int, actions: SavedSearchesActions) {
        self.state = state
        self.limit = limit
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeydaColor.background)
        .navigationTitle(L10n.alertsTitle)
        .navigationBarTitleDisplayMode(.large)
        .weydaBanner(state.banner, onAction: actions.onBannerAction, onDismiss: actions.onBannerDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.savedSearches")
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            InboxRowSkeletons(count: 4, showsThumb: false)
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: actions.onRetry)
        } else if state.items.isEmpty {
            InboxScrollableState {
                EmptyState(
                    systemImage: "bell",
                    title: L10n.alertsEmpty,
                    message: L10n.alertsEmptyHint,
                    actionTitle: L10n.listsAlertsSearch,
                    action: actions.onSearch
                )
            }
        } else {
            list
        }
    }

    /// Une alerte supprimée s'efface (immobile si « Réduire les animations »).
    private var list: some View {
        let items: [SavedSearch] = state.items
        let catalog: AlertCatalog = state.catalog
        let canAdd: Bool = items.count < limit
        let ids: [String] = items.map { $0.id }
        return List {
            Section {
                ForEach(items) { alert in
                    row(for: alert, catalog: catalog)
                }
            } header: {
                Text(SavedSearchCriteria.usage(count: items.count, limit: limit))
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityIdentifier("alerts.usage")
            } footer: {
                Text(canAdd ? L10n.alertsEmptyHint : L10n.alertLimit)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
            if canAdd {
                Section {
                    Button(action: actions.onSearch) {
                        AccountMenuRow(title: L10n.listsAlertsSearch, systemImage: "magnifyingglass")
                    }
                    .listRowBackground(WeydaColor.surface)
                    .accessibilityIdentifier("alerts.search")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .weydaAnimation(.easeInOut(duration: WeydaDuration.medium), value: ids)
    }

    /// Une alerte : appui = ses annonces ; glisser vers le bord de fin = supprimer (sans confirmation : « Annuler » dans
    /// la bannière), action aussi proposée à VoiceOver par la liste. Rôle « destructif » : la liste fait partir la
    /// ligne d'elle-même, comme l'état.
    private func row(for alert: SavedSearch, catalog: AlertCatalog) -> some View {
        let criteria: [AlertCriterion] = SavedSearchCriteria.criteria(for: alert.params, catalog: catalog)
        return Button {
            actions.onOpen(alert)
        } label: {
            SavedSearchRow(alert: alert, criteria: criteria)
        }
        .listRowBackground(WeydaColor.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                actions.onDelete(alert)
            } label: {
                Label(L10n.alertDelete, systemImage: "trash")
            }
            .tint(WeydaColor.error)
        }
        .accessibilityLabel(SavedSearchCriteria.accessibilityLabel(for: alert, criteria: criteria))
        .accessibilityHint(L10n.listsAlertOpenHint)
        .accessibilityIdentifier("alert.row.\(alert.id)")
    }
}

// MARK: - Rangée

/// Une alerte : cloche, nom (sur autant de lignes qu'il faut), critères en puces, date de création, chevron. En très
/// grand texte, la cloche s'efface pour laisser la largeur au texte.
private struct SavedSearchRow: View {
    private let alert: SavedSearch
    private let criteria: [AlertCriterion]
    @Environment(\.dynamicTypeSize) private var typeSize

    init(alert: SavedSearch, criteria: [AlertCriterion]) {
        self.alert = alert
        self.criteria = criteria
    }

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            HStack(alignment: .top, spacing: WeydaSpace.md) {
                if !typeSize.isAccessibilitySize {
                    SavedSearchBell()
                }
                details
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WeydaColor.outline)
                .accessibilityHidden(true)
        }
        .padding(.vertical, WeydaSpace.xs)
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            Text(alert.name)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !criteria.isEmpty {
                SavedSearchCriteriaView(criteria: criteria)
            }
            if let created = SavedSearchCriteria.createdOn(alert) {
                Text(created)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cloche verte sur pastille ronde (le pictogramme des alertes dans le Profil).
private struct SavedSearchBell: View {
    private static let side: CGFloat = 36

    init() {}

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WeydaColor.primary)
            .frame(width: Self.side, height: Self.side)
            .background(WeydaColor.primaryContainer, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Puces des critères

/// Les critères en puces, passés à la ligne sans rien rogner : toutes sur une ligne si elles tiennent, sinon par 3,
/// par 2, puis une par ligne (texte sur plusieurs lignes en très grand texte). Lus par VoiceOver dans l'étiquette de la
/// rangée.
private struct SavedSearchCriteriaView: View {
    private let criteria: [AlertCriterion]

    init(criteria: [AlertCriterion]) {
        self.criteria = criteria
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SavedSearchCriteriaRows(criteria: criteria, perRow: criteria.count, wraps: false)
            SavedSearchCriteriaRows(criteria: criteria, perRow: 3, wraps: false)
            SavedSearchCriteriaRows(criteria: criteria, perRow: 2, wraps: false)
            SavedSearchCriteriaRows(criteria: criteria, perRow: 1, wraps: true)
        }
        .accessibilityHidden(true)
    }
}

private struct SavedSearchCriteriaRows: View {
    private let rows: [[AlertCriterion]]
    private let wraps: Bool

    init(criteria: [AlertCriterion], perRow: Int, wraps: Bool) {
        self.rows = SavedSearchCriteria.rows(criteria, perRow: perRow)
        self.wraps = wraps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                HStack(spacing: WeydaSpace.xs) {
                    ForEach(entry.element) { criterion in
                        SavedSearchCriterionChip(criterion: criterion, wraps: wraps)
                    }
                }
            }
        }
    }
}

/// Une puce : pictogramme vert (icône de la catégorie, épingle, symbole) et libellé, sur le fond des conteneurs.
private struct SavedSearchCriterionChip: View {
    private let criterion: AlertCriterion
    private let wraps: Bool
    @ScaledMetric(relativeTo: .caption) private var iconSide: CGFloat = 13

    init(criterion: AlertCriterion, wraps: Bool) {
        self.criterion = criterion
        self.wraps = wraps
    }

    var body: some View {
        HStack(spacing: WeydaSpace.xs) {
            icon
            Text(criterion.title)
                .weydaText(.labelMedium)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: false, vertical: wraps)
        }
        .padding(.horizontal, WeydaSpace.sm)
        .padding(.vertical, WeydaSpace.xs)
        .background(
            WeydaColor.surfaceContainer,
            in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous)
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch criterion.icon {
        case .asset(let name):
            CategoryIconImage(assetName: name, size: iconSide)
                .foregroundStyle(WeydaColor.primary)
        case .symbol(let name):
            Image(systemName: name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
        }
    }
}
