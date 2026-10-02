import SwiftUI

/*
 * Les cartes d'annonce — portage de `components/ListingCards.kt` (Android), mêmes partis pris :
 *  1. PAS D'OMBRE : surface sur le fond de l'écran + filet de 1 pt (vingt ombres à redessiner à chaque image
 *     de défilement pour rien) ;
 *  2. LE PRIX D'ABORD : style typographique propre, couleur de la marque ;
 *  3. VUES PURES : la carte ne navigue pas, l'écran l'enveloppe dans un `NavigationLink(value:)` (avec
 *     `.buttonStyle(.weydaCard)` pour l'appui). Le cœur est un bouton à part, qui gagne l'appui.
 * VoiceOver : une carte = UN élément (titre, prix, lieu, ancienneté, « À la une ») ; le favori est aussi une
 * action de cet élément (rotor), car dans un lien les boutons imbriqués ne sont pas atteignables.
 */

/// Carte verticale (grille de l'accueil) : photo 4:3, titre sur 2 lignes, prix, lieu et ancienneté.
/// Photo COMPLÈTE (comme Android) : sur un écran 3x, la miniature 400 px d'une carte de 170 à 230 pt serait floue.
struct ListingCard: View {
    private let listing: Listing
    private let isFavorite: Bool?
    private let onFavorite: (() -> Void)?

    /// `onFavorite` nil = pas de cœur (visiteur, démonstration) ; `isFavorite` nil = pas encore connu (cœur vide).
    init(listing: Listing, isFavorite: Bool? = nil, onFavorite: (() -> Void)? = nil) {
        self.listing = listing
        self.isFavorite = isFavorite
        self.onFavorite = onFavorite
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ListingCoverImage(url: listing.coverImage)
                .overlay(alignment: .topLeading) {
                    if listing.isFeatured {
                        FeaturedBadge()
                            .padding(WeydaSpace.sm)
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(listing.title)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                // Mention « Négociable » retirée si elle ne tient pas à côté du prix : toutes les cartes d'une
                // rangée gardent la même hauteur (VoiceOver la lit toujours).
                PriceText(price: listing.price, priceType: listing.priceType, style: .price, overflow: .drop)
                    .padding(.top, WeydaSpace.sm)
                ListingMetaLine(listing: listing)
                    .padding(.top, WeydaSpace.xs)
            }
            .padding(WeydaSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listingAccessibility(listing, isFavorite: isFavorite ?? false, onFavorite: onFavorite)
        .background(WeydaColor.surface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let onFavorite {
                FavoriteButton(isFavorite: isFavorite ?? false, onPhoto: true, action: onFavorite)
                    .padding(WeydaSpace.xxs)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .contain)
    }
}

/// Carte du carrousel « À la une » : la carte de grille, à largeur fixe (≈ 70 % d'un iPhone, comme le site).
struct ListingCarouselCard: View {
    private let listing: Listing
    private let isFavorite: Bool?
    private let onFavorite: (() -> Void)?

    init(listing: Listing, isFavorite: Bool? = nil, onFavorite: (() -> Void)? = nil) {
        self.listing = listing
        self.isFavorite = isFavorite
        self.onFavorite = onFavorite
    }

    var body: some View {
        ListingCard(listing: listing, isFavorite: isFavorite, onFavorite: onFavorite)
            .frame(width: WeydaSize.carouselCard)
    }
}

/// Ligne de résultat (Annonces, vitrine du vendeur, favoris) : miniature au début, texte ensuite, cœur au bout.
/// Hauteur MINIMALE = celle de la vignette, jamais figée (texte agrandi : rien n'est rogné).
struct ListingRow: View {
    private let listing: Listing
    private let isFavorite: Bool?
    private let onFavorite: (() -> Void)?

    init(listing: Listing, isFavorite: Bool? = nil, onFavorite: (() -> Void)? = nil) {
        self.listing = listing
        self.isFavorite = isFavorite
        self.onFavorite = onFavorite
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        HStack(alignment: .top, spacing: WeydaSpace.xxs) {
            HStack(alignment: .top, spacing: WeydaSpace.md) {
                thumbnail
                details
            }
            // Le texte prend la hauteur de la ligne : prix et lieu se calent en bas, face au bas de la vignette.
            .fixedSize(horizontal: false, vertical: true)
            .listingAccessibility(listing, isFavorite: isFavorite ?? false, onFavorite: onFavorite)
            if let onFavorite {
                FavoriteButton(isFavorite: isFavorite ?? false, action: onFavorite)
            }
        }
        .padding(WeydaSpace.sm)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .contain)
    }

    private var thumbnail: some View {
        Group {
            if listing.coverImage == nil {
                NoPhoto()
            } else {
                RemoteImage(urlString: listing.coverThumbnail, fallbackURLString: listing.coverImage)
            }
        }
        .frame(width: WeydaSize.rowThumbWidth, height: WeydaSize.rowThumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
        .overlay(alignment: .topLeading) {
            if listing.isFeatured {
                // Sur une vignette de 116 pt, le libellé mangerait un tiers de la photo : l'étoile suffit.
                FeaturedBadge(compact: true)
                    .padding(WeydaSpace.xs)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(listing.title)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: WeydaSpace.sm)
            PriceText(price: listing.price, priceType: listing.priceType)
            ListingMetaLine(listing: listing)
                .padding(.top, WeydaSpace.xxs)
        }
        .frame(maxWidth: .infinity, minHeight: WeydaSize.rowThumbHeight, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Cœur favori. Sur une photo, il est posé sur une PASTILLE BLANCHE cerclée d'un filet (une photo d'annonce
/// est le plus souvent claire : un disque sombre y faisait une tache). Passer en favori fait rebondir le cœur
/// (iOS 17+, sauf « Réduire les animations ») — retour immédiat, avant la réponse du serveur. Cible 44 pt.
struct FavoriteButton: View {
    private let isFavorite: Bool
    private let onPhoto: Bool
    private let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops: Int = 0
    @State private var settled: Bool = false

    /// Cœur seul (ligne de résultat, barre d'outils).
    init(isFavorite: Bool, action: @escaping () -> Void) {
        self.init(isFavorite: isFavorite, onPhoto: false, action: action)
    }

    /// `onPhoto` : pastille blanche, lisible sur n'importe quelle photo (cartes, galerie).
    init(isFavorite: Bool, onPhoto: Bool, action: @escaping () -> Void) {
        self.isFavorite = isFavorite
        self.onPhoto = onPhoto
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            heart
                .frame(width: FavoritePill.side, height: FavoritePill.side)
                .background {
                    if onPhoto {
                        Circle()
                            .fill(FavoritePill.fill)
                            .overlay {
                                Circle().strokeBorder(FavoritePill.stroke, lineWidth: 1)
                            }
                    }
                }
                .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? L10n.favoriteRemove : L10n.favoriteAdd)
        .task(id: isFavorite) {
            // Premier passage = l'état initial (cellule qui apparaît) : pas de rebond.
            if settled && isFavorite {
                pops += 1
            }
            settled = true
        }
    }

    @ViewBuilder
    private var heart: some View {
        let glyph = Image(systemName: isFavorite ? "heart.fill" : "heart")
            .font(.system(size: FavoritePill.glyph, weight: .semibold))
            .foregroundStyle(tint)
        if #available(iOS 17.0, *) {
            if reduceMotion {
                glyph
            } else {
                glyph.symbolEffect(.bounce, value: pops)
            }
        } else {
            glyph
        }
    }

    private var tint: Color {
        if isFavorite { return WeydaColor.secondary }
        return onPhoto ? FavoritePill.idle : WeydaColor.onSurfaceVariant
    }
}

/// Pastille du cœur sur photo : toujours blanche (elle se pose sur une photo, pas sur le thème). Valeurs
/// d'Android (`Color.White` 92 %, filet Slate200, cœur Slate700) — candidates pour `WeydaPalette`.
private enum FavoritePill {
    static let side: CGFloat = WeydaSize.touchTarget - WeydaSpace.md
    static let glyph: CGFloat = WeydaSize.icon - WeydaSpace.xxs
    static let fill = Color(rgb: WeydaRamp.white, opacity: 0.92)
    static let stroke = Color(rgb: WeydaRamp.slate200, opacity: 0.9)
    static let idle = Color(rgb: WeydaRamp.slate700)
}

/// Pastille « À la une » — ambre, pas rouge : le rouge de la marque signale l'urgence et les actions
/// destructrices, une mise en avant relève du doré (convention des places de marché).
struct FeaturedBadge: View {
    private let compact: Bool

    init() {
        self.compact = false
    }

    /// `compact` : l'étoile seule (vignette d'une ligne), le libellé reste lu par VoiceOver.
    init(compact: Bool) {
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: WeydaSpace.xxs) {
            Image(systemName: "star.fill")
                .font(.caption2.weight(.bold))
            if !compact {
                Text(L10n.featuredBadge)
                    .weydaText(.labelSmall)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(WeydaPalette.onFeatured)
        .padding(.horizontal, compact ? WeydaSpace.xs : WeydaSpace.sm)
        .padding(.vertical, WeydaSpace.xxs + 1)
        .background(WeydaPalette.featured, in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.featuredBadge)
    }
}

/// Prix (« 12 500 DA », « Gratuit », « Prix sur demande » : `Format.price`) + mention « Négociable » à côté.
/// Si la mention ne tient pas sur la ligne, elle passe dessous (Android : FlowRow) — dans une ligne de résultat,
/// la colonne de texte est étroite.
struct PriceText: View {
    private let price: Double?
    private let priceType: PriceType
    private let style: WeydaTextStyle
    private let overflow: PriceOverflow

    init(price: Double?, priceType: PriceType, style: WeydaTextStyle = .price) {
        self.init(price: price, priceType: priceType, style: style, overflow: .wrap)
    }

    init(price: Double?, priceType: PriceType, style: WeydaTextStyle, overflow: PriceOverflow) {
        self.price = price
        self.priceType = priceType
        self.style = style
        self.overflow = overflow
    }

    var body: some View {
        let amount = Format.price(price, type: priceType)
        let mention = Format.negotiableLabel(price: price, type: priceType)
        Group {
            if let mention {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                        amountText(amount)
                        mentionText(mention)
                    }
                    if overflow == .wrap {
                        VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                            amountText(amount)
                            mentionText(mention)
                        }
                    } else {
                        amountText(amount)
                    }
                }
            } else {
                amountText(amount)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mention.map { "\(amount), \($0)" } ?? amount)
    }

    private func amountText(_ text: String) -> some View {
        Text(text)
            .weydaText(style)
            .foregroundStyle(WeydaColor.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func mentionText(_ text: String) -> some View {
        Text(text)
            .weydaText(.labelSmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Mention « Négociable » trop large pour la ligne du prix : dessous (`wrap`) ou retirée (`drop`, cartes d'une
/// grille à hauteur égale — VoiceOver la lit toujours).
nonisolated enum PriceOverflow: Sendable {
    case wrap
    case drop
}

/// Lieu de l'annonce : « Bab Ezzouar, Alger » (commune puis wilaya, dans la langue de l'app), épingle devant.
/// Rien du tout si aucun des deux n'est connu.
struct LocationLine: View {
    private let wilaya: LocalizedName?
    private let commune: LocalizedName?
    @ScaledMetric(relativeTo: .caption) private var pinSide: CGFloat = 14

    init(wilaya: LocalizedName?, commune: LocalizedName?) {
        self.wilaya = wilaya
        self.commune = commune
    }

    var body: some View {
        if let place = ListingText.place(wilaya: wilaya, commune: commune) {
            HStack(spacing: WeydaSpace.xs) {
                CategoryIconImage(assetName: CategoryIcon.place, size: pinSide)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                Text(place)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Photo d'annonce au format 4:3, sur le fond d'attente ; sans photo : un pictogramme, jamais un trou blanc.
struct ListingCoverImage: View {
    private let url: String?
    private let fallbackURL: String?

    init(url: String?, fallbackURL: String? = nil) {
        self.url = url
        self.fallbackURL = fallbackURL
    }

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                if url == nil {
                    NoPhoto()
                } else {
                    RemoteImage(urlString: url, fallbackURLString: fallbackURL)
                }
            }
            .clipped()
    }
}

/// Annonce sans photo.
private struct NoPhoto: View {
    var body: some View {
        ZStack {
            WeydaPalette.imagePlaceholder
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        }
        .accessibilityHidden(true)
    }
}

/// « Bab Ezzouar, Alger · il y a 2 h » sous le prix (lieu et ancienneté, les morceaux vides disparaissent).
private struct ListingMetaLine: View {
    let listing: Listing

    var body: some View {
        Text(ListingText.meta(for: listing))
            .weydaText(.bodySmall)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
            .lineLimit(1)
    }
}

/// Textes d'une annonce partagés par les cartes et les lignes. Logique pure, testable.
nonisolated enum ListingText {
    /// « Bab Ezzouar, Alger » (commune puis wilaya) ; virgule arabe en arabe ; nil si aucun des deux.
    static func place(wilaya: LocalizedName?, commune: LocalizedName?, language: String = WeydaLocale.language) -> String? {
        let parts = [commune, wilaya]
            .compactMap { $0?.resolve(language) }
            .filter { !TextCheck.isBlank($0) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: language == "ar" ? "، " : ", ")
    }

    /// Lieu et ancienneté : « Bab Ezzouar, Alger · il y a 2 h ».
    static func meta(for listing: Listing, now: Date = Date(), language: String = WeydaLocale.language) -> String {
        let location: String? = place(wilaya: listing.wilaya, commune: listing.commune, language: language)
        let age: String? = TextCheck.nonBlank(Format.relativeTime(listing.createdAt, now: now))
        return [location, age].compactMap { $0 }.joined(separator: " · ")
    }

    /// Ce que VoiceOver lit pour une carte : titre, prix (+ « Négociable »), lieu, ancienneté, « À la une ».
    static func accessibilityLabel(for listing: Listing, now: Date = Date(), language: String = WeydaLocale.language) -> String {
        var parts: [String] = [listing.title, Format.price(listing.price, type: listing.priceType)]
        if let mention = Format.negotiableLabel(price: listing.price, type: listing.priceType) {
            parts.append(mention)
        }
        if let location = place(wilaya: listing.wilaya, commune: listing.commune, language: language) {
            parts.append(location)
        }
        if let age = TextCheck.nonBlank(Format.relativeTime(listing.createdAt, now: now)) {
            parts.append(age)
        }
        if listing.isFeatured {
            parts.append(L10n.featuredBadge)
        }
        return parts.joined(separator: ", ")
    }
}

extension View {
    /// Une annonce = UN élément VoiceOver ; le favori y est aussi une action (rotor « Actions »).
    func listingAccessibility(_ listing: Listing, isFavorite: Bool, onFavorite: (() -> Void)?) -> some View {
        modifier(ListingAccessibility(listing: listing, isFavorite: isFavorite, onFavorite: onFavorite))
    }
}

private struct ListingAccessibility: ViewModifier {
    let listing: Listing
    let isFavorite: Bool
    let onFavorite: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        let element = content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ListingText.accessibilityLabel(for: listing))
        if let onFavorite {
            element.accessibilityAction(named: Text(isFavorite ? L10n.favoriteRemove : L10n.favoriteAdd)) {
                onFavorite()
            }
        } else {
            element
        }
    }
}
