import SwiftUI

/// Champs de l'étape « Infos & prix » (focus enchaîné : titre → description).
nonisolated enum PostDetailsField: Hashable, Sendable {
    case title
    case descriptionText
    case price
}

/// Étape 3 — infos et prix (Android : `DetailsStep`) : titre (compteur 0 / 100), description (compteur 0 / 5 000),
/// type de prix en sélecteur segmenté (Android : puces), puis le prix — sauf « Gratuit » — au pavé numérique, groupé
/// par milliers pendant la frappe, « DA » au bout, avec l'aide « prix indicatif » quand il est négociable.
struct PostDetailsStep: View {
    private let state: PostListingState
    private let actions: PostListingActions
    @FocusState private var focus: PostDetailsField?
    @State private var priceType: PriceType

    private static let priceTypes: [PriceType] = [.fixed, .negotiable, .free]

    init(state: PostListingState, actions: PostListingActions) {
        self.state = state
        self.actions = actions
        _priceType = State(initialValue: state.priceType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.lg) {
            titleField
            descriptionField
            priceTypePicker
            if state.priceType != .free {
                priceField
                    .transition(.opacity)
            }
        }
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: state.priceType)
        .onChange(of: priceType) { type in
            if type != state.priceType {
                actions.priceTypeChange(type)
            }
        }
        .onChange(of: state.priceType) { type in
            if type != priceType {
                priceType = type
            }
        }
    }

    private var titleField: some View {
        PostFormTextField(
            L10n.postAdTitle,
            value: state.title,
            placeholder: L10n.postAdTitlePlaceholder,
            isRequired: true,
            error: state.titleError,
            counter: L10n.postCharCount(state.title.utf16.count, PostListingState.titleMax),
            focus: $focus,
            field: .title,
            identifier: "post.title",
            onChange: actions.titleChange
        )
        .submitLabel(.next)
        .onSubmit {
            focus = .descriptionText
        }
    }

    private var descriptionField: some View {
        PostFormTextField(
            L10n.postAdDescription,
            value: state.description,
            placeholder: L10n.postAdDescriptionPlaceholder,
            isRequired: true,
            error: state.descriptionError,
            counter: L10n.postCharCount(state.description.utf16.count, PostListingState.descriptionMax),
            lines: PostFormLimits.descriptionLines,
            focus: $focus,
            field: .descriptionText,
            identifier: "post.description",
            onChange: actions.descriptionChange
        )
    }

    private var priceTypePicker: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(L10n.postPriceType)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            Picker(L10n.postPriceType, selection: $priceType) {
                ForEach(Self.priceTypes, id: \.self) { type in
                    Text(Self.title(of: type))
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("post.priceType")
        }
    }

    private var priceField: some View {
        PostFormNumberField(
            L10n.postPrice,
            value: state.price,
            placeholder: L10n.postPricePlaceholder,
            suffix: L10n.currencyDa,
            style: .groupedInteger(maxDigits: PostFormLimits.priceDigits),
            error: state.priceError,
            supporting: priceHint,
            focus: $focus,
            field: .price,
            identifier: "post.price",
            onChange: actions.priceChange
        )
    }

    /// « Prix indicatif — à débattre avec l'acheteur » sous un prix négociable.
    private var priceHint: String? {
        state.priceType == .negotiable ? L10n.postPriceNegotiableHint : nil
    }

    private static func title(of type: PriceType) -> String {
        switch type {
        case .fixed: L10n.postPriceFixed
        case .negotiable: L10n.postPriceNegotiable
        case .free: L10n.postPriceFree
        }
    }
}
