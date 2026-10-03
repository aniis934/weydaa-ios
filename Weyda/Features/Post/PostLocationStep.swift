import SwiftUI

/// Étape 5 — localisation et téléphone (Android : `LocationStep`) : wilaya puis commune, chacune dans une feuille
/// avec recherche (fr / ar / en, sans accents ; numéro de wilaya compris), « Aucun » pour vider ; puis « Afficher mon
/// numéro » quand le compte (ou l'annonce modifiée) en a un.
struct PostLocationStep: View {
    private let state: PostListingState
    private let actions: PostListingActions

    init(state: PostListingState, actions: PostListingActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.lg) {
            Text(L10n.postLocationHint)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            wilayaPicker
            if state.wilayaId != nil {
                communePicker
            }
            if let phone = state.contactPhone {
                PostFormToggleRow(
                    L10n.postShowPhone,
                    subtitle: "\(L10n.postShowPhoneHint) · \(Format.ltrIsolate(phone))",
                    systemImage: "phone.fill",
                    isOn: state.showPhone,
                    identifier: "post.showPhone",
                    onChange: actions.showPhoneChange
                )
                .padding(.top, WeydaSpace.xs)
            }
        }
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: state.wilayaId)
    }

    private var wilayaPicker: some View {
        let options: [PostFormOption] = state.wilayas.map { wilaya in
            PostFormOption(
                id: String(wilaya.id),
                label: PostFormText.wilayaLabel(wilaya),
                keywords: [wilaya.name.fr, wilaya.name.ar, wilaya.name.en]
            )
        }
        let selectedLabel: String? = state.selectedWilaya.map { wilaya in PostFormText.wilayaLabel(wilaya) }
        return PostFormPicker(
            L10n.postWilaya,
            options: options,
            selectedId: state.wilayaId.map { id in String(id) },
            selectedLabel: selectedLabel,
            placeholder: L10n.postSelectWilaya,
            allowsClear: true,
            prefersSheet: true,
            identifier: "post.wilaya",
            onSelect: { (selected: String?) in
                actions.wilayaChange(selected.flatMap { raw in Int(raw) })
            }
        )
    }

    private var communePicker: some View {
        let options: [PostFormOption] = state.communes.map { commune in
            PostFormOption(
                id: String(commune.id),
                label: commune.name.resolve(),
                keywords: [commune.name.fr, commune.name.ar, commune.name.en]
            )
        }
        let selectedLabel: String? = state.selectedCommune.map { commune in commune.name.resolve() }
        return PostFormPicker(
            L10n.postCommune,
            options: options,
            selectedId: state.communeId.map { id in String(id) },
            selectedLabel: selectedLabel,
            placeholder: L10n.postSelectCommune,
            allowsClear: true,
            isEnabled: !state.communesLoading && !state.communes.isEmpty,
            isLoading: state.communesLoading,
            prefersSheet: true,
            identifier: "post.commune",
            onSelect: { (selected: String?) in
                actions.communeChange(selected.flatMap { raw in Int(raw) })
            }
        )
    }
}
