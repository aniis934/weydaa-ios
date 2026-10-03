import SwiftUI

/// Étape 2 — caractéristiques de la catégorie (Android : `AttributesStep`) : champs requis et recommandés, puis
/// « Plus de détails (n) » qui déplie les facultatifs. Chaque champ suit le type de l'attribut : choix (menu, ou
/// feuille avec recherche au-delà de 8 options ; désactivé tant que son parent est vide), nombre (pavé numérique +
/// unité), oui / non (interrupteur), texte.
struct PostAttributesStep: View {
    private let state: PostListingState
    private let actions: PostListingActions
    @State private var showsOptional: Bool
    @FocusState private var focus: String?

    init(state: PostListingState, actions: PostListingActions) {
        self.state = state
        self.actions = actions
        // Une erreur sur un champ facultatif (renvoyée par le serveur) ne doit pas rester repliée.
        _showsOptional = State(initialValue: Self.hasOptionalError(state))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.lg) {
            if state.attributesLoading && definitions.isEmpty {
                InlineLoader()
            }
            ForEach(mainDefinitions, id: \.key) { definition in
                field(definition)
            }
            if !optionalDefinitions.isEmpty {
                optionalToggle
                if showsOptional {
                    ForEach(optionalDefinitions, id: \.key) { definition in
                        field(definition)
                    }
                }
            }
        }
        .onChange(of: state.attributeErrors) { _ in
            if Self.hasOptionalError(state) {
                showsOptional = true
            }
        }
    }

    private var definitions: [AttributeDefinition] {
        state.attributeSet?.attributes ?? []
    }

    private var mainDefinitions: [AttributeDefinition] {
        definitions.filter { definition in definition.requirement != Requirement.optional }
    }

    private var optionalDefinitions: [AttributeDefinition] {
        definitions.filter { definition in definition.requirement == Requirement.optional }
    }

    private var optionalToggle: some View {
        Button {
            showsOptional.toggle()
        } label: {
            HStack(spacing: WeydaSpace.xs) {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(showsOptional ? 180 : 0))
                    .accessibilityHidden(true)
                Text(L10n.postMoreDetails(optionalDefinitions.count))
                    .weydaText(.labelLarge)
            }
            .foregroundStyle(WeydaColor.primary)
            .frame(minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: showsOptional)
        .accessibilityIdentifier("post.attributes.more")
    }

    private func field(_ definition: AttributeDefinition) -> some View {
        PostAttributeField(
            definition: definition,
            state: state,
            focus: $focus,
            onChange: actions.attributeChange
        )
    }

    private static func hasOptionalError(_ state: PostListingState) -> Bool {
        let definitions: [AttributeDefinition] = state.attributeSet?.attributes ?? []
        return definitions.contains { definition in
            definition.requirement == Requirement.optional && state.attributeErrors[definition.key] != nil
        }
    }
}

/// Un attribut (Android : `AttributeField`). Valeur, erreur, options courantes et activation viennent de l'état ;
/// les nombres et textes sont bornés ici comme sur Android (`take(12)`, `take(200)`), chiffres ramenés en ASCII.
struct PostAttributeField: View {
    private let definition: AttributeDefinition
    private let state: PostListingState
    private let focus: FocusState<String?>.Binding
    private let onChange: (String, String) -> Void

    init(
        definition: AttributeDefinition,
        state: PostListingState,
        focus: FocusState<String?>.Binding,
        onChange: @escaping (String, String) -> Void
    ) {
        self.definition = definition
        self.state = state
        self.focus = focus
        self.onChange = onChange
    }

    var body: some View {
        switch definition.type {
        case .select:
            selectField
        case .number:
            numberField
        case .boolean:
            booleanField
        case .text:
            textField
        }
    }

    private var key: String { definition.key }

    private var value: String { state.attributeValues[key] ?? "" }

    private var error: String? { state.attributeErrors[key] }

    private var identifier: String { "post.attr.\(key)" }

    private var selectField: some View {
        let options: [AttributeOption] = state.optionsFor(definition)
        let isEnabled: Bool = state.isAttributeEnabled(definition)
        let current: String = value
        var selectedId: String? = nil
        var selectedLabel: String? = nil
        if !TextCheck.isBlank(current) {
            selectedId = current
            // Libellé cherché dans les options COURANTES (select dépendant : options chargées avec le contexte).
            let match: AttributeOption? = options.first { option in option.value == current }
            selectedLabel = match?.label ?? definition.optionLabel(current)
        }
        let choices: [PostFormOption] = options.map { option in PostFormOption(id: option.value, label: option.label) }
        return PostFormPicker(
            definition.label,
            options: choices,
            selectedId: selectedId,
            selectedLabel: selectedLabel,
            placeholder: L10n.postUiChoose,
            isRequired: definition.isRequired,
            allowsClear: !definition.isRequired,
            isEnabled: isEnabled,
            error: error,
            supporting: isEnabled ? nil : parentHint,
            identifier: identifier,
            onSelect: { (selected: String?) in
                onChange(definition.key, selected ?? "")
            }
        )
    }

    /// « Choisissez d'abord : Marque » sous un choix dépendant encore désactivé.
    private var parentHint: String? {
        guard let parentKey = definition.dependsOn else { return nil }
        let parentLabel: String = state.attributeSet?.attribute(parentKey)?.label ?? parentKey
        return L10n.postSelectParentFirst(parentLabel)
    }

    private var numberField: some View {
        PostFormNumberField(
            definition.label,
            value: value,
            placeholder: PostFormText.numberPlaceholder(definition),
            suffix: definition.unitLabel,
            style: .decimal(maxLength: PostFormLimits.numberLength),
            isRequired: definition.isRequired,
            error: error,
            focus: focus,
            field: key,
            identifier: identifier,
            onChange: { (text: String) in
                onChange(definition.key, text)
            }
        )
    }

    /// Désactivé = valeur retirée (Android envoie "" : l'attribut n'est pas transmis).
    private var booleanField: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            PostFormToggleRow(
                definition.label,
                isOn: value == "true",
                identifier: identifier,
                onChange: { (isOn: Bool) in
                    onChange(definition.key, isOn ? "true" : "")
                }
            )
            if let error {
                Text(error)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var textField: some View {
        PostFormTextField(
            definition.label,
            value: value,
            isRequired: definition.isRequired,
            error: error,
            focus: focus,
            field: key,
            identifier: identifier,
            onChange: { (text: String) in
                onChange(definition.key, String(text.prefix(PostFormLimits.textLength)))
            }
        )
        .submitLabel(.done)
    }
}
