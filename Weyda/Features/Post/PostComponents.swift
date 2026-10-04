import SwiftUI
import UIKit

// Briques de l'assistant de dépôt (portage des composants privés de `PostSteps.kt` / `PostReviewScreens.kt`) :
// champs à libellé au-dessus (le gabarit des formulaires de connexion, dont le cadre est privé à AuthComponents),
// choix en menu ou en feuille avec recherche, bascule, boutons, aperçu d'une photo. Préfixe « PostForm » : aucun
// nom ne croise ceux de l'état / du ViewModel (WIZARD) ni des sélecteurs de photos (MEDIA).

// MARK: - Limites et textes

/// Bornes de saisie — celles d'Android (`take(10)`, `take(12)`, `take(200)`) ; titre et description :
/// `PostListingState.titleMax` / `descriptionMax`.
nonisolated enum PostFormLimits {
    static let priceDigits = 10
    static let numberLength = 12
    static let textLength = 200
    /// Au-delà, un choix s'ouvre dans une feuille avec recherche plutôt qu'en menu (marques : 54 options).
    static let menuMaxOptions = 8
    /// Lignes visibles de la description (Android : minLines 5, maxLines 12).
    static let descriptionLines: ClosedRange<Int> = 5...12
}

/// Textes composés de l'assistant (aucun texte en dur : tout vient de `L10n` ou des données).
nonisolated enum PostFormText {
    /// Nom de l'étape, en tête de l'assistant et dans le récapitulatif (Android : `stepLabel`).
    static func stepTitle(_ step: PostStep) -> String {
        switch step {
        case .category: L10n.postStepCategory
        case .attributes: L10n.postStepAttributes
        case .details: L10n.postStepDetails
        case .photos: L10n.postStepPhotos
        case .location: L10n.postStepLocation
        case .review: L10n.postStepReview
        }
    }

    /// « Marque * » : l'astérisque des champs requis (Android : `"$label *"`). VoiceOver lit « Obligatoire » à part.
    static func fieldLabel(_ label: String, isRequired: Bool) -> String {
        isRequired ? "\(label) *" : label
    }

    /// « 16 – Alger » (Android : numéro sur deux chiffres, puis le nom dans la langue de l'app).
    static func wilayaLabel(_ wilaya: Wilaya) -> String {
        let number = wilaya.id < 10 ? "0\(wilaya.id)" : "\(wilaya.id)"
        return "\(number) – \(wilaya.name.resolve())"
    }

    /// « 1970 – 2027 » sous un attribut numérique borné (Android : `min.toLong() – max.toLong()`, sans groupement :
    /// une année ne s'écrit pas « 1 970 »). Vide si l'une des bornes manque.
    static func numberPlaceholder(_ definition: AttributeDefinition) -> String {
        guard let lower = definition.min, let upper = definition.max,
              lower.isFinite, upper.isFinite, abs(lower) < 1e15, abs(upper) < 1e15 else { return "" }
        return "\(Int(lower)) – \(Int(upper))"
    }

    /// Chiffres d'un prix groupés pour l'affichage pendant la frappe (« 2350000 » → « 2 350 000 »).
    static func groupedDigits(_ digits: String) -> String {
        guard !digits.isEmpty, let value = Int(digits) else { return digits }
        return Format.count(value)
    }

    /// Valeur d'un attribut telle que la relit le récapitulatif (Android : `ReviewStep`) : Oui / Non, libellé de
    /// l'option (options COURANTES d'un select dépendant), nombre localisé + unité, texte brut.
    static func attributeValue(_ definition: AttributeDefinition, raw: String, options: [AttributeOption]) -> String {
        switch definition.type {
        case .boolean:
            return raw == "true" ? L10n.attrYes : L10n.attrNo
        case .select:
            return options.first { $0.value == raw }?.label ?? definition.optionLabel(raw)
        case .number:
            // Milliers groupés à partir de 10 000 seulement : une année (« 2019 ») ou une cylindrée (« 1500 ») ne se
            // groupe pas — Android affichait « 2 019 » sur son récapitulatif.
            let number: String = Double(raw).flatMap { abs($0) >= 10_000 ? Format.decimal($0) : nil } ?? raw
            guard let unit = TextCheck.nonBlank(definition.unitLabel) else { return number }
            return "\(number) \(unit)"
        case .text:
            return raw
        }
    }

    /// « Véhicules › Voitures » (le chevron est un caractère miroir : il pointe vers la gauche en arabe).
    static func categoryPath(parent: Category?, subcategory: Category?) -> String {
        let names: [String] = [parent?.name.resolve(), subcategory?.name.resolve()].compactMap { $0 }
        return names.joined(separator: " › ")
    }

    /// « Alger, Hydra » ; nil si rien n'est choisi.
    static func place(wilaya: Wilaya?, commune: Commune?) -> String? {
        let names: [String] = [wilaya?.name.resolve(), commune?.name.resolve()].compactMap { $0 }
        return TextCheck.nonBlank(names.joined(separator: ", "))
    }
}

/// Couleurs posées sur une photo (voile d'envoi, texte blanc) : fixes, lisibles sur n'importe quelle image.
nonisolated enum PostFormColors {
    static let scrim = Color(rgb: WeydaRamp.black, opacity: 0.45)
    static let onScrim = Color(rgb: WeydaRamp.white)
    static let removeBadge = Color(rgb: WeydaRamp.black, opacity: 0.55)
}

/// Rabat le clavier (bouton de la barre au-dessus du clavier : les pavés numériques n'ont pas de touche « OK »).
enum PostKeyboard {
    static func hide() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Gabarit d'un champ

/// Libellé au-dessus (toujours visible, lu par VoiceOver comme nom du champ), le champ, puis l'erreur (rouge) ou
/// l'aide (gris) avec un compteur au bout — le gabarit d'`AuthTextField` / `AccountTextArea`.
struct PostFormField<Input: View>: View {
    private let label: String
    private let isRequired: Bool
    private let error: String?
    private let supporting: String?
    private let counter: String?
    private let input: Input

    init(
        label: String,
        isRequired: Bool = false,
        error: String? = nil,
        supporting: String? = nil,
        counter: String? = nil,
        @ViewBuilder input: () -> Input
    ) {
        self.label = label
        self.isRequired = isRequired
        self.error = error
        self.supporting = supporting
        self.counter = counter
        self.input = input()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(PostFormText.fieldLabel(label, isRequired: isRequired))
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            input
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        let message: String? = error ?? supporting
        if message != nil || counter != nil {
            HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                Text(message ?? "")
                    .weydaText(.bodySmall)
                    .foregroundStyle(messageColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let counter {
                    Text(Format.ltrIsolate(counter))
                        .weydaText(.labelSmall)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var messageColor: Color {
        error == nil ? WeydaColor.onSurfaceVariant : WeydaColor.error
    }
}

/// Cadre d'un champ : fond carte, contour fin ; vert au focus, rouge en erreur (comme `AuthInputChrome`).
private struct PostFormChrome: ViewModifier {
    let isFocused: Bool
    let hasError: Bool
    let verticalPadding: CGFloat

    private static let minHeight: CGFloat = 48

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        return content
            .padding(.horizontal, WeydaSpace.md)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: Self.minHeight)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: borderWidth)
            }
    }

    private var borderColor: Color {
        if hasError { return WeydaColor.error }
        return isFocused ? WeydaColor.primary : WeydaPalette.cardOutline
    }

    private var borderWidth: CGFloat {
        hasError || isFocused ? 1.5 : 1
    }
}

extension View {
    /// Cadre des champs de l'assistant.
    func postFormChrome(isFocused: Bool = false, hasError: Bool = false, verticalPadding: CGFloat = WeydaSpace.sm) -> some View {
        modifier(PostFormChrome(isFocused: isFocused, hasError: hasError, verticalPadding: verticalPadding))
    }
}

// MARK: - Texte

/// Champ texte (une ligne, ou plusieurs avec `lines`). Le texte vit ici pendant la frappe et suit la valeur de
/// l'état (brouillon restauré, annonce relue, troncature du ViewModel) : aucune liaison `Binding(get:set:)`.
struct PostFormTextField<Field: Hashable>: View {
    private let label: String
    private let value: String
    private let placeholder: String
    private let isRequired: Bool
    private let error: String?
    private let supporting: String?
    private let counter: String?
    private let lines: ClosedRange<Int>?
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let identifier: String
    private let onChange: (String) -> Void
    @State private var text: String

    init(
        _ label: String,
        value: String,
        placeholder: String = "",
        isRequired: Bool = false,
        error: String? = nil,
        supporting: String? = nil,
        counter: String? = nil,
        lines: ClosedRange<Int>? = nil,
        focus: FocusState<Field?>.Binding,
        field: Field,
        identifier: String,
        onChange: @escaping (String) -> Void
    ) {
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.error = error
        self.supporting = supporting
        self.counter = counter
        self.lines = lines
        self.focus = focus
        self.field = field
        self.identifier = identifier
        self.onChange = onChange
        _text = State(initialValue: value)
    }

    var body: some View {
        PostFormField(label: label, isRequired: isRequired, error: error, supporting: supporting, counter: counter) {
            input
        }
        .onChange(of: text) { newValue in
            if newValue != value {
                onChange(newValue)
            }
        }
        .onChange(of: value) { newValue in
            if newValue != text {
                text = newValue
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        if let lines {
            styled(TextField(placeholder, text: $text, axis: .vertical).lineLimit(lines), verticalPadding: WeydaSpace.md)
        } else {
            styled(TextField(placeholder, text: $text), verticalPadding: WeydaSpace.sm)
        }
    }

    private func styled<Input: View>(_ textField: Input, verticalPadding: CGFloat) -> some View {
        textField
            .textInputAutocapitalization(.sentences)
            .weydaText(.bodyLarge)
            .foregroundStyle(WeydaColor.onSurface)
            .focused(focus, equals: field)
            .postFormChrome(isFocused: focus.wrappedValue == field, hasError: error != nil, verticalPadding: verticalPadding)
            .accessibilityLabel(label)
            .accessibilityHint(isRequired ? L10n.postUiRequired : "")
            .accessibilityIdentifier(identifier)
    }
}

// MARK: - Nombres

/// Saisie numérique : prix (chiffres seuls, groupés par milliers pendant la frappe) ou attribut (décimal).
nonisolated enum PostNumberStyle: Sendable, Equatable {
    case groupedInteger(maxDigits: Int)
    case decimal(maxLength: Int)

    /// Valeur transmise au ViewModel : chiffres ASCII (un clavier arabe écrit « ١٢٣ »), séparateur décimal « . ».
    func clean(_ text: String) -> String {
        switch self {
        case .groupedInteger(let maxDigits):
            String(Validators.asciiDigits(text).prefix(maxDigits))
        case .decimal(let maxLength):
            String(Validators.asciiDecimal(text).prefix(maxLength))
        }
    }

    /// Texte affiché dans le champ pour une valeur de l'état.
    func display(_ value: String) -> String {
        switch self {
        case .groupedInteger:
            PostFormText.groupedDigits(value)
        case .decimal:
            value
        }
    }

    var usesDecimalPad: Bool {
        switch self {
        case .groupedInteger: false
        case .decimal: true
        }
    }
}

/// Champ numérique (pavé numérique, unité au bout). Les chiffres s'écrivent de gauche à droite même en arabe
/// (« 2 350 000 » ne s'inverse pas en « 000 350 2 »), alignés du côté de lecture.
struct PostFormNumberField<Field: Hashable>: View {
    private let label: String
    private let value: String
    private let placeholder: String
    private let suffix: String?
    private let style: PostNumberStyle
    private let isRequired: Bool
    private let error: String?
    private let supporting: String?
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    private let identifier: String
    private let onChange: (String) -> Void
    @State private var text: String

    init(
        _ label: String,
        value: String,
        placeholder: String = "",
        suffix: String? = nil,
        style: PostNumberStyle,
        isRequired: Bool = false,
        error: String? = nil,
        supporting: String? = nil,
        focus: FocusState<Field?>.Binding,
        field: Field,
        identifier: String,
        onChange: @escaping (String) -> Void
    ) {
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.suffix = suffix
        self.style = style
        self.isRequired = isRequired
        self.error = error
        self.supporting = supporting
        self.focus = focus
        self.field = field
        self.identifier = identifier
        self.onChange = onChange
        _text = State(initialValue: style.display(value))
    }

    var body: some View {
        PostFormField(label: label, isRequired: isRequired, error: error, supporting: supporting) {
            HStack(spacing: WeydaSpace.sm) {
                TextField(placeholder, text: $text)
                    .keyboardType(style.usesDecimalPad ? .decimalPad : .numberPad)
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(alignment)
                    .environment(\.layoutDirection, .leftToRight)
                    .focused(focus, equals: field)
                    .accessibilityLabel(label)
                    .accessibilityHint(isRequired ? L10n.postUiRequired : "")
                    .accessibilityIdentifier(identifier)
                if let suffix = TextCheck.nonBlank(suffix) {
                    Text(suffix)
                        .weydaText(.bodyMedium)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .accessibilityHidden(true)
                }
            }
            .postFormChrome(isFocused: focus.wrappedValue == field, hasError: error != nil)
        }
        .onChange(of: text) { newValue in
            let clean = style.clean(newValue)
            let shown = style.display(clean)
            if shown != newValue {
                text = shown
            }
            if clean != value {
                onChange(clean)
            }
        }
        .onChange(of: value) { newValue in
            let shown = style.display(newValue)
            if shown != text {
                text = shown
            }
        }
    }

    /// Champ forcé de gauche à droite : « fin » = à droite, le côté où l'arabe commence sa lecture.
    private var alignment: TextAlignment {
        WeydaLocale.isRightToLeft ? .trailing : .leading
    }
}

// MARK: - Choix dans une liste

/// Une option d'un choix (valeur technique + libellé affiché), cherchée aussi par ses `keywords` (noms fr / ar / en
/// d'une wilaya, son numéro).
nonisolated struct PostFormOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let keywords: [String]

    init(id: String, label: String, keywords: [String] = []) {
        self.id = id
        self.label = label
        self.keywords = keywords
    }

    /// Sans casse ni accents (`foldedForSearch`), dans toutes les écritures à la fois ; aiguille vide = tout.
    func matches(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        if label.foldedForSearch().contains(needle) { return true }
        return keywords.contains { $0.foldedForSearch().contains(needle) }
    }
}

/// Champ de choix (Android : `PickerField`) : menu natif jusqu'à 8 options, au-delà (ou `prefersSheet`) une feuille
/// avec recherche. « Aucun » en tête quand le choix peut être vidé (`allowsClear`).
struct PostFormPicker: View {
    private let label: String
    private let options: [PostFormOption]
    private let selectedId: String?
    private let selectedLabel: String?
    private let placeholder: String
    private let isRequired: Bool
    private let allowsClear: Bool
    private let isEnabled: Bool
    private let isLoading: Bool
    private let prefersSheet: Bool
    private let error: String?
    private let supporting: String?
    private let identifier: String
    private let onSelect: (String?) -> Void
    @State private var showsSheet: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ label: String,
        options: [PostFormOption],
        selectedId: String?,
        selectedLabel: String?,
        placeholder: String,
        isRequired: Bool = false,
        allowsClear: Bool = false,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        prefersSheet: Bool = false,
        error: String? = nil,
        supporting: String? = nil,
        identifier: String,
        onSelect: @escaping (String?) -> Void
    ) {
        self.label = label
        self.options = options
        self.selectedId = selectedId
        self.selectedLabel = selectedLabel
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.allowsClear = allowsClear
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.prefersSheet = prefersSheet
        self.error = error
        self.supporting = supporting
        self.identifier = identifier
        self.onSelect = onSelect
    }

    var body: some View {
        PostFormField(label: label, isRequired: isRequired, error: error, supporting: supporting) {
            control
        }
        .sheet(isPresented: $showsSheet) {
            PostFormOptionSheet(
                title: label,
                options: options,
                selectedId: selectedId,
                allowsClear: allowsClear,
                onSelect: onSelect
            )
        }
    }

    private var usesSheet: Bool {
        prefersSheet || options.count > PostFormLimits.menuMaxOptions
    }

    private var valueText: String {
        selectedLabel ?? placeholder
    }

    @ViewBuilder
    private var control: some View {
        if usesSheet {
            Button {
                showsSheet = true
            } label: {
                fieldBox(symbol: "chevron.forward")
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
            .accessibilityValue(valueText)
            .accessibilityHint(isRequired ? L10n.postUiRequired : "")
            .accessibilityIdentifier(identifier)
        } else {
            Menu {
                menuItems
            } label: {
                fieldBox(symbol: "chevron.up.chevron.down")
            }
            .disabled(!isEnabled)
            .accessibilityLabel(label)
            .accessibilityValue(valueText)
            .accessibilityHint(isRequired ? L10n.postUiRequired : "")
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if allowsClear && selectedId != nil {
            Button(L10n.postClearSelection) {
                onSelect(nil)
            }
        }
        ForEach(options) { option in
            Button {
                onSelect(option.id)
            } label: {
                if option.id == selectedId {
                    Label(option.label, systemImage: "checkmark")
                } else {
                    Text(option.label)
                }
            }
        }
    }

    /// Valeur choisie : deux lignes aux tailles normales ; entière en très grand texte (nil).
    private var valueLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 2
    }

    private func fieldBox(symbol: String) -> some View {
        HStack(spacing: WeydaSpace.sm) {
            Text(valueText)
                .weydaText(.bodyLarge)
                .foregroundStyle(textColor)
                .lineLimit(valueLineLimit)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
        }
        .postFormChrome(hasError: error != nil)
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    private var textColor: Color {
        selectedLabel == nil ? WeydaColor.onSurfaceVariant : WeydaColor.onSurface
    }
}

/// Longue liste (marques, wilayas, communes) : feuille à mi-hauteur, recherche sans casse ni accents dans les trois
/// langues, ouverte sur l'option choisie ; un choix ferme la feuille.
struct PostFormOptionSheet: View {
    private let title: String
    private let options: [PostFormOption]
    private let selectedId: String?
    private let allowsClear: Bool
    private let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    init(
        title: String,
        options: [PostFormOption],
        selectedId: String?,
        allowsClear: Bool,
        onSelect: @escaping (String?) -> Void
    ) {
        self.title = title
        self.options = options
        self.selectedId = selectedId
        self.allowsClear = allowsClear
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                list
                    .onAppear {
                        if let selectedId {
                            proxy.scrollTo(selectedId, anchor: .center)
                        }
                    }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.postUiSearch)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var filtered: [PostFormOption] {
        let needle = query.foldedForSearch()
        return options.filter { option in option.matches(needle) }
    }

    private var list: some View {
        let rows: [PostFormOption] = filtered
        return List {
            if allowsClear && selectedId != nil && TextCheck.isBlank(query) {
                Button {
                    choose(nil)
                } label: {
                    PostFormOptionRow(title: L10n.postClearSelection, isSelected: false, isSecondary: true)
                }
                .listRowBackground(WeydaColor.surface)
            }
            ForEach(rows) { option in
                Button {
                    choose(option.id)
                } label: {
                    PostFormOptionRow(title: option.label, isSelected: option.id == selectedId, isSecondary: false)
                }
                .listRowBackground(WeydaColor.surface)
                .accessibilityIdentifier("post.option.\(option.id)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WeydaColor.surface)
        .overlay {
            if rows.isEmpty {
                Text(L10n.postUiNoMatch)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.postOptions")
    }

    private func choose(_ id: String?) {
        onSelect(id)
        dismiss()
    }
}

private struct PostFormOptionRow: View {
    let title: String
    let isSelected: Bool
    let isSecondary: Bool

    var body: some View {
        HStack(spacing: WeydaSpace.sm) {
            Text(title)
                .weydaText(.bodyLarge)
                .foregroundStyle(isSecondary ? WeydaColor.onSurfaceVariant : WeydaColor.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WeydaColor.primary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: WeydaSize.touchTarget)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Bascule

/// Ligne « Oui / Non » entière touchable (Android : rangée `toggleable`) : VoiceOver lit « Afficher mon numéro,
/// interrupteur, activé ». L'état local suit la valeur de l'état.
struct PostFormToggleRow: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let isOn: Bool
    private let identifier: String
    private let onChange: (Bool) -> Void
    @State private var value: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isOn: Bool,
        identifier: String,
        onChange: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isOn = isOn
        self.identifier = identifier
        self.onChange = onChange
        _value = State(initialValue: isOn)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        Toggle(isOn: $value) {
            HStack(spacing: WeydaSpace.md) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body)
                        .foregroundStyle(WeydaColor.primary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                    Text(title)
                        .weydaText(.bodyLarge)
                        .foregroundStyle(WeydaColor.onSurface)
                    if let subtitle {
                        Text(subtitle)
                            .weydaText(.bodySmall)
                            .foregroundStyle(WeydaColor.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(WeydaColor.primary)
        .padding(.horizontal, WeydaSpace.lg)
        .padding(.vertical, WeydaSpace.md)
        .frame(minHeight: WeydaSize.touchTarget)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .accessibilityIdentifier(identifier)
        .onChange(of: value) { newValue in
            if newValue != isOn {
                onChange(newValue)
            }
        }
        .onChange(of: isOn) { newValue in
            if newValue != value {
                value = newValue
            }
        }
    }
}

// MARK: - Titres, cartes, boutons

/// Titre d'un groupe de l'étape (« Choisissez une catégorie * », Android : `RequiredLabel`).
struct PostFormSectionLabel: View {
    private let title: String
    private let isRequired: Bool

    init(_ title: String, isRequired: Bool = false) {
        self.title = title
        self.isRequired = isRequired
    }

    var body: some View {
        Text(PostFormText.fieldLabel(title, isRequired: isRequired))
            .weydaText(.titleSmall)
            .foregroundStyle(WeydaColor.onBackground)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Titre de l'étape et compteur (« Caractéristiques » — « Étape 2 sur 6 », dans `PostStepProgress`) : sur une
/// ligne aux tailles normales (le rendu validé) ; en très grand texte, le compteur passe SOUS le titre — à côté, le
/// titre se coupait d'un trait d'union (« Caractéris-tiques »).
struct PostStepTitleRow: View {
    private let title: String
    private let counter: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, counter: String) {
        self.title = title
        self.counter = counter
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                titleText
                    .fixedSize(horizontal: false, vertical: true)
                counterText
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                titleText
                    .frame(maxWidth: .infinity, alignment: .leading)
                counterText
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .weydaText(.titleMedium)
            .foregroundStyle(WeydaColor.onBackground)
    }

    private var counterText: some View {
        Text(counter)
            .weydaText(.labelMedium)
            .foregroundStyle(WeydaColor.onSurfaceVariant)
    }
}

/// Carte blanche à filet fin (sections du récapitulatif, liste des sous-catégories).
struct PostFormCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
            }
    }
}

/// Bouton principal pleine largeur (« Suivant », « Publier l'annonce », « Voir l'annonce ») ; pendant l'envoi le W
/// s'écrit à la place du libellé et l'appui est ignoré (comme `SubmitButton`, avec son propre identifiant).
struct PostPrimaryButton: View {
    private let title: String
    private let isEnabled: Bool
    private let isLoading: Bool
    private let identifier: String
    private let action: () -> Void

    private static let loaderSide: CGFloat = 22

    init(_ title: String, isEnabled: Bool = true, isLoading: Bool = false, identifier: String, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: submit) {
            ZStack {
                Text(title)
                    .weydaText(.titleSmall)
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    WeydaLoader(color: WeydaColor.onPrimary)
                        .frame(width: Self.loaderSide, height: Self.loaderSide)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        // Pendant l'envoi, le bouton garde sa couleur (le W reste lisible) ; `submit` ignore l'appui.
        .disabled(!isEnabled && !isLoading)
        .accessibilityLabel(isLoading ? L10n.loading : title)
        .accessibilityIdentifier(identifier)
    }

    private var labelColor: Color {
        isEnabled || isLoading ? WeydaColor.onPrimary : WeydaColor.onSurfaceVariant
    }

    private func submit() {
        guard !isLoading else { return }
        action()
    }
}

/// Bouton secondaire à contour vert (« Retour », « Mes annonces ») — Android : `OutlinedButton`.
struct PostSecondaryButton: View {
    private let title: String
    private let fillsWidth: Bool
    private let isEnabled: Bool
    private let identifier: String
    private let action: () -> Void

    init(_ title: String, fillsWidth: Bool = true, isEnabled: Bool = true, identifier: String, action: @escaping () -> Void) {
        self.title = title
        self.fillsWidth = fillsWidth
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        let width: CGFloat? = fillsWidth ? CGFloat.infinity : nil
        Button(action: action) {
            Text(title)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WeydaSpace.sm)
                .frame(maxWidth: width)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Photo

/// Aperçu d'une photo de l'annonce : distant une fois envoyée (miniature du serveur), sinon le fichier local
/// (`LocalPhotoThumbnail`, décodé hors du fil principal). Remplit son cadre : l'appelant fixe la taille et rogne.
struct PostFormPhotoImage: View {
    private let photo: PhotoItem
    private let localURL: (String) -> URL

    init(photo: PhotoItem, localURL: @escaping (String) -> URL) {
        self.photo = photo
        self.localURL = localURL
    }

    var body: some View {
        if let remote = photo.remoteURL {
            RemoteImage(url: remote)
        } else {
            LocalPhotoThumbnail(fileURL: localURL(photo.localRef))
        }
    }
}
