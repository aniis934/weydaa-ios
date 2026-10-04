import SwiftUI

/// « Mes favoris », sans état propre — portage de `FavoritesScreen` (Android) : squelettes, erreur avec « Réessayer »,
/// e-mail à vérifier (bandeau « Vérifier » fixé en haut + explication), vide (« Parcourir les annonces »), ou la liste
/// native (`List`) des annonces : appui = la fiche (zoom depuis la carte), cœur plein, glissement vers le bord de fin
/// ou menu d'appui long = retirer (bannière « Retiré des favoris » + « Annuler »), tirer pour rafraîchir (posé par
/// l'hôte). Grand titre, comme les listes du Profil.
struct FavoritesScreen: View {
    private let state: FavoritesState
    private let currentUserId: String?
    private let actions: FavoritesActions

    /// Demi-gouttière au-dessus et au-dessous de chaque carte : `WeydaSpace.gutter` entre deux cartes.
    private static let rowGap: CGFloat = WeydaSpace.gutter / 2

    /// - Parameter currentUserId: compte connecté (menu d'appui long : pas de « Voir le vendeur » sur ses annonces).
    init(state: FavoritesState, currentUserId: String? = nil, actions: FavoritesActions) {
        self.state = state
        self.currentUserId = currentUserId
        self.actions = actions
    }

    /// Clé de la transition zoom d'une carte (source sur la carte, destination sur la fiche) : `favorites.<id>`.
    nonisolated static func zoomKey(for listing: Listing) -> String {
        "favorites.\(listing.id)"
    }

    /// Bandeau dans une pile, AU-DESSUS de la vue défilante, et non dans un `safeAreaInset` : sur iOS 26, l'effet de
    /// bord de défilement de la barre de navigation recouvre l'encart du haut (constat de la phase 3).
    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            if state.needsEmailVerification {
                VerifyEmailBanner()
                    .padding(.horizontal, WeydaSpace.screen)
                    .padding(.top, WeydaSpace.sm)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeydaColor.background)
        .navigationTitle(L10n.favoritesTitle)
        .navigationBarTitleDisplayMode(.large)
        .weydaBanner(state.banner, onAction: actions.onBannerAction, onDismiss: actions.onBannerDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.favorites")
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            ScrollView {
                ListingRowSkeletons()
            }
            .scrollDisabled(true)
        } else if state.needsEmailVerification {
            InboxScrollableState {
                EmptyState(
                    systemImage: "envelope.badge",
                    title: L10n.listsFavoritesUnverifiedTitle,
                    message: L10n.listsFavoritesUnverifiedBody
                )
            }
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: actions.onRetry)
        } else if state.items.isEmpty {
            InboxScrollableState {
                EmptyState(
                    systemImage: "heart",
                    title: L10n.favoritesEmpty,
                    message: L10n.favoritesEmptyHint,
                    actionTitle: L10n.listsBrowse,
                    action: actions.onBrowse
                )
            }
        } else {
            list
        }
    }

    /// Le nombre d'annonces, puis les cartes ; une ligne retirée s'efface (immobile si « Réduire les animations »).
    private var list: some View {
        let items: [Listing] = state.items
        let ids: [String] = items.map { $0.id }
        return List {
            Text(L10n.resultsCount(items.count))
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .accessibilityAddTraits(.isHeader)
                .listRowInsets(EdgeInsets(top: WeydaSpace.sm, leading: WeydaSpace.screen, bottom: WeydaSpace.xxs, trailing: WeydaSpace.screen))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(items) { listing in
                row(for: listing)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .weydaAnimation(.easeInOut(duration: WeydaDuration.medium), value: ids)
    }

    /// Une annonce : la carte de résultat (`ListingRow`, cœur plein, source du zoom) ; appui = la fiche ; glisser vers
    /// le bord de fin ou menu d'appui long = retirer des favoris.
    private func row(for listing: Listing) -> some View {
        let onRemove: () -> Void = { actions.onRemove(listing) }
        let key: String = Self.zoomKey(for: listing)
        return Button {
            actions.onOpen(listing)
        } label: {
            ListingRow(listing: listing, isFavorite: true, onFavorite: onRemove)
                .listingZoomSource(id: key)
        }
        .buttonStyle(.weydaCard)
        .listingContextMenu(
            listing,
            menu: ListingCardMenu(listing: listing, currentUserId: currentUserId),
            isFavorite: true,
            onFavorite: onRemove,
            onSeller: actions.onSeller
        )
        .listRowInsets(EdgeInsets(top: Self.rowGap, leading: WeydaSpace.screen, bottom: Self.rowGap, trailing: WeydaSpace.screen))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(action: onRemove) {
                Label(L10n.favoriteRemove, systemImage: "heart.slash")
            }
            .tint(WeydaColor.secondary)
        }
        .accessibilityLabel(ListingText.accessibilityLabel(for: listing))
        .accessibilityIdentifier("favorite.row.\(listing.id)")
    }
}
