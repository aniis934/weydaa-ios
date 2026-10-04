import SwiftUI
import UIKit

/// Feuille « Laisser un avis » / « Modifier mon avis » — portage de `ReviewDialog` (Android), au gabarit des feuilles
/// « Annuler | Titre » de l'app (`OfferAmountSheet`, `ContactSellerSheet`) : le vendeur rappelé, une note de 1 à 5
/// étoiles (cibles de 44 pt, remplies dans le sens de lecture ; VoiceOver : un seul élément réglable « Votre note,
/// 4 étoiles sur 5 »), un commentaire facultatif borné comme le serveur (`MyReview.commentMax` unités UTF-16, avec
/// compteur), « Publier » occupé pendant l'envoi, erreur traduite au-dessus du bouton. Commentaire commencé ou envoi
/// en cours : un glissement ne ferme plus la feuille (Annuler reste possible), comme `dismissOnClickOutside` d'Android.
struct ReviewSheet: View {
    private let sellerName: String
    private let isEditing: Bool
    @Binding private var rating: Int
    @Binding private var comment: String
    private let isBusy: Bool
    private let errorMessage: String?
    private let onSubmit: () -> Void
    private let onCancel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(
        sellerName: String,
        isEditing: Bool,
        rating: Binding<Int>,
        comment: Binding<String>,
        isBusy: Bool,
        errorMessage: String?,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sellerName = sellerName
        self.isEditing = isEditing
        self._rating = rating
        self._comment = comment
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _text = State(initialValue: comment.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WeydaSpace.xl) {
                    if let name = TextCheck.nonBlank(sellerName) {
                        sellerContext(name)
                    }
                    ratingSection
                    commentField
                    if isEditing {
                        editHint
                    }
                    submitArea
                }
                .padding(WeydaSpace.screen)
                .frame(maxWidth: WeydaSize.formMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WeydaColor.background)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.review")
            .navigationTitle(isEditing ? L10n.reviewEdit : L10n.reviewLeave)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel, action: onCancel)
                        .disabled(isBusy)
                        .accessibilityIdentifier("review.cancel")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isBusy || !TextCheck.isBlank(text))
        .onChange(of: text) { value in
            textChanged(value)
        }
        .onChange(of: comment) { value in
            if value != text {
                text = value
            }
        }
        .onChange(of: errorMessage) { message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    // MARK: Vendeur

    /// « Vendeur — Karim B. » : à qui l'avis s'adresse (le nom est un contenu saisi : sens d'écriture naturel).
    private func sellerContext(_ name: String) -> some View {
        HStack(alignment: .center, spacing: WeydaSpace.md) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(WeydaColor.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WeydaSpace.xxs) {
                Text(L10n.detailSeller)
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                Text(name)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Note

    /// « Votre note », les cinq étoiles sur une carte, puis la note en clair (« 4 étoiles sur 5 »).
    private var ratingSection: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            Text(L10n.reviewRating)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            VStack(spacing: WeydaSpace.xs) {
                ReviewStarPicker(rating: $rating, isEnabled: !isBusy)
                Text(L10n.reviewStar(rating))
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, WeydaSpace.md)
            .padding(.horizontal, WeydaSpace.sm)
            .frame(maxWidth: .infinity)
            .background(WeydaColor.surface, in: shape)
            .overlay {
                shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
            }
        }
    }

    // MARK: Commentaire

    private var commentField: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.field, style: .continuous)
        let count = text.utf16.count
        return VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            Text(L10n.reviewComment)
                .weydaText(.labelLarge)
                .foregroundStyle(WeydaColor.onSurface)
                .accessibilityHidden(true)
            TextField(L10n.reviewCommentPlaceholder, text: $text, axis: .vertical)
                .lineLimit(4...8)
                .weydaText(.bodyLarge)
                .focused($isFocused)
                .disabled(isBusy)
                .accessibilityLabel(L10n.reviewComment)
                .accessibilityIdentifier("review.comment")
                .padding(WeydaSpace.md)
                .background(WeydaColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(fieldBorder, lineWidth: isFocused ? 1.5 : 1)
                }
            Text(L10n.postCharCount(count, MyReview.commentMax))
                .weydaText(.labelSmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var fieldBorder: Color {
        isFocused ? WeydaColor.primary : WeydaPalette.cardOutline
    }

    /// Modification : le serveur REMPLACE l'avis (upsert) — dit avant l'envoi.
    private var editHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .accessibilityHidden(true)
            Text(L10n.reviewsEditHint)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .weydaText(.bodySmall)
    }

    // MARK: Envoi

    private var submitArea: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.sm) {
            if let errorMessage {
                Text(errorMessage)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("review.error")
            }
            submitButton
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            ZStack {
                Text(L10n.reviewSend)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onPrimary)
                    .multilineTextAlignment(.center)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .tint(WeydaColor.onPrimary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(WeydaColor.primary)
        .accessibilityLabel(isBusy ? L10n.loading : L10n.reviewSend)
        .accessibilityIdentifier("review.submit")
    }

    /// Pendant l'envoi, le bouton garde sa couleur ; un second appui est ignoré.
    private func submit() {
        guard !isBusy else { return }
        isFocused = false
        onSubmit()
    }

    /// Coupé à `MyReview.commentMax` unités UTF-16 comme le serveur (et non refusé : un collage trop long ne disparaît
    /// pas sans explication) ; Android refusait la frappe au-delà.
    private func textChanged(_ value: String) {
        let capped = RepositorySupport.truncatedUTF16(value, max: MyReview.commentMax)
        if capped != value {
            text = capped
            return
        }
        if capped != comment {
            comment = capped
        }
    }
}

// MARK: - Étoiles

/// Les cinq étoiles de la note : chacune un bouton de 44 pt au moins (Contrôle vocal, Contrôle de sélection, tour de
/// captures : `review.star.<n>`), remplies du début de la ligne jusqu'à la note — donc depuis la droite en arabe.
/// VoiceOver actif : la rangée devient UN élément réglable (balayer vers le haut / le bas change la note), plus
/// naturel que cinq boutons à parcourir.
private struct ReviewStarPicker: View {
    @Binding private var rating: Int
    private let isEnabled: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @ScaledMetric(relativeTo: .title) private var starSide: CGFloat = 30

    /// Étoile la plus grande (texte agrandi) : les cinq cases tiennent toujours sur une ligne d'iPhone.
    private static let maxStarSide: CGFloat = 46
    /// Une étoile vide est un peu plus petite : la note choisie « gonfle » (ressort, rien si Réduire les animations).
    private static let emptyScale: CGFloat = 0.88

    init(rating: Binding<Int>, isEnabled: Bool) {
        self._rating = rating
        self.isEnabled = isEnabled
    }

    var body: some View {
        if voiceOverEnabled {
            stars
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.reviewRating)
                .accessibilityValue(L10n.reviewStar(rating))
                .accessibilityAdjustableAction { direction in
                    adjust(direction)
                }
                .accessibilityIdentifier("review.stars")
        } else {
            stars
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("review.stars")
        }
    }

    private var side: CGFloat {
        min(starSide, Self.maxStarSide)
    }

    private var stars: some View {
        HStack(spacing: WeydaSpace.xs) {
            ForEach(1...RatingStarSymbols.maxStars, id: \.self) { value in
                starButton(value)
            }
        }
        .opacity(isEnabled ? 1 : 0.6)
        .weydaAnimation(WeydaSpring.interactive, value: rating)
    }

    private func starButton(_ value: Int) -> some View {
        let filled = value <= rating
        let cell = max(WeydaSize.touchTarget, side + WeydaSpace.sm)
        return Button {
            select(value)
        } label: {
            Image(systemName: filled ? "star.fill" : "star")
                .font(.system(size: side, weight: .medium))
                .foregroundStyle(filled ? WeydaColor.tertiary : WeydaColor.outline)
                .scaleEffect(filled ? 1 : Self.emptyScale)
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(L10n.reviewStar(value))
        .accessibilityAddTraits(value == rating ? [.isSelected] : [])
        .accessibilityIdentifier("review.star.\(value)")
    }

    private func select(_ value: Int) {
        guard isEnabled, value != rating else { return }
        rating = value
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Réglage VoiceOver : une étoile de plus ou de moins, bornée à 1…5.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard isEnabled else { return }
        if direction == .increment && rating < RatingStarSymbols.maxStars {
            rating = max(rating + 1, 1)
        } else if direction == .decrement && rating > 1 {
            rating -= 1
        }
    }
}
