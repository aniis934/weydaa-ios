import SwiftUI

/// Étape 6 — récapitulatif (Android : `ReviewStep`, miroir de StepReview.tsx) : en-tête « Vérifiez votre annonce »
/// (en modification : l'avertissement « repassera en vérification »), puis une carte par étape avec « Modifier »
/// (retour direct sur l'étape), et la durée de vie de l'annonce.
struct PostReviewStep: View {
    private let state: PostListingState
    private let actions: PostListingActions

    private static let thumbSide: CGFloat = 64

    init(state: PostListingState, actions: PostListingActions) {
        self.state = state
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.md) {
            header
            PostReviewSection(step: .category, onEdit: actions.goTo) {
                Text(PostFormText.categoryPath(parent: state.parentCategory, subcategory: state.subcategory))
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
            }
            if !filledDefinitions.isEmpty {
                PostReviewSection(step: .attributes, onEdit: actions.goTo) {
                    attributeRows
                }
            }
            PostReviewSection(step: .details, onEdit: actions.goTo) {
                detailsSummary
            }
            PostReviewSection(step: .photos, onEdit: actions.goTo) {
                photosSummary
            }
            PostReviewSection(step: .location, onEdit: actions.goTo) {
                locationSummary
            }
            Text(L10n.postExpirationNotice)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WeydaSpace.xs)
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(L10n.postReviewTitle)
                .weydaText(.titleMedium)
                .foregroundStyle(WeydaColor.primary)
                .accessibilityAddTraits(.isHeader)
            Text(state.isEditing ? L10n.postEditPendingWarning : L10n.postReviewSubtitle)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WeydaSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WeydaColor.primaryContainer.opacity(0.35),
            in: RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Caractéristiques

    /// Attributs renseignés, dans l'ordre de la catégorie (Android : valeurs non vides seulement).
    private var filledDefinitions: [AttributeDefinition] {
        let definitions: [AttributeDefinition] = state.attributeSet?.attributes ?? []
        return definitions.filter { definition in !TextCheck.isBlank(state.attributeValues[definition.key]) }
    }

    private var attributeRows: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            ForEach(filledDefinitions, id: \.key) { definition in
                PostReviewRow(
                    label: definition.label,
                    value: PostFormText.attributeValue(
                        definition,
                        raw: state.attributeValues[definition.key] ?? "",
                        options: state.optionsFor(definition)
                    )
                )
            }
        }
    }

    // MARK: - Infos et prix

    private var detailsSummary: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(state.title)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurface)
            Text(state.description)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .lineLimit(3)
            priceLine
                .padding(.top, WeydaSpace.xs)
        }
    }

    /// Prix (avec « Négociable »), « Gratuit », ou « Prix non renseigné ».
    @ViewBuilder
    private var priceLine: some View {
        if state.priceType != .free && TextCheck.isBlank(state.price) {
            Text(L10n.postPriceNotSet)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        } else {
            // Le composant des cartes : prix vert + « Négociable » à côté (Android : « (Négociable) »).
            PriceText(price: Double(state.price), priceType: state.priceType, style: .titleSmall)
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private var photosSummary: some View {
        if state.photos.isEmpty {
            Text(L10n.postReviewNoPhotos)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WeydaSpace.sm) {
                    ForEach(state.photos) { photo in
                        PostFormPhotoImage(photo: photo, localURL: actions.localPhotoURL)
                            .frame(width: Self.thumbSide, height: Self.thumbSide)
                            .background(WeydaPalette.imagePlaceholder)
                            .clipShape(RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.postPhotoCount(state.photos.count, state.maxPhotos))
        }
    }

    // MARK: - Localisation

    private var locationSummary: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(PostFormText.place(wilaya: state.selectedWilaya, commune: state.selectedCommune) ?? L10n.postReviewNoLocation)
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurface)
            if let phone = state.contactPhone {
                Text(phoneText(phone))
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
        }
    }

    private func phoneText(_ phone: String) -> String {
        state.showPhone ? L10n.postReviewPhoneShown(Format.ltrIsolate(phone)) : L10n.postReviewPhoneHidden
    }
}

/// Carte d'une étape du récapitulatif : titre de l'étape, « Modifier » au bout, puis le contenu.
private struct PostReviewSection<Content: View>: View {
    private let step: PostStep
    private let onEdit: (PostStep) -> Void
    private let content: Content

    init(step: PostStep, onEdit: @escaping (PostStep) -> Void, @ViewBuilder content: () -> Content) {
        self.step = step
        self.onEdit = onEdit
        self.content = content()
    }

    var body: some View {
        PostFormCard {
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                HStack(spacing: WeydaSpace.sm) {
                    Text(title)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Button {
                        onEdit(step)
                    } label: {
                        Text(L10n.postEditStep)
                            .weydaText(.labelLarge)
                            .foregroundStyle(WeydaColor.primary)
                            .padding(.horizontal, WeydaSpace.md)
                            .frame(minHeight: WeydaSize.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.postUiEditSection(title))
                    .accessibilityIdentifier("post.review.edit.\(step.rawValue.lowercased())")
                }
                content
                    .padding(.trailing, WeydaSpace.md)
            }
            .padding(.leading, WeydaSpace.lg)
            .padding(.bottom, WeydaSpace.md)
        }
    }

    private var title: String {
        PostFormText.stepTitle(step)
    }
}

/// « Marque ……… Renault » : libellé à gauche, valeur à droite (côtés inversés en arabe), une seule annonce VoiceOver.
private struct PostReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
            Text(label)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
            Spacer(minLength: WeydaSpace.sm)
            Text(value)
                .weydaText(.bodySmall)
                .fontWeight(.semibold)
                .foregroundStyle(WeydaColor.onSurface)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
