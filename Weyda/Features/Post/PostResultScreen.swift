import SwiftUI
import UIKit

/// Après la publication ou la modification (Android : `PostResultScreen`) : le statut RÉEL renvoyé par le serveur —
/// en ligne (approuvée par l'IA), en vérification par un modérateur, ou publiée et bientôt examinée ; en
/// modification, « vérifiée avant d'être publiée » ou « enregistrée ». Puis « Voir l'annonce », « Mes annonces » et,
/// pour un nouveau dépôt, « Déposer une autre annonce ».
struct PostResultScreen: View {
    private let listing: Listing
    private let isEditing: Bool
    private let onViewListing: () -> Void
    private let onMyListings: () -> Void
    private let onPostAnother: () -> Void
    @State private var appeared: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let iconSide: CGFloat = 72
    /// La coche arrive d'un peu plus petit (une fois : l'état survit au retour depuis la fiche).
    private static let iconStartScale: CGFloat = 0.6

    init(
        listing: Listing,
        isEditing: Bool,
        onViewListing: @escaping () -> Void,
        onMyListings: @escaping () -> Void,
        onPostAnother: @escaping () -> Void
    ) {
        self.listing = listing
        self.isEditing = isEditing
        self.onViewListing = onViewListing
        self.onMyListings = onMyListings
        self.onPostAnother = onPostAnother
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.iconSide, height: Self.iconSide)
                    .foregroundStyle(WeydaColor.primary)
                    .scaleEffect(iconScale)
                    .weydaAnimation(WeydaSpring.interactive, value: appeared)
                    .accessibilityHidden(true)
                Text(title)
                    .weydaText(.headlineSmall)
                    .foregroundStyle(WeydaColor.onBackground)
                    .multilineTextAlignment(.center)
                    .padding(.top, WeydaSpace.lg)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WeydaSpace.sm)
                Text(listing.title)
                    .weydaText(.titleMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .multilineTextAlignment(.center)
                    .padding(.top, WeydaSpace.lg)
                Text(L10n.postExpirationNotice)
                    .weydaText(.bodySmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, WeydaSpace.sm)
                buttons
                    .padding(.top, WeydaSpace.xxxl)
            }
            .frame(maxWidth: WeydaSize.formMaxWidth)
            .padding(.horizontal, WeydaSpace.xxl)
            .padding(.vertical, WeydaSpace.xxxl)
            .frame(maxWidth: .infinity)
        }
        .background(WeydaColor.background)
        .onAppear {
            guard !appeared else { return }
            appeared = true
            // Le formulaire a disparu : VoiceOver repart du haut, sur le titre.
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private var buttons: some View {
        VStack(spacing: WeydaSpace.md) {
            PostPrimaryButton(L10n.postViewListing, identifier: "postResult.view", action: onViewListing)
            PostSecondaryButton(L10n.postMyListings, identifier: "postResult.myListings", action: onMyListings)
            if !isEditing {
                Button(action: onPostAnother) {
                    Text(L10n.postAnother)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WeydaSpace.md)
                        .frame(minHeight: WeydaSize.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("postResult.another")
            }
        }
    }

    private var iconScale: CGFloat {
        appeared || reduceMotion ? 1 : Self.iconStartScale
    }

    private var title: String {
        isEditing ? L10n.postUpdatedTitle : L10n.postSuccessTitle
    }

    /// Mêmes règles qu'Android : statut réel, puis verdict de la modération IA.
    private var message: String {
        let status = listing.listingStatus
        if isEditing {
            return status == .pending ? L10n.postUpdatedPending : L10n.postUpdatedSaved
        }
        if status == .active {
            return L10n.postSuccessApproved
        }
        let decision: String = listing.moderation?.decision ?? ""
        if decision.caseInsensitiveCompare("REJECT") == .orderedSame {
            return L10n.postSuccessPendingReview
        }
        return L10n.postSuccessPublished
    }
}
