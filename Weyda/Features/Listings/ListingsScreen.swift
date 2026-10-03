import SwiftUI
import UIKit

/// Actions de l'écran Annonces (le ViewModel derrière ; un visiteur est envoyé vers la connexion pour les favoris et
/// l'alerte par `ListingsView`).
struct ListingsActions {
    var onQueryChange: (String) -> Void
    var onSubmitSearch: () -> Void
    var onSuggestionPick: (Suggestion) -> Void
    var onHistoryPick: (String) -> Void
    var onClearHistory: () -> Void
    var onCategorySelect: (String?) -> Void
    var onSubcategoryToggle: (String) -> Void
    var onRemoveFilter: (ListingsChipKind) -> Void
    var onClearFilters: () -> Void
    var onOpenFilters: () -> Void
    var onCloseFilters: () -> Void
    var onApplyFilters: (ListingFilters) -> Void
    var onFilterWilayaChange: (Int?) -> Void
    /// Brouillon de la feuille modifié (sous-catégorie, attributs) : options des selects dépendants.
    var onDraftAttributesChange: (String?, [String: String]) -> Void
    var onSaveSearch: () -> Void
    var onRetry: () -> Void
    var onLoadMore: () -> Void
    var onRetryLoadMore: () -> Void
    var onDidYouMean: (String) -> Void
    var onToggleFavorite: (Listing) -> Void
}

/// Onglet Annonces, sans état — portage de `ListingsScreen.kt` : champ de recherche (historique, suggestions),
/// catégories racines en puces, sous-catégories, filtres actifs (bouton Filtres + nombre, « Créer une alerte »,
/// puces retirables), « Vouliez-vous dire », puis les résultats en lignes (`ListingRow`) paginés, avec squelettes,
/// vide, erreur, hors ligne et tirer pour rafraîchir. Barre de navigation masquée : le champ fait office d'en-tête
/// (comme Android et les places de marché iOS).
struct ListingsScreen: View {
    private let state: ListingsState
    private let suggestions: [Suggestion]
    private let history: [String]
    private let favoriteIds: Set<String>
    private let searchFocus: FocusState<Bool>.Binding
    private let filtersPresented: Binding<Bool>
    private let actions: ListingsActions
    private let onRefresh: @MainActor @Sendable () async -> Void
    private let onNoticeShown: @MainActor @Sendable () -> Void

    init(
        state: ListingsState,
        suggestions: [Suggestion],
        history: [String],
        favoriteIds: Set<String>,
        searchFocus: FocusState<Bool>.Binding,
        filtersPresented: Binding<Bool>,
        actions: ListingsActions,
        onRefresh: @escaping @MainActor @Sendable () async -> Void,
        onNoticeShown: @escaping @MainActor @Sendable () -> Void
    ) {
        self.state = state
        self.suggestions = suggestions
        self.history = history
        self.favoriteIds = favoriteIds
        self.searchFocus = searchFocus
        self.filtersPresented = filtersPresented
        self.actions = actions
        self.onRefresh = onRefresh
        self.onNoticeShown = onNoticeShown
    }

    /// Pagination : la page suivante est demandée quand l'une des 4 dernières lignes apparaît.
    private static let loadMoreDistance = 4
    private static let allCategoriesID = "listings.category.all"

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    filterBars
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showsSearchPanel {
                    searchPanel
                        .padding(.horizontal, WeydaSpace.screen)
                        .padding(.top, WeydaSpace.xxs)
                        .padding(.bottom, WeydaSpace.sm)
                        .zIndex(1)
                }
            }
        }
        .background(WeydaColor.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            OfflineBanner()
        }
        .overlay(alignment: .bottom) {
            noticeOverlay
        }
        .sheet(isPresented: filtersPresented) {
            FiltersSheet(
                state: state,
                onDismiss: actions.onCloseFilters,
                onApply: actions.onApplyFilters,
                onWilayaChange: actions.onFilterWilayaChange,
                onDraftAttributesChange: actions.onDraftAttributesChange
            )
        }
        .navigationTitle(L10n.navListings)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.listings")
    }

    // MARK: - Recherche

    private var searchBar: some View {
        ListingsSearchField(
            query: state.query,
            focus: searchFocus,
            onQueryChange: actions.onQueryChange,
            onSubmit: actions.onSubmitSearch
        )
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.top, WeydaSpace.sm)
        .padding(.bottom, WeydaSpace.xs)
    }

    /// Historique (champ vide) ou suggestions (dès 2 caractères), seulement pendant la saisie.
    private var showsSearchPanel: Bool {
        guard searchFocus.wrappedValue else { return false }
        if TextCheck.isBlank(state.query) {
            return !history.isEmpty
        }
        return !suggestions.isEmpty
    }

    private var searchPanel: some View {
        ListingsSearchPanel(
            query: state.query,
            suggestions: suggestions,
            history: history,
            onSuggestionPick: { suggestion in
                searchFocus.wrappedValue = false
                actions.onSuggestionPick(suggestion)
            },
            onHistoryPick: { text in
                searchFocus.wrappedValue = false
                actions.onHistoryPick(text)
            },
            onClearHistory: actions.onClearHistory
        )
    }

    // MARK: - Puces

    private var filterBars: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !state.categories.isEmpty {
                categoryChips
            }
            if let subcategories = state.selectedCategory?.children, !subcategories.isEmpty {
                subcategoryChips(subcategories)
            }
            activeFilters
            if let correction = state.didYouMean {
                didYouMeanButton(correction)
            }
        }
    }

    /// « Toutes » puis les catégories racines ; la catégorie choisie revient dans le champ de vision.
    private var categoryChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WeydaSpace.sm) {
                    WeydaChip(
                        title: L10n.allCategories,
                        isSelected: state.categorySlug == nil,
                        action: { actions.onCategorySelect(nil) }
                    )
                    .id(Self.allCategoriesID)
                    ForEach(state.categories) { category in
                        categoryChip(category)
                    }
                }
                .padding(.horizontal, WeydaSpace.screen)
            }
            .onAppear {
                scrollToSelectedCategory(proxy)
            }
            .onChange(of: state.categorySlug) { _ in
                scrollToSelectedCategory(proxy)
            }
        }
    }

    private func categoryChip(_ category: Category) -> some View {
        let selected = state.categorySlug == category.slug
        return WeydaChip(
            title: category.name.resolve(),
            isSelected: selected,
            iconAsset: CategoryIcon.assetName(forSlug: category.slug),
            action: { actions.onCategorySelect(selected ? nil : category.slug) }
        )
        .id(category.slug)
    }

    private func scrollToSelectedCategory(_ proxy: ScrollViewProxy) {
        let target = state.categorySlug ?? Self.allCategoriesID
        proxy.scrollTo(target, anchor: .center)
    }

    /// Sous-catégories en accès rapide, comme la barre de filtres du site.
    private func subcategoryChips(_ subcategories: [Category]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeydaSpace.sm) {
                ForEach(subcategories) { subcategory in
                    WeydaChip(
                        title: subcategory.name.resolve(),
                        isSelected: state.filters.subcategory == subcategory.slug,
                        action: { actions.onSubcategoryToggle(subcategory.slug) }
                    )
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
        }
    }

    /// Bouton Filtres (nombre de filtres actifs), « Créer une alerte », puces retirables, « Tout effacer » — miroir
    /// d'`ActiveFiltersBar` (site).
    private var activeFilters: some View {
        let chips = ListingsFilterRules.activeChips(for: state)
        let activeCount = state.filters.activeCount
        let canAlert = !state.toSearchParams().isEmpty
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeydaSpace.sm) {
                ListingsFiltersButton(count: activeCount, action: actions.onOpenFilters)
                if canAlert {
                    ListingsAlertButton(isSaving: state.isSavingSearch, action: actions.onSaveSearch)
                }
                ForEach(chips) { chip in
                    WeydaChip(
                        title: chip.title,
                        isSelected: true,
                        onRemove: { actions.onRemoveFilter(chip.kind) },
                        action: { actions.onRemoveFilter(chip.kind) }
                    )
                }
                if activeCount > 0 {
                    Button(action: actions.onClearFilters) {
                        Text(L10n.filtersClearAll)
                            .weydaText(.labelLarge)
                            .foregroundStyle(WeydaColor.primary)
                            .padding(.horizontal, WeydaSpace.xs)
                            .frame(minHeight: WeydaSize.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
        }
    }

    private func didYouMeanButton(_ correction: String) -> some View {
        Button {
            actions.onDidYouMean(correction)
        } label: {
            Text(L10n.searchDidYouMean(correction))
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: WeydaSize.touchTarget, alignment: .leading)
                .padding(.horizontal, WeydaSpace.screen)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("listings.didYouMean")
    }

    // MARK: - Contenu

    /// Squelettes plutôt qu'un rond : la recherche et les filtres restent utilisables pendant la requête, et la liste
    /// ne saute pas à l'arrivée des résultats.
    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            ListingRowSkeletons()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else if state.isError {
            ErrorState(message: state.errorMessage ?? L10n.errorGeneric, onRetry: actions.onRetry)
        } else if state.items.isEmpty {
            emptyState
        } else {
            results
        }
    }

    private var emptyState: some View {
        let clear: (() -> Void)? = state.filters.activeCount > 0 ? actions.onClearFilters : nil
        let clearTitle: String? = clear == nil ? nil : L10n.filtersClearAll
        return ScrollView {
            EmptyState(
                systemImage: "magnifyingglass",
                title: L10n.emptyResults,
                message: L10n.emptyResultsHint,
                actionTitle: clearTitle,
                action: clear
            )
            .padding(.top, WeydaSpace.xxl)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var results: some View {
        let refresh = onRefresh
        let threshold = max(state.items.count - Self.loadMoreDistance, 0)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: WeydaSpace.gutter) {
                Text(L10n.resultsCount(state.total))
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(state.items.enumerated()), id: \.element.id) { entry in
                    row(entry.element)
                        .onAppear {
                            if entry.offset >= threshold {
                                actions.onLoadMore()
                            }
                        }
                }
                footer
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.sm)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await refresh()
        }
    }

    private func row(_ listing: Listing) -> some View {
        NavigationLink(value: AppRoute.detail(idOrSlug: listing.id)) {
            ListingRow(
                listing: listing,
                isFavorite: favoriteIds.contains(listing.id),
                onFavorite: { actions.onToggleFavorite(listing) }
            )
        }
        .buttonStyle(.weydaCard)
        .accessibilityIdentifier("listings.row.\(listing.id)")
    }

    /// Bas de liste : chargement de la page suivante, ou « Réessayer » après son échec.
    @ViewBuilder
    private var footer: some View {
        if state.isLoadingMore {
            InlineLoader()
        } else if state.loadMoreFailed {
            Button(action: actions.onRetryLoadMore) {
                Text(L10n.retry)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.primary)
                    .frame(maxWidth: .infinity, minHeight: WeydaSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Conteneur toujours présent : l'arrivée et le départ du message s'animent (rien ne bouge si « Réduire les
    /// animations »).
    private var noticeOverlay: some View {
        ZStack(alignment: .bottom) {
            if let notice = state.notice {
                ListingsNoticeToast(notice: notice, onDismiss: onNoticeShown)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .weydaAnimation(.easeOut(duration: WeydaDuration.medium), value: state.notice)
    }
}

// MARK: - Champ de recherche

/// `WeydaSearchField` relié au ViewModel : le texte vit ici pendant la frappe et suit `query` quand le ViewModel le
/// change (suggestion choisie, « Vouliez-vous dire », alerte). Valider ferme le clavier puis cherche.
private struct ListingsSearchField: View {
    private let query: String
    private let focus: FocusState<Bool>.Binding
    private let onQueryChange: (String) -> Void
    private let onSubmit: () -> Void
    @State private var text: String

    init(query: String, focus: FocusState<Bool>.Binding, onQueryChange: @escaping (String) -> Void, onSubmit: @escaping () -> Void) {
        self.query = query
        self.focus = focus
        self.onQueryChange = onQueryChange
        self.onSubmit = onSubmit
        _text = State(initialValue: query)
    }

    var body: some View {
        WeydaSearchField(text: $text, placeholder: L10n.searchHint, onSubmit: submit)
            .focused(focus)
            .onChange(of: text) { value in
                if value != query {
                    onQueryChange(value)
                }
            }
            .onChange(of: query) { value in
                if value != text {
                    text = value
                }
            }
    }

    private func submit() {
        focus.wrappedValue = false
        onSubmit()
    }
}

// MARK: - Boutons de la barre des filtres

/// Bouton « Filtres » : capsule comme les puces, nombre de filtres actifs en pastille verte (Android : Badge).
private struct ListingsFiltersButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L10n.filtersTitle)
                    .weydaText(.labelLarge)
                    .lineLimit(1)
                if count > 0 {
                    Text(Format.count(count))
                        .weydaText(.labelSmall)
                        .foregroundStyle(WeydaColor.onPrimary)
                        .padding(.horizontal, WeydaSpace.xs + WeydaSpace.xxs)
                        .frame(minWidth: ChipCapsule.badge, minHeight: ChipCapsule.badge)
                        .background(WeydaColor.primary, in: Capsule())
                }
            }
            .foregroundStyle(WeydaColor.onSurface)
            .modifier(ChipCapsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.filtersTitle)
        .accessibilityValue(count > 0 ? Format.count(count) : "")
        .accessibilityIdentifier("listings.filters")
    }
}

/// « Créer une alerte » : visible dès qu'il y a un critère (comme Android), inactif pendant l'envoi.
private struct ListingsAlertButton: View {
    let isSaving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
                Image(systemName: "bell")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L10n.alertCreate)
                    .weydaText(.labelLarge)
                    .lineLimit(1)
            }
            .foregroundStyle(WeydaColor.onSurface)
            .modifier(ChipCapsule())
            .opacity(isSaving ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityIdentifier("listings.alert")
    }
}

/// Capsule des boutons de la barre : celle des puces (36 pt visibles dans une cible de 44 pt, filet fin).
private struct ChipCapsule: ViewModifier {
    static let badge: CGFloat = WeydaSize.icon

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, WeydaSpace.md)
            .frame(minHeight: WeydaSize.touchTarget)
            .background {
                Capsule()
                    .fill(WeydaColor.surface)
                    .overlay {
                        Capsule().strokeBorder(WeydaColor.outlineVariant, lineWidth: 1)
                    }
                    .padding(.vertical, WeydaSpace.xs)
            }
            .contentShape(Rectangle())
    }
}

// MARK: - Message éphémère

/// Message éphémère en bas de l'écran (le Snackbar d'Android) : lu par VoiceOver, effacé après 3 s.
private struct ListingsNoticeToast: View {
    let notice: ListingsNotice
    let onDismiss: @MainActor @Sendable () -> Void

    var body: some View {
        Text(notice.text)
            .weydaText(.labelLarge)
            .foregroundStyle(WeydaColor.surface)
            .multilineTextAlignment(.center)
            .padding(.horizontal, WeydaSpace.lg)
            .padding(.vertical, WeydaSpace.md)
            .background(WeydaColor.onSurface, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.bottom, WeydaSpace.lg)
            .accessibilityIdentifier("listings.notice")
            .task(id: notice) {
                await announceThenDismiss()
            }
    }

    /// Lu tout de suite par VoiceOver, effacé 3 s plus tard (un nouveau message relance le délai).
    private func announceThenDismiss() async {
        UIAccessibility.post(notification: .announcement, argument: notice.text)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        onDismiss()
    }
}
