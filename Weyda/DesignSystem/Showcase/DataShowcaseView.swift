#if DEBUG
import SwiftUI

/// Démonstration de la couche données (Debug seulement), ouverte par `-WeydaScreen data` : catégories et villes
/// populaires chargées par les VRAIS repositories du conteneur — à travers l'API simulée (`-WeydaMockAPI YES`,
/// MockFixtures/catalog) — et six photos fictives servies par le pipeline d'images. Relue dans le tour de captures.
struct DataShowcaseView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var categories: [Category] = []
    @State private var cities: [Wilaya] = []
    @State private var categoriesError: String? = nil
    @State private var citiesError: String? = nil
    @State private var started = false

    /// Photos dessinées par `MockPhotos` (hôte fictif, servi par l'API simulée).
    private static let photoNames = ["car-1", "phone-1", "house-1", "sofa-1", "laptop-1", "bike-1"]

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WeydaSpace.section) {
                categoriesSection
                citiesSection
                photosSection
            }
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.lg)
        }
        .background(WeydaColor.background)
        .navigationTitle(Text(verbatim: "Données"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.data")
        .task {
            await load()
        }
    }

    // MARK: - Sections

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            sectionTitle(L10n.sectionCategories)
            if let categoriesError {
                errorText(categoriesError)
            } else if categories.isEmpty {
                ProgressView()
            } else {
                LazyVGrid(columns: Self.twoColumns, spacing: WeydaSpace.sm) {
                    ForEach(categories) { category in
                        categoryCell(category)
                    }
                }
            }
        }
    }

    private var citiesSection: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            sectionTitle(L10n.sectionPopularCities)
            if let citiesError {
                errorText(citiesError)
            } else if cities.isEmpty {
                ProgressView()
            } else {
                LazyVGrid(columns: Self.twoColumns, spacing: WeydaSpace.sm) {
                    ForEach(cities) { wilaya in
                        cityCell(wilaya)
                    }
                }
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            sectionTitle("Photos (RemoteImage)")
            LazyVGrid(columns: Self.twoColumns, spacing: WeydaSpace.sm) {
                ForEach(Self.photoNames, id: \.self) { name in
                    RemoteImage(urlString: "https://photos.mock.weydaa/annonces/\(name).webp", pipeline: container.images)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
                }
            }
            .accessibilityIdentifier("data.photos")
        }
    }

    // MARK: - Cellules

    private static let twoColumns: [GridItem] = [
        GridItem(.flexible(), spacing: WeydaSpace.sm),
        GridItem(.flexible(), spacing: WeydaSpace.sm),
    ]

    private func categoryCell(_ category: Category) -> some View {
        HStack(spacing: WeydaSpace.sm) {
            CategoryIconImage(assetName: CategoryIcon.assetName(forSlug: category.slug))
                .foregroundStyle(WeydaColor.onPrimaryContainer)
                .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                .background(WeydaColor.primaryContainer, in: RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous))
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(category.name.resolve())
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(2)
                Text(L10n.resultsCount(category.listingsCount))
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(WeydaSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surface, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("data.category.\(category.slug)")
    }

    private func cityCell(_ wilaya: Wilaya) -> some View {
        HStack(spacing: WeydaSpace.sm) {
            CategoryIconImage(assetName: CategoryIcon.place)
                .foregroundStyle(WeydaColor.primary)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(wilaya.name.resolve())
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(1)
                Text(L10n.resultsCount(wilaya.listingsCount))
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(WeydaSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surface, in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("data.city.\(wilaya.id)")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .weydaText(.titleMedium)
            .foregroundStyle(WeydaColor.onBackground)
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .weydaText(.bodyMedium)
            .foregroundStyle(WeydaColor.error)
    }

    // MARK: - Chargement

    private func load() async {
        guard !started else { return }
        started = true
        do {
            categories = try await container.categories.roots()
        } catch {
            categoriesError = ErrorMapper.message(for: error) ?? L10n.errorGeneric
        }
        do {
            cities = try await container.geo.topWilayas(limit: 10)
        } catch {
            citiesError = ErrorMapper.message(for: error) ?? L10n.errorGeneric
        }
    }
}
#endif
