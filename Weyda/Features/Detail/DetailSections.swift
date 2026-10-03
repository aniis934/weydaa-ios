import SwiftUI

// Sections de la fiche — portage des blocs de `DetailContent` (DetailScreen.kt) : bandeau d'état, vendeur, avis,
// conseils de sécurité, annonces similaires, barre d'actions du bas.

// MARK: - Bandeau d'état

/// Annonce hors ligne (mêmes textes que le site) : en vérification, refusée, vendue, expirée — `ListingStatusBanner`
/// (Android). Le propriétaire peut modifier une annonce refusée ou expirée pour la republier.
struct DetailStatusBanner: View {
    private let status: ListingStatus
    private let isOwner: Bool
    private let onEdit: () -> Void

    init(status: ListingStatus, isOwner: Bool, onEdit: @escaping () -> Void) {
        self.status = status
        self.isOwner = isOwner
        self.onEdit = onEdit
    }

    var body: some View {
        if let content = DetailStatusContent(status: status) {
            HStack(alignment: .center, spacing: WeydaSpace.md) {
                Image(systemName: content.symbol)
                    .font(.title3)
                    .foregroundStyle(foreground)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                    Text(content.title)
                        .weydaText(.titleSmall)
                        .foregroundStyle(foreground)
                    Text(content.message)
                        .weydaText(.bodySmall)
                        .foregroundStyle(foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if isOwner && content.isEditable {
                    Button(L10n.myListingEdit, action: onEdit)
                        .buttonStyle(.bordered)
                        .tint(foreground)
                        .controlSize(.small)
                }
            }
            .padding(WeydaSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.status")
        }
    }

    private var background: Color {
        switch status {
        case .pending: WeydaColor.tertiaryContainer
        case .rejected: WeydaColor.errorContainer
        default: WeydaColor.surfaceVariant
        }
    }

    private var foreground: Color {
        switch status {
        case .pending: WeydaColor.onTertiaryContainer
        case .rejected: WeydaColor.onErrorContainer
        default: WeydaColor.onSurfaceVariant
        }
    }
}

/// Textes et pictogramme du bandeau (logique pure) ; nil pour une annonce en ligne.
nonisolated struct DetailStatusContent: Equatable, Sendable {
    let title: String
    let message: String
    let symbol: String
    /// Le propriétaire peut la corriger et la republier.
    let isEditable: Bool

    init?(status: ListingStatus) {
        switch status {
        case .active:
            return nil
        case .pending:
            self.init(title: L10n.detailStatusPending, message: L10n.detailStatusPendingDesc, symbol: "hourglass", isEditable: false)
        case .rejected:
            self.init(title: L10n.detailStatusRejected, message: L10n.detailStatusRejectedDesc, symbol: "exclamationmark.octagon", isEditable: true)
        case .sold:
            self.init(title: L10n.detailStatusSold, message: L10n.detailStatusSoldDesc, symbol: "checkmark.seal", isEditable: false)
        case .expired:
            self.init(title: L10n.detailStatusExpired, message: L10n.detailStatusExpiredDesc, symbol: "clock", isEditable: true)
        }
    }

    init(title: String, message: String, symbol: String, isEditable: Bool) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.isEditable = isEditable
    }
}

// MARK: - Vendeur

/// Carte du vendeur : portrait, nom, ancienneté, annonces en ligne, note et badges ; elle ouvre sa vitrine, comme
/// le lien `/profil/{id}` du site.
struct DetailSellerCard: View {
    private let seller: Seller
    private let action: () -> Void

    init(seller: Seller, action: @escaping () -> Void) {
        self.seller = seller
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: WeydaSpace.md) {
                HStack(alignment: .center, spacing: WeydaSpace.md) {
                    SellerAvatar(url: seller.avatarUrl, size: WeydaSize.touchTarget)
                    identity
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WeydaColor.outline)
                        .accessibilityHidden(true)
                }
                if !TrustBadge.badges(for: seller).isEmpty {
                    TrustBadges(seller: seller)
                }
            }
            .padding(WeydaSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.weydaCard)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("detail.seller")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
            Text(TextCheck.ifBlank(seller.name, "—"))
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
                .lineLimit(1)
            if let meta = DetailText.sellerMeta(seller) {
                Text(meta)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(2)
            }
            if let rating = seller.rating {
                Text(L10n.sellerRating(rating, seller.ratingCount))
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.primary)
                    .accessibilityLabel(DetailRatingText.spoken(rating, count: seller.ratingCount))
            }
        }
    }
}

// MARK: - Avis

/// Avis du vendeur sur la fiche : moyenne du serveur et 3 premiers avis (ou « Aucun avis pour le moment »).
struct DetailReviewsSection: View {
    private let summary: ReviewSummary

    init(summary: ReviewSummary) {
        self.summary = summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            ReviewsHeader(summary: summary)
            if summary.reviews.isEmpty {
                Text(L10n.reviewsEmpty)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            } else {
                ForEach(summary.reviews) { review in
                    ReviewCard(review: review)
                }
            }
        }
    }
}

// MARK: - Conseils de sécurité

/// Conseils du site (échange en main propre, jamais de paiement à l'avance…), montrés aux acheteurs seulement.
struct DetailSafetyTips: View {
    private static let tips: [String] = [
        L10n.detailSafetyTip1,
        L10n.detailSafetyTip2,
        L10n.detailSafetyTip3,
        L10n.detailSafetyTip4,
    ]

    init() {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            Label {
                Text(L10n.detailSafetyTitle)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(WeydaColor.primary)
            }
            VStack(alignment: .leading, spacing: WeydaSpace.xs) {
                ForEach(Self.tips, id: \.self) { tip in
                    Text(L10n.detailSafetyBullet(tip))
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(WeydaSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surfaceContainer, in: shape)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Annonces similaires

/// Carrousel « Annonces similaires » (même catégorie) ; chaque carte ouvre sa fiche sur la même pile.
struct DetailSimilarSection: View {
    private let listings: [Listing]

    init(listings: [Listing]) {
        self.listings = listings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L10n.detailSimilar)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: WeydaSpace.gutter) {
                    ForEach(listings) { listing in
                        NavigationLink(value: AppRoute.detail(idOrSlug: listing.id)) {
                            ListingCarouselCard(listing: listing)
                        }
                        .buttonStyle(.weydaCard)
                    }
                }
                .padding(.horizontal, WeydaSpace.screen)
                .padding(.vertical, WeydaSpace.xs)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.similar")
    }
}

// MARK: - Barre d'actions

/// Barre du bas — celle d'Android : « Faire une offre » sur toute la largeur, puis le numéro et « Contacter le
/// vendeur » (ou « Modifier » pour le propriétaire). Rien du tout pour une annonce vendue ou expirée.
struct DetailActionBar: View {
    private let state: DetailState
    private let onOffer: () -> Void
    private let onPhone: () -> Void
    private let onEdit: () -> Void
    private let onContact: () -> Void

    init(
        state: DetailState,
        onOffer: @escaping () -> Void,
        onPhone: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onContact: @escaping () -> Void
    ) {
        self.state = state
        self.onOffer = onOffer
        self.onPhone = onPhone
        self.onEdit = onEdit
        self.onContact = onContact
    }

    var body: some View {
        VStack(spacing: WeydaSpace.sm) {
            if state.canMakeOffer {
                Button(action: onOffer) {
                    DetailBarLabel(title: L10n.offerMake, systemImage: "tag")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("detail.offer")
            }
            HStack(spacing: WeydaSpace.md) {
                if state.canShowPhone {
                    phoneButton
                }
                if state.canEdit {
                    Button(action: onEdit) {
                        DetailBarLabel(title: L10n.myListingEdit, systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("detail.edit")
                }
                if state.canContact {
                    Button(action: onContact) {
                        DetailBarLabel(title: L10n.detailContact, systemImage: "envelope")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("detail.contact")
                }
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .tint(WeydaColor.primary)
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.top, WeydaSpace.md)
        .padding(.bottom, WeydaSpace.sm)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// « Afficher le numéro », puis le numéro lui-même : le toucher appelle.
    private var phoneButton: some View {
        Button(action: onPhone) {
            ZStack {
                if state.isRevealingPhone {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let phone = state.revealedPhone {
                    DetailBarLabel(title: Format.ltrIsolate(phone), systemImage: "phone.fill")
                } else {
                    DetailBarLabel(title: L10n.detailShowPhone, systemImage: "phone")
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(state.isRevealingPhone)
        .accessibilityIdentifier("detail.phone")
    }
}

/// Libellé d'un bouton de la barre : pictogramme et texte sur une ligne, toute la largeur du bouton.
private struct DetailBarLabel: View {
    let title: String
    let systemImage: String

    // Icône + texte quand la place suffit ; sinon le texte seul (« Contacter le vendeur » sur un iPhone 6,1"
    // en français), réduit au besoin plutôt que tronqué.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: systemImage)
            Text(title)
        }
        .weydaText(.labelLarge)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Textes

/// Lignes de texte de la fiche (logique pure, testée).
nonisolated enum DetailText {
    /// « Publiée il y a 2 h · 1 234 vues ».
    static func postedLine(_ listing: Listing, now: Date = Date()) -> String {
        var parts: [String] = []
        if listing.createdAt != nil {
            parts.append(L10n.detailPosted(Format.relativeTime(listing.createdAt, now: now)))
        }
        parts.append(L10n.detailViews(listing.views))
        return parts.joined(separator: " · ")
    }

    /// « Expire le 12 nov. 2026 · Référence ABCD1234 » (8 derniers caractères de l'id, comme la fiche du site).
    static func referenceLine(_ listing: Listing) -> String {
        var parts: [String] = []
        if let expiresAt = listing.expiresAt {
            parts.append(L10n.detailExpiresOn(Format.date(expiresAt)))
        }
        parts.append(L10n.detailReference(reference(of: listing.id)))
        return parts.joined(separator: " · ")
    }

    /// Référence lue de gauche à droite même en arabe.
    static func reference(of id: String) -> String {
        Format.ltrIsolate(String(id.suffix(8)).uppercased())
    }

    /// « Membre depuis mai 2024 · 14 annonces en ligne » ; nil si rien n'est connu.
    static func sellerMeta(_ seller: Seller) -> String? {
        var parts: [String] = []
        if let since = seller.memberSince {
            parts.append(L10n.memberSince(Format.monthYear(since)))
        }
        if seller.activeListings > 0 {
            parts.append(L10n.sellerListings(seller.activeListings))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
