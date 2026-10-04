import SwiftUI

/// « Mes annonces » — portage de `MyListingsRoute` / `MyListingsScreen` (MyListingsScreen.kt) : onglets par statut,
/// badges, note de modération IA sous une annonce refusée, ouverture de la fiche, et sous chaque annonce ses actions
/// (`ListingActionsRow`) : modifier, marquer vendu, renouveler, supprimer — vendu et suppression après confirmation
/// (feuille d'actions iOS ; Android : `ConfirmActionDialog`), bannière après chaque action (le Snackbar d'Android). Les
/// mêmes actions s'ouvrent aussi par un appui long sur la carte.
struct MyListingsView: View {
    @EnvironmentObject private var container: AppContainer

    init() {}

    var body: some View {
        AccountMemberGate(title: L10n.myListingsTitle) { _ in
            MyListingsHost(
                model: MyListingsViewModel(
                    users: container.users,
                    annonces: container.annonces,
                    reviewPrompter: container.reviewPrompter
                )
            )
        }
    }
}

/// Possède le ViewModel ; recharge en silence à chaque retour sur l'écran (dont le retour de l'édition d'une
/// annonce : sa ligne a pu changer, titre ou statut).
private struct MyListingsHost: View {
    @StateObject private var model: MyListingsViewModel
    @EnvironmentObject private var router: AppRouter

    init(model: @autoclosure @escaping () -> MyListingsViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        MyListingsScreen(
            state: model.state,
            isConfirmationPresented: confirmationBinding,
            onFilter: { status in _ = model.setFilter(status) },
            onRetry: { _ = model.load() },
            onLoadMore: { _ = model.loadMore() },
            onPost: { router.select(.post) },
            onAction: { action, listing in perform(action, on: listing) },
            onConfirm: { _ = model.confirmAction() },
            onCancelConfirmation: { model.dismissAction() },
            onNoticeShown: { model.noticeShown() }
        )
        // `@MainActor` explicite : juste, que le SDK fasse hériter cette fermeture de l'acteur de la vue ou non.
        .refreshable { @MainActor [model] in
            await model.pullToRefresh()
        }
        .onAppear {
            _ = model.appear()
        }
        // Annonce vendue : demande de note quand c'est le bon moment (`ReviewPrompter`).
        .requestsReview(when: model.asksForReview)
    }

    /// Boutons d'une annonce — `MyListingsActions` (Android) : modifier ouvre l'assistant en édition, vendu et
    /// suppression demandent confirmation, renouveler part tout de suite.
    private func perform(_ action: MyListingRowAction, on listing: Listing) {
        switch action {
        case .edit:
            router.push(.editListing(id: listing.id))
        case .sold:
            model.askMarkSold(listing)
        case .renew:
            _ = model.renew(listing)
        case .delete:
            model.askDelete(listing)
        }
    }

    /// Feuille de confirmation, ouverte tant qu'une action attend (`pendingAction`). Un appui sur l'un de ses boutons
    /// la referme et SwiftUI repasse la liaison à « faux » — peut-être AVANT d'exécuter l'action du bouton, qui lit
    /// encore l'action en attente : l'effacement est donc reporté au tour suivant (sans effet si le bouton l'a fait).
    private var confirmationBinding: Binding<Bool> {
        let model = self.model
        return Binding(
            get: { MainActor.assumeIsolated { model.state.pendingAction != nil } },
            set: { presented in
                guard !presented else { return }
                Task { @MainActor in
                    model.dismissAction()
                }
            }
        )
    }
}

/// Écran sans état : grand titre, puis la vue défilante (puces de statut en tête, squelettes, erreur, vide, ou les
/// annonces et leurs actions), la feuille de confirmation d'une action et la bannière qui la suit.
struct MyListingsScreen: View {
    private let state: MyListingsState
    private let isConfirmationPresented: Binding<Bool>
    private let onFilter: (ListingStatus?) -> Void
    private let onRetry: () -> Void
    private let onLoadMore: () -> Void
    private let onPost: () -> Void
    private let onAction: (MyListingRowAction, Listing) -> Void
    private let onConfirm: () -> Void
    private let onCancelConfirmation: () -> Void
    private let onNoticeShown: () -> Void

    /// La page suivante se demande quand l'une des 4 dernières annonces paraît (Android : même seuil).
    private static let prefetchDistance = 4
    /// Ancre du haut de la liste (la rangée de puces).
    private static let topAnchor = "myListings.top"
    /// Hauteur estimée de la rangée de puces (cible tactile et marges) : erreur et liste vide se centrent dessous.
    private static let filterBarHeight: CGFloat = WeydaSize.touchTarget + WeydaSpace.sm

    init(
        state: MyListingsState,
        isConfirmationPresented: Binding<Bool>,
        onFilter: @escaping (ListingStatus?) -> Void,
        onRetry: @escaping () -> Void,
        onLoadMore: @escaping () -> Void,
        onPost: @escaping () -> Void,
        onAction: @escaping (MyListingRowAction, Listing) -> Void,
        onConfirm: @escaping () -> Void,
        onCancelConfirmation: @escaping () -> Void,
        onNoticeShown: @escaping () -> Void
    ) {
        self.state = state
        self.isConfirmationPresented = isConfirmationPresented
        self.onFilter = onFilter
        self.onRetry = onRetry
        self.onLoadMore = onLoadMore
        self.onPost = onPost
        self.onAction = onAction
        self.onConfirm = onConfirm
        self.onCancelConfirmation = onCancelConfirmation
        self.onNoticeShown = onNoticeShown
    }

    /// Puces EN TÊTE du contenu défilant (phase 8) : posées au-dessus, leur vue défilante horizontale était la première
    /// de l'écran et captait le grand titre, qui ne se repliait plus. Jamais dans un `safeAreaInset` : sur iOS 26,
    /// l'effet de bord de défilement de la barre de navigation recouvre l'encart du haut (captures de la phase 3).
    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeydaColor.background)
        .navigationTitle(L10n.myListingsTitle)
        .navigationBarTitleDisplayMode(.large)
        .weydaBanner(state.banner, onAction: { _ in }, onDismiss: onNoticeShown)
        .confirmationDialog(
            confirmationTitle,
            isPresented: isConfirmationPresented,
            titleVisibility: .visible,
            presenting: state.pendingAction
        ) { action in
            confirmationButtons(for: action)
        } message: { action in
            Text(MyListingsText.confirmationMessage(for: action))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.myListings")
    }

    /// Titre de la confirmation (vide le temps que la feuille se referme).
    private var confirmationTitle: String {
        state.pendingAction.map { MyListingsText.confirmationTitle(for: $0) } ?? ""
    }

    /// `ConfirmActionDialog` (Android) : « Confirmer la vente », ou « Supprimer » en rouge, puis « Annuler » (à part,
    /// en bas de la feuille d'actions).
    @ViewBuilder
    private func confirmationButtons(for action: MyListingAction) -> some View {
        switch action {
        case .markSold:
            Button(L10n.myListingSoldConfirmBtn, action: onConfirm)
        case .delete:
            Button(L10n.myListingDelete, role: .destructive, action: onConfirm)
        }
        Button(L10n.cancel, role: .cancel, action: onCancelConfirmation)
    }

    /// UNE vue défilante pour tous les états, puces en tête : la rangée de puces garde sa position quand le filtre
    /// change, la liste repart du haut (Android le faisait à la main, `scrollToItem(0)`). Erreur et liste vide restent
    /// défilantes (« tirer pour rafraîchir ») et se centrent dans la place laissée par les puces.
    private var content: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        MyListingsFilterBar(selected: state.filter, onSelect: onFilter)
                            .id(Self.topAnchor)
                        stateContent(minHeight: max(geometry.size.height - Self.filterBarHeight, 0))
                    }
                }
                .onChange(of: state.filter) { _ in
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func stateContent(minHeight: CGFloat) -> some View {
        if state.isLoading {
            ListingRowSkeletons()
        } else if let message = state.errorMessage {
            ErrorState(message: message, onRetry: onRetry)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        } else if state.items.isEmpty {
            emptyMessage
                .frame(maxWidth: .infinity, minHeight: minHeight)
        } else {
            list
        }
    }

    /// Une action à la fois (règle du ViewModel) : pendant qu'elle tourne, les boutons de TOUTES les annonces sont
    /// désactivés, l'indicateur n'apparaît que sur la sienne.
    private var list: some View {
        let trailing: Set<String> = Set(state.items.suffix(Self.prefetchDistance).map(\.id))
        let busyId: String? = state.busyId
        return LazyVStack(spacing: WeydaSpace.gutter) {
            ForEach(state.items) { listing in
                MyListingCard(
                    listing: listing,
                    isBusy: busyId == listing.id,
                    isLocked: busyId != nil,
                    onAction: { action in onAction(action, listing) }
                )
                .onAppear {
                    if trailing.contains(listing.id) {
                        onLoadMore()
                    }
                }
            }
            if state.isLoadingMore {
                InlineLoader()
            }
        }
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.vertical, WeydaSpace.md)
    }

    /// Aucune annonce : sans filtre, une invitation à déposer ; avec un filtre, le retour à « Toutes ».
    @ViewBuilder
    private var emptyMessage: some View {
        if state.filter == nil {
            EmptyState(
                systemImage: AppRoute.myListings.symbol,
                title: L10n.emptyResults,
                actionTitle: L10n.postTitle,
                action: onPost
            )
        } else {
            EmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: L10n.emptyResults,
                actionTitle: L10n.filterAll,
                action: { onFilter(nil) }
            )
        }
    }
}

// MARK: - Puces de statut

/// Un onglet de statut (nil = toutes), dans l'ordre d'Android.
nonisolated struct MyListingsFilter: Identifiable, Hashable, Sendable {
    let id: String
    let status: ListingStatus?

    static let all: [MyListingsFilter] = [
        MyListingsFilter(id: "all", status: nil),
        MyListingsFilter(id: "active", status: .active),
        MyListingsFilter(id: "pending", status: .pending),
        MyListingsFilter(id: "sold", status: .sold),
        MyListingsFilter(id: "expired", status: .expired),
        MyListingsFilter(id: "rejected", status: .rejected),
    ]

    var title: String {
        guard let status else { return L10n.filterAll }
        return MyListingsText.statusTitle(status)
    }
}

private struct MyListingsFilterBar: View {
    let selected: ListingStatus?
    let onSelect: (ListingStatus?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeydaSpace.sm) {
                ForEach(MyListingsFilter.all) { filter in
                    WeydaChip(
                        title: filter.title,
                        isSelected: filter.status == selected,
                        action: { onSelect(filter.status) }
                    )
                    .accessibilityIdentifier("myListings.filter.\(filter.id)")
                }
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.xs)
        }
    }
}

// MARK: - Ligne d'annonce

/// Textes d'une annonce de « Mes annonces ». Logique pure, testable.
nonisolated enum MyListingsText {
    static func statusTitle(_ status: ListingStatus) -> String {
        switch status {
        case .active: L10n.statusActive
        case .pending: L10n.statusPending
        case .sold: L10n.statusSold
        case .expired: L10n.statusExpired
        case .rejected: L10n.statusRejected
        }
    }

    /// Motifs de modération à montrer (3 au plus) : seulement sur une annonce qui n'est pas en ligne.
    static func moderationReasons(for listing: Listing) -> [String] {
        guard listing.listingStatus != .active, let verdict = listing.moderation else { return [] }
        let reasons = verdict.reasons.filter { !TextCheck.isBlank($0) }
        return Array(reasons.prefix(3))
    }

    /// « 128 vues · il y a 3 j » (les morceaux vides disparaissent).
    static func meta(for listing: Listing, now: Date = Date()) -> String {
        let age: String? = TextCheck.nonBlank(Format.relativeTime(listing.createdAt, now: now))
        return [L10n.detailViews(listing.views), age].compactMap { $0 }.joined(separator: " · ")
    }

    /// Ce que VoiceOver lit pour une ligne : statut, titre, prix, vues et ancienneté, motifs de modération.
    static func accessibilityLabel(for listing: Listing, now: Date = Date()) -> String {
        var parts: [String] = [statusTitle(listing.listingStatus), listing.title, Format.price(listing.price, type: listing.priceType)]
        if let mention = Format.negotiableLabel(price: listing.price, type: listing.priceType) {
            parts.append(mention)
        }
        parts.append(meta(for: listing, now: now))
        let reasons = moderationReasons(for: listing)
        if !reasons.isEmpty {
            parts.append(L10n.moderationReason)
            parts.append(contentsOf: reasons)
        }
        return parts.joined(separator: ", ")
    }

    /// Titre de la confirmation d'une action (`ConfirmActionDialog`).
    static func confirmationTitle(for action: MyListingAction) -> String {
        switch action {
        case .markSold: L10n.myListingSoldConfirmTitle
        case .delete: L10n.myListingDeleteConfirmTitle
        }
    }

    static func confirmationMessage(for action: MyListingAction) -> String {
        switch action {
        case .markSold: L10n.myListingSoldConfirmBody
        case .delete: L10n.myListingDeleteConfirmBody
        }
    }
}

// MARK: - Actions d'une annonce

/// Un bouton sous une annonce — règles de `ListingActionsRow` (Android). Logique pure, testable.
nonisolated enum MyListingRowAction: String, CaseIterable, Hashable, Sendable {
    case edit, sold, renew, delete

    /// Boutons proposés, dans l'ordre d'Android : Modifier (sauf vendue), Marquer vendu (en ligne), Renouveler
    /// (expirée, ou en ligne à moins de 7 jours de l'échéance, s'il reste des renouvellements), Supprimer (toujours).
    static func available(for listing: Listing, now: Date = Date()) -> [MyListingRowAction] {
        let status = listing.listingStatus
        var result: [MyListingRowAction] = []
        if status != .sold {
            result.append(.edit)
        }
        if status == .active {
            result.append(.sold)
        }
        if listing.isRenewable(now: now) && listing.renewalsLeft > 0 {
            result.append(.renew)
        }
        result.append(.delete)
        return result
    }

    /// Renouvelable mais plus aucun renouvellement : une information (`error_renewal_limit`), pas un bouton désactivé.
    static func showsRenewalLimit(for listing: Listing, now: Date = Date()) -> Bool {
        listing.isRenewable(now: now) && listing.renewalsLeft == 0
    }

    func title(for listing: Listing) -> String {
        switch self {
        case .edit: L10n.myListingEdit
        case .sold: L10n.myListingMarkSold
        case .renew: L10n.myListingRenew(listing.renewalsLeft)
        case .delete: L10n.myListingDelete
        }
    }

    var symbol: String {
        switch self {
        case .edit: "square.and.pencil"
        case .sold: "checkmark.circle"
        case .renew: "arrow.clockwise"
        case .delete: "trash"
        }
    }

    var isDestructive: Bool { self == .delete }

    /// Identifiant stable (tour de captures) : `myListing.<edit|sold|renew|delete>.<id>`.
    func accessibilityIdentifier(for listingId: String) -> String {
        "myListing.\(rawValue).\(listingId)"
    }
}

/// Carte d'une annonce du membre : la partie haute ouvre la fiche, la barre du bas porte ses actions. Deux zones
/// sœurs (et non des boutons dans le lien) : chaque bouton reste atteignable par VoiceOver et par le tour ; le lien
/// propose en plus les mêmes actions dans le rotor.
private struct MyListingCard: View {
    let listing: Listing
    let isBusy: Bool
    let isLocked: Bool
    let onAction: (MyListingRowAction) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        let actions = MyListingRowAction.available(for: listing)
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: AppRoute.detail(idOrSlug: listing.id)) {
                MyListingRow(listing: listing)
            }
            .buttonStyle(MyListingLinkStyle())
            .accessibilityIdentifier("myListings.row.\(listing.id)")
            .accessibilityActions {
                if !isLocked {
                    ForEach(actions, id: \.self) { action in
                        Button(action.title(for: listing)) {
                            onAction(action)
                        }
                    }
                }
            }
            // Appui long : les mêmes actions que la barre (mêmes règles, désactivées pendant une action), avec
            // l'aperçu de l'annonce. Pas de glissements : la liste n'est pas une `List` (décision de la phase 8).
            .contextMenu {
                MyListingMenuItems(listing: listing, actions: actions, isLocked: isLocked, onAction: onAction)
            } preview: {
                MyListingMenuPreview(listing: listing)
            }
            Rectangle()
                .fill(WeydaPalette.cardOutline)
                .frame(height: 1)
            MyListingActionsBar(
                listing: listing,
                actions: actions,
                isBusy: isBusy,
                isLocked: isLocked,
                onAction: onAction
            )
        }
        .background(WeydaColor.surface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
    }
}

/// Entrées du menu d'appui long d'une carte : les actions de la barre, dans le même ordre, « Supprimer » en rouge.
/// Les identifiants `myListing.<action>.<id>` restent ceux des boutons visibles (ceux du menu ont `myListing.menu.…`).
private struct MyListingMenuItems: View {
    private let listing: Listing
    private let actions: [MyListingRowAction]
    private let isLocked: Bool
    private let onAction: (MyListingRowAction) -> Void

    init(listing: Listing, actions: [MyListingRowAction], isLocked: Bool, onAction: @escaping (MyListingRowAction) -> Void) {
        self.listing = listing
        self.actions = actions
        self.isLocked = isLocked
        self.onAction = onAction
    }

    var body: some View {
        ForEach(actions, id: \.self) { action in
            Button(role: role(for: action)) {
                onAction(action)
            } label: {
                Label(action.title(for: listing), systemImage: action.symbol)
            }
            .disabled(isLocked)
            .accessibilityIdentifier("myListing.menu.\(action.rawValue).\(listing.id)")
        }
    }

    private func role(for action: MyListingRowAction) -> ButtonRole? {
        action.isDestructive ? .destructive : nil
    }
}

/// Aperçu de l'appui long : la carte d'annonce à largeur fixe (comme `listingContextMenu`), sans cœur.
private struct MyListingMenuPreview: View {
    private let listing: Listing

    init(listing: Listing) {
        self.listing = listing
    }

    var body: some View {
        ListingCard(listing: listing)
            .frame(width: WeydaSize.carouselCard)
            .padding(WeydaSpace.sm)
            .background(WeydaColor.background)
    }
}

/// Appui sur la partie haute de la carte : un voile léger (le retrait `.weydaCard` rétrécirait le contenu À
/// L'INTÉRIEUR du cadre, la barre d'actions restant fixe).
private struct MyListingLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                WeydaColor.onSurface
                    .opacity(configuration.isPressed ? 0.06 : 0)
                    .allowsHitTesting(false)
            }
    }
}

/// Barre d'actions : cellules de même largeur (icône au-dessus du libellé), sur une seule ligne quel que soit leur
/// nombre — Android passait à la ligne (FlowRow) des boutons texte qui ne tenaient pas. Très grand texte : deux
/// cellules par ligne (à quatre sur une ligne, « Renouveler (60 j) » se tronquait). Pendant l'action de CETTE
/// annonce, l'indicateur remplace les boutons ; pendant celle d'une autre, ils sont seulement désactivés.
private struct MyListingActionsBar: View {
    private let listing: Listing
    private let actions: [MyListingRowAction]
    private let isBusy: Bool
    private let isLocked: Bool
    private let onAction: (MyListingRowAction) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Très grand texte : deux colonnes égales (une action seule sur sa ligne garde la largeur d'une colonne).
    private static let largeColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 0, alignment: .top),
        GridItem(.flexible(), spacing: 0, alignment: .top),
    ]

    init(
        listing: Listing,
        actions: [MyListingRowAction],
        isBusy: Bool,
        isLocked: Bool,
        onAction: @escaping (MyListingRowAction) -> Void
    ) {
        self.listing = listing
        self.actions = actions
        self.isBusy = isBusy
        self.isLocked = isLocked
        self.onAction = onAction
    }

    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: Self.largeColumns, spacing: 0) {
                ForEach(actions, id: \.self) { action in
                    button(for: action)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(actions, id: \.self) { action in
                    button(for: action)
                }
            }
        }
    }

    private func button(for action: MyListingRowAction) -> some View {
        MyListingActionButton(
            action: action,
            title: action.title(for: listing),
            identifier: action.accessibilityIdentifier(for: listing.id),
            onTap: { onAction(action) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                buttons
                    .opacity(isBusy ? 0 : 1)
                    .accessibilityHidden(isBusy)
                if isBusy {
                    WeydaLoader()
                        .frame(width: WeydaSize.iconLarge, height: WeydaSize.iconLarge)
                }
            }
            .disabled(isLocked)
            if MyListingRowAction.showsRenewalLimit(for: listing) {
                Text(L10n.errorRenewalLimit)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WeydaSpace.md)
                    .padding(.bottom, WeydaSpace.sm)
            }
        }
        .padding(.horizontal, WeydaSpace.xs)
    }
}

/// Une cellule de la barre : icône puis libellé (2 lignes au plus), teinte verte — rouge pour « Supprimer ».
/// Cible d'au moins 44 pt ; grisée quand la barre est désactivée. Très grand texte : une ligne par mot au plus
/// (3 lignes), réduite jusqu'à 70 % — jamais un mot coupé ni tronqué.
private struct MyListingActionButton: View {
    private let action: MyListingRowAction
    private let title: String
    private let identifier: String
    private let onTap: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let largeLabelMinScale: CGFloat = 0.7

    init(action: MyListingRowAction, title: String, identifier: String, onTap: @escaping () -> Void) {
        self.action = action
        self.title = title
        self.identifier = identifier
        self.onTap = onTap
    }

    @ViewBuilder
    private var label: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
                .weydaText(.labelMedium)
                .multilineTextAlignment(.center)
                .lineLimit(LabelLines.limit(for: title, maxLines: 3))
                .minimumScaleFactor(Self.largeLabelMinScale)
        } else {
            Text(title)
                .weydaText(.labelMedium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: WeydaSpace.xxs) {
                Image(systemName: action.symbol)
                    .font(.body.weight(.medium))
                    .accessibilityHidden(true)
                label
            }
            .frame(maxWidth: .infinity, minHeight: WeydaSize.touchTarget)
            .padding(.vertical, WeydaSpace.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(action.isDestructive ? WeydaColor.error : WeydaColor.primary)
        .accessibilityIdentifier(identifier)
    }
}

/// Haut de la carte d'une annonce du membre : vignette, statut, titre, prix, vues et ancienneté ; note de
/// modération dessous. Une seule entité pour VoiceOver. Très grand texte : vignette AU-DESSUS du texte (comme
/// `ListingRow`), titre sur 3 lignes, vues et ancienneté entières.
private struct MyListingRow: View {
    private let listing: Listing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(listing: Listing) {
        self.listing = listing
    }

    var body: some View {
        let reasons = MyListingsText.moderationReasons(for: listing)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(WeydaSpace.sm)
            if !reasons.isEmpty {
                MyListingModerationNote(reasons: reasons)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MyListingsText.accessibilityLabel(for: listing))
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WeydaSpace.sm) {
                MyListingThumbnail(listing: listing)
                details
            }
        } else {
            HStack(alignment: .top, spacing: WeydaSpace.md) {
                MyListingThumbnail(listing: listing)
                details
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            MyListingStatusBadge(status: listing.listingStatus)
            Text(listing.title)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(titleLines)
            PriceText(price: listing.price, priceType: listing.priceType)
            meta
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var meta: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(MyListingsText.meta(for: listing))
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(MyListingsText.meta(for: listing))
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .lineLimit(1)
        }
    }

    private var titleLines: Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 2
    }
}

/// Vignette 116 × 92 (comme `ListingRow`) ; sans photo, un pictogramme sur le fond d'attente.
private struct MyListingThumbnail: View {
    let listing: Listing

    var body: some View {
        Group {
            if listing.coverImage == nil {
                ZStack {
                    WeydaPalette.imagePlaceholder
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                }
            } else {
                RemoteImage(urlString: listing.coverThumbnail, fallbackURLString: listing.coverImage)
            }
        }
        .frame(width: WeydaSize.rowThumbWidth, height: WeydaSize.rowThumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Pastille de statut — couples fond / texte du thème (Android : un blanc en dur tombait à 1,7:1 sur les teintes
/// claires du mode sombre).
private struct MyListingStatusBadge: View {
    let status: ListingStatus

    var body: some View {
        Text(MyListingsText.statusTitle(status))
            .weydaText(.labelSmall)
            .fontWeight(.bold)
            .textCase(.uppercase)
            .foregroundStyle(content)
            .lineLimit(1)
            .padding(.horizontal, WeydaSpace.xs + WeydaSpace.xxs)
            .padding(.vertical, WeydaSpace.xxs)
            .background(container, in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
    }

    private var container: Color {
        switch status {
        case .active: WeydaColor.primary
        case .pending: WeydaColor.tertiary
        case .sold, .expired: WeydaColor.surfaceContainerHigh
        case .rejected: WeydaColor.error
        }
    }

    private var content: Color {
        switch status {
        case .active: WeydaColor.onPrimary
        case .pending: WeydaColor.onTertiary
        case .sold, .expired: WeydaColor.onSurfaceVariant
        case .rejected: WeydaColor.onError
        }
    }
}

/// « Motif de la modération » et ses raisons (3 au plus), sous une annonce refusée, en attente ou expirée.
private struct MyListingModerationNote: View {
    private let reasons: [String]
    /// Puce centrée sur la première ligne du motif, quelle que soit la taille du texte.
    @ScaledMetric(relativeTo: .caption) private var bulletTop: CGFloat = 6

    private static let bulletSide: CGFloat = 4

    init(reasons: [String]) {
        self.reasons = reasons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            HStack(spacing: WeydaSpace.xs) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(L10n.moderationReason)
                    .weydaText(.labelMedium)
            }
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            ForEach(Array(reasons.enumerated()), id: \.offset) { item in
                HStack(alignment: .top, spacing: WeydaSpace.sm) {
                    Circle()
                        .fill(WeydaColor.onSurfaceVariant)
                        .frame(width: Self.bulletSide, height: Self.bulletSide)
                        .padding(.top, bulletTop)
                    Text(item.element)
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.onSurface)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, WeydaSpace.md)
        .padding(.vertical, WeydaSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surfaceContainer)
    }
}
