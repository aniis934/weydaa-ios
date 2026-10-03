import SwiftUI
import UIKit

/// Feuille de filtres — portage de `FiltersSheet.kt` (miroir de FilterSidebar du site) : sous-catégorie, tri,
/// localisation (wilaya puis commune), type de prix et fourchette, « À la une seulement », attributs de la catégorie
/// (plages, oui / non) et facettes (valeurs comptées par le serveur ; un select dépendant, comme le modèle, n'apparaît
/// qu'une fois la marque choisie). Travaille sur un brouillon : « Voir les résultats » l'applique et relance la
/// recherche ; « Réinitialiser » vide le brouillon. Formulaire iOS natif (sections, sélecteurs poussés).
struct FiltersSheet: View {
    private let state: ListingsState
    private let onDismiss: () -> Void
    private let onApply: (ListingFilters) -> Void
    private let onWilayaChange: (Int?) -> Void
    private let onDraftAttributesChange: (String?, [String: String]) -> Void
    @State private var draft: ListingFilters

    init(
        state: ListingsState,
        onDismiss: @escaping () -> Void,
        onApply: @escaping (ListingFilters) -> Void,
        onWilayaChange: @escaping (Int?) -> Void,
        onDraftAttributesChange: @escaping (String?, [String: String]) -> Void
    ) {
        self.state = state
        self.onDismiss = onDismiss
        self.onApply = onApply
        self.onWilayaChange = onWilayaChange
        self.onDraftAttributesChange = onDraftAttributesChange
        _draft = State(initialValue: state.filters)
    }

    /// Chiffres saisis au plus : prix (Android : 10), bornes d'attribut (9).
    private static let priceDigits = 10
    private static let rangeDigits = 9
    private static let priceTypes: [PriceType] = [.fixed, .negotiable, .free]

    var body: some View {
        NavigationStack {
            Form {
                subcategorySection
                sortSection
                locationSection
                priceSection
                featuredSection
                rangeSections
                booleanSections
                facetSections
            }
            .tint(WeydaColor.primary)
            .scrollContentBackground(.hidden)
            .background(WeydaColor.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.filtersTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyBar
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.filters")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            onDraftAttributesChange(draft.subcategory, draft.attributes)
        }
        .onChange(of: draft.attributes) { attributes in
            onDraftAttributesChange(draft.subcategory, attributes)
        }
        .onChange(of: draft.wilayaId) { wilayaId in
            // Nouvelle wilaya : la commune d'avant ne vaut plus, les communes de la nouvelle sont chargées.
            draft.communeId = nil
            onWilayaChange(wilayaId)
        }
    }

    // MARK: - Barre d'outils, bouton d'application

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.close, action: onDismiss)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(L10n.filtersReset) {
                draft = ListingFilters()
                onWilayaChange(nil)
            }
            .accessibilityIdentifier("filters.reset")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                Self.hideKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .accessibilityLabel(L10n.close)
        }
    }

    private var applyBar: some View {
        Button {
            onApply(draft)
        } label: {
            Text(L10n.filtersApply)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onPrimary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        .accessibilityIdentifier("filters.apply")
        .padding(.horizontal, WeydaSpace.screen)
        .padding(.vertical, WeydaSpace.md)
        .background(WeydaColor.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WeydaColor.outlineVariant)
                .frame(height: 1)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var subcategorySection: some View {
        let subcategories: [Category] = state.selectedCategory?.children ?? []
        if !subcategories.isEmpty {
            Section {
                FilterChipsRow {
                    WeydaChip(
                        title: L10n.filtersAll,
                        isSelected: draft.subcategory == nil,
                        action: { selectSubcategory(nil) }
                    )
                    ForEach(subcategories) { subcategory in
                        WeydaChip(
                            title: subcategory.name.resolve(),
                            isSelected: draft.subcategory == subcategory.slug,
                            action: { selectSubcategory(subcategory.slug) }
                        )
                    }
                }
            } header: {
                Text(L10n.filtersSubcategories)
            }
            .listRowBackground(WeydaColor.surface)
        }
    }

    /// Tri : menu natif (Android : puces) ; « Pertinence » en tête avec un mot-clé.
    private var sortSection: some View {
        let hasQuery = state.hasQuery
        let current = ListingSort(rawValue: draft.sort ?? "") ?? ListingSort.defaultSort(hasQuery: hasQuery)
        return Section {
            Menu {
                ForEach(ListingSort.options(hasQuery: hasQuery), id: \.self) { option in
                    Button {
                        draft.sort = option.rawValue
                    } label: {
                        if option == current {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: WeydaSpace.sm) {
                    Text(L10n.filtersSort)
                        .foregroundStyle(WeydaColor.onSurface)
                    Spacer(minLength: WeydaSpace.sm)
                    Text(current.title)
                        .foregroundStyle(WeydaColor.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
                .weydaText(.bodyLarge)
                .frame(minHeight: WeydaSize.touchTarget)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("filters.sort")
        }
        .listRowBackground(WeydaColor.surface)
    }

    /// Wilaya puis commune : listes poussées (58 wilayas, des dizaines de communes), « Toutes » en tête.
    private var locationSection: some View {
        Section {
            Picker(L10n.postWilaya, selection: $draft.wilayaId) {
                Text(L10n.filtersAllWilayas).tag(Int?.none)
                ForEach(state.wilayas) { wilaya in
                    Text(Self.wilayaLabel(wilaya)).tag(Int?.some(wilaya.id))
                }
            }
            .pickerStyle(.navigationLink)
            if draft.wilayaId != nil {
                Picker(L10n.postCommune, selection: $draft.communeId) {
                    Text(L10n.filtersAllCommunes).tag(Int?.none)
                    ForEach(state.communes) { commune in
                        Text(commune.name.resolve()).tag(Int?.some(commune.id))
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(state.communes.isEmpty)
            }
        } header: {
            Text(L10n.filtersLocation)
        }
        .listRowBackground(WeydaColor.surface)
    }

    private var priceSection: some View {
        Section {
            FilterChipsRow {
                ForEach(Self.priceTypes, id: \.self) { type in
                    WeydaChip(
                        title: ListingsFilterRules.priceTypeTitle(type),
                        isSelected: draft.priceType == type,
                        action: { togglePriceType(type) }
                    )
                }
            }
            FilterNumberField(
                title: L10n.filtersPriceMin,
                suffix: L10n.currencyDa,
                value: draft.priceMin,
                maxDigits: Self.priceDigits,
                onChange: { draft.priceMin = $0 }
            )
            FilterNumberField(
                title: L10n.filtersPriceMax,
                suffix: L10n.currencyDa,
                value: draft.priceMax,
                maxDigits: Self.priceDigits,
                onChange: { draft.priceMax = $0 }
            )
        } header: {
            Text(L10n.filtersPrice)
        }
        .listRowBackground(WeydaColor.surface)
    }

    private var featuredSection: some View {
        Section {
            Toggle(isOn: $draft.featuredOnly) {
                Text(L10n.filtersFeaturedOnly)
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurface)
            }
            .frame(minHeight: WeydaSize.touchTarget)
        }
        .listRowBackground(WeydaColor.surface)
    }

    /// Attributs par plage (année, kilométrage, surface…), comme AttributeFilters du site.
    private var rangeSections: some View {
        ForEach(ListingsFilterRules.filterableAttributes(state.attributeSet, filterType: "range"), id: \.key) { definition in
            Section {
                rangeField(definition, suffix: "_min", title: L10n.filtersRangeMin)
                rangeField(definition, suffix: "_max", title: L10n.filtersRangeMax)
            } header: {
                Text(ListingsFilterRules.rangeTitle(definition))
            }
            .listRowBackground(WeydaColor.surface)
        }
    }

    private func rangeField(_ definition: AttributeDefinition, suffix: String, title: String) -> some View {
        let key = definition.key + suffix
        return FilterNumberField(
            title: title,
            suffix: definition.unitLabel,
            value: draft.attributes[key] ?? "",
            maxDigits: Self.rangeDigits,
            onChange: { value in
                draft = ListingsFilterRules.settingAttribute(draft, key: key, value: value)
            }
        )
    }

    /// Attributs oui / non (« Échange possible », « Meublé »…) : « Oui uniquement ».
    private var booleanSections: some View {
        ForEach(ListingsFilterRules.filterableAttributes(state.attributeSet, filterType: "boolean"), id: \.key) { definition in
            Section {
                FilterCheckRow(
                    title: L10n.filtersYesOnly,
                    isOn: draft.attributes[definition.key] == "true",
                    action: { toggleBoolean(definition.key) }
                )
            } header: {
                Text(definition.label)
            }
            .listRowBackground(WeydaColor.surface)
        }
    }

    /// Facettes (attributs structurés de la catégorie, valeurs comptées par le serveur).
    private var facetSections: some View {
        ForEach(ListingsFilterRules.facetSections(state: state, attributes: draft.attributes)) { section in
            Section {
                FilterChipsRow {
                    ForEach(section.choices) { choice in
                        WeydaChip(
                            title: ListingsFilterRules.facetTitle(choice),
                            isSelected: draft.attributes[section.key] == choice.value,
                            action: { toggleFacet(section.key, value: choice.value) }
                        )
                    }
                }
            } header: {
                Text(section.title)
            }
            .listRowBackground(WeydaColor.surface)
        }
    }

    // MARK: - Brouillon

    private func selectSubcategory(_ slug: String?) {
        draft.subcategory = slug
        draft.attributes = [:]
    }

    private func togglePriceType(_ type: PriceType) {
        draft.priceType = draft.priceType == type ? nil : type
    }

    private func toggleBoolean(_ key: String) {
        let value = draft.attributes[key] == "true" ? "" : "true"
        draft = ListingsFilterRules.settingAttribute(draft, key: key, value: value)
    }

    private func toggleFacet(_ key: String, value: String) {
        draft = ListingsFilterRules.toggling(draft, key: key, value: value, attributeSet: state.attributeSet)
    }

    /// « 16 – Alger » (Android : numéro sur deux chiffres, puis le nom dans la langue de l'app).
    private static func wilayaLabel(_ wilaya: Wilaya) -> String {
        let number = wilaya.id < 10 ? "0\(wilaya.id)" : "\(wilaya.id)"
        return "\(number) – \(wilaya.name.resolve())"
    }

    private static func hideKeyboard() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Rangée de puces défilant horizontalement, bord à bord dans sa ligne de formulaire.
private struct FilterChipsRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WeydaSpace.sm) {
                content
            }
            .padding(.horizontal, WeydaSpace.lg)
        }
        .listRowInsets(EdgeInsets(top: WeydaSpace.xxs, leading: 0, bottom: WeydaSpace.xxs, trailing: 0))
    }
}

/// Champ numérique (pavé numérique, chiffres ASCII seulement — un clavier arabe écrit « ١٢٣ »), unité au bout.
/// Le texte vit ici pendant la frappe et suit la valeur du brouillon (« Réinitialiser »).
private struct FilterNumberField: View {
    private let title: String
    private let suffix: String?
    private let value: String
    private let maxDigits: Int
    private let onChange: (String) -> Void
    @State private var text: String

    init(title: String, suffix: String?, value: String, maxDigits: Int, onChange: @escaping (String) -> Void) {
        self.title = title
        self.suffix = suffix
        self.value = value
        self.maxDigits = maxDigits
        self.onChange = onChange
        _text = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            TextField(title, text: $text)
                .keyboardType(.numberPad)
                .weydaText(.bodyLarge)
                .foregroundStyle(WeydaColor.onSurface)
            if let suffix = TextCheck.nonBlank(suffix) {
                Text(suffix)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: WeydaSize.touchTarget)
        .onChange(of: text) { newValue in
            let clean = String(Validators.asciiDigits(newValue).prefix(maxDigits))
            if clean != newValue {
                text = clean
            } else if clean != value {
                onChange(clean)
            }
        }
        .onChange(of: value) { newValue in
            if newValue != text {
                text = newValue
            }
        }
    }
}

/// Ligne « Oui uniquement » cochée ou non (Android : FilterChip).
private struct FilterCheckRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WeydaSpace.sm) {
                Text(title)
                    .foregroundStyle(WeydaColor.onSurface)
                Spacer(minLength: WeydaSpace.sm)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(WeydaColor.primary)
                        .accessibilityHidden(true)
                }
            }
            .weydaText(.bodyLarge)
            .frame(minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
