#if DEBUG
import SwiftUI

/// Démonstration du système de design (Debug seulement) : marque, couleurs, typographie, icônes,
/// rayons, contrôles, puis les composants communs (`ComponentsShowcase`). Sert à relire les tokens et
/// les composants dans les captures automatiques, en clair / sombre et dans les trois langues. Les
/// libellés techniques (noms de tokens) sont en `verbatim` : cet écran n'existe pas dans l'app publiée.
struct DesignShowcaseView: View {
    /// `-WeydaScreen components` : la section « Composants » seule (captures `92-components-*`).
    private let componentsOnly: Bool

    init(componentsOnly: Bool = false) {
        self.componentsOnly = componentsOnly
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeydaSpace.section) {
                if !componentsOnly {
                    brand
                    colors
                    typography
                    icons
                    radii
                    controls
                }
                components
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.lg)
        }
        .background(WeydaColor.background)
        .navigationTitle(Text(verbatim: componentsOnly ? "Components" : "Design system"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(componentsOnly ? "screen.components" : "screen.showcase")
    }

    // MARK: Sections

    private var brand: some View {
        ShowcaseSection(title: "Marque") {
            HStack(spacing: WeydaSpace.lg) {
                WeydaTile(size: 72)
                ZStack {
                    RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
                        .fill(WeydaColor.primary)
                    WeydaMarkExtruded(size: 48)
                }
                .frame(width: 72, height: 72)
                WeydaLoader()
                    .frame(width: 48, height: 48)
            }
            WeydaWordmark(color: WeydaColor.onBackground)
            Text(L10n.tagline)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        }
    }

    private var colors: some View {
        ShowcaseSection(title: "Couleurs") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: WeydaSpace.sm)], spacing: WeydaSpace.sm) {
                ForEach(Self.swatches, id: \.name) { swatch in
                    VStack(alignment: .leading, spacing: WeydaSpace.xs) {
                        RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous)
                            .fill(swatch.color)
                            .frame(height: 40)
                            .overlay {
                                RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous)
                                    .strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
                            }
                        Text(verbatim: swatch.name)
                            .weydaText(.labelSmall)
                            .foregroundStyle(WeydaColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var typography: some View {
        ShowcaseSection(title: "Typographie") {
            ForEach(WeydaTextStyle.allCases, id: \.self) { style in
                Text(style == .price || style == .priceLarge ? L10n.priceDzd("12 500") : L10n.sectionFeatured)
                    .weydaText(style)
                    .foregroundStyle(WeydaColor.onBackground)
            }
        }
    }

    private var icons: some View {
        ShowcaseSection(title: "Catégories") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: WeydaSize.categoryCell), spacing: WeydaSpace.sm)], spacing: WeydaSpace.md) {
                ForEach(CategoryIcon.knownSlugs + ["all"], id: \.self) { slug in
                    VStack(spacing: WeydaSpace.xs) {
                        Circle()
                            .fill(WeydaPalette.categoryTile)
                            .frame(width: WeydaSize.categoryCircle, height: WeydaSize.categoryCircle)
                            .overlay {
                                CategoryIconImage(
                                    assetName: slug == "all" ? CategoryIcon.all : CategoryIcon.assetName(forSlug: slug),
                                    size: WeydaSize.iconLarge
                                )
                                .foregroundStyle(WeydaColor.primary)
                            }
                        Text(verbatim: slug)
                            .weydaText(.labelSmall)
                            .foregroundStyle(WeydaColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
            }
            HStack(spacing: WeydaSpace.xs) {
                CategoryIconImage(assetName: CategoryIcon.place, size: WeydaSize.icon)
                    .foregroundStyle(WeydaColor.primary)
                Text(verbatim: "Alger")
                    .weydaText(.labelLarge)
            }
            .padding(.horizontal, WeydaSpace.md)
            .padding(.vertical, WeydaSpace.sm)
            .background(WeydaColor.surfaceVariant, in: Capsule())
        }
    }

    private var radii: some View {
        ShowcaseSection(title: "Rayons") {
            HStack(spacing: WeydaSpace.sm) {
                ForEach(Self.radiusSamples, id: \.name) { sample in
                    VStack(spacing: WeydaSpace.xs) {
                        RoundedRectangle(cornerRadius: sample.radius, style: .continuous)
                            .fill(WeydaColor.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: sample.radius, style: .continuous)
                                    .strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
                            }
                            .frame(width: 52, height: 52)
                        Text(verbatim: sample.name)
                            .weydaText(.labelSmall)
                            .foregroundStyle(WeydaColor.onSurfaceVariant)
                    }
                }
            }
        }
    }

    private var components: some View {
        ShowcaseSection(title: "Composants") {
            ComponentsShowcase()
        }
    }

    private var controls: some View {
        ShowcaseSection(title: "Contrôles") {
            Button {} label: {
                // onPrimary : en sombre, le vert clair porte un texte foncé (le blanc par défaut y passe sous 3:1).
                Text(L10n.retry)
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.onPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(WeydaColor.primary)

            Button {} label: {
                Text(L10n.close)
                    .weydaText(.labelLarge)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            HStack(spacing: WeydaSpace.sm) {
                Text(L10n.featuredBadge)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaPalette.onFeatured)
                    .padding(.horizontal, WeydaSpace.sm)
                    .padding(.vertical, WeydaSpace.xxs)
                    .background(WeydaPalette.featured, in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
                Text(L10n.priceNegotiable)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onPrimaryContainer)
                    .padding(.horizontal, WeydaSpace.sm)
                    .padding(.vertical, WeydaSpace.xxs)
                    .background(WeydaColor.primaryContainer, in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
            }
            Text(L10n.resultsCount(2))
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        }
    }

    // MARK: Données

    private struct Swatch {
        let name: String
        let color: Color
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "primary", color: WeydaColor.primary),
        Swatch(name: "primaryContainer", color: WeydaColor.primaryContainer),
        Swatch(name: "secondary", color: WeydaColor.secondary),
        Swatch(name: "tertiary", color: WeydaColor.tertiary),
        Swatch(name: "background", color: WeydaColor.background),
        Swatch(name: "surface", color: WeydaColor.surface),
        Swatch(name: "surfaceVariant", color: WeydaColor.surfaceVariant),
        Swatch(name: "outline", color: WeydaColor.outline),
        Swatch(name: "error", color: WeydaColor.error),
        Swatch(name: "success", color: WeydaPalette.success),
        Swatch(name: "warning", color: WeydaPalette.warning),
        Swatch(name: "featured", color: WeydaPalette.featured),
        Swatch(name: "categoryTile", color: WeydaPalette.categoryTile),
        Swatch(name: "bubbleOwn", color: WeydaPalette.bubbleOwn),
        Swatch(name: "bubbleOther", color: WeydaPalette.bubbleOther),
        Swatch(name: "skeleton", color: WeydaPalette.skeleton),
    ]

    private struct RadiusSample {
        let name: String
        let radius: CGFloat
    }

    private static let radiusSamples: [RadiusSample] = [
        RadiusSample(name: "badge", radius: WeydaRadius.badge),
        RadiusSample(name: "thumb", radius: WeydaRadius.thumb),
        RadiusSample(name: "card", radius: WeydaRadius.card),
        RadiusSample(name: "panel", radius: WeydaRadius.panel),
        RadiusSample(name: "sheet", radius: WeydaRadius.sheet),
    ]
}

/// Une section de la démonstration : titre technique + contenu.
private struct ShowcaseSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            Text(verbatim: title)
                .weydaText(.titleMedium)
                .foregroundStyle(WeydaColor.onBackground)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
