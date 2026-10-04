import SwiftUI
import UIKit

// Vues partagées par la fiche d'une annonce et le profil public d'un vendeur : feuille « Signaler », portrait,
// badges de confiance, avis, titre de section et message bref.

// MARK: - Signalement

nonisolated extension ReportReason {
    /// Libellé du motif — mêmes mots et même ordre que `report.reasons.*` du site (`labelRes()`, ReportDialog.kt).
    var label: String {
        switch self {
        case .spam: L10n.reportReasonSpam
        case .inappropriate: L10n.reportReasonInappropriate
        case .fraud: L10n.reportReasonFraud
        case .duplicate: L10n.reportReasonDuplicate
        case .other: L10n.reportReasonOther
        }
    }

    /// Motifs proposés : sans « annonce en double » quand on signale un UTILISATEUR (profil, fil).
    static func choices(targetsUser: Bool) -> [ReportReason] {
        targetsUser ? allCases.filter { $0 != .duplicate } : allCases
    }

    /// Motif présélectionné : spam pour une annonce, fraude pour un utilisateur (comme Android).
    static func initial(targetsUser: Bool) -> ReportReason {
        targetsUser ? .fraud : .spam
    }
}

/// Feuille « Signaler » — portage de `ReportDialog` (Android) : un motif obligatoire (liste à coche unique, le motif
/// choisi annoncé « sélectionné » par VoiceOver) et des précisions facultatives bornées comme côté serveur (1000
/// caractères). Saisie commencée : la feuille ne se ferme plus d'un glissement (Annuler reste possible).
struct ReportSheet: View {
    private let targetsUser: Bool
    private let isBusy: Bool
    private let errorMessage: String?
    private let onSubmit: (ReportReason, String) -> Void
    private let onCancel: () -> Void
    @State private var reason: ReportReason
    @State private var details: String = ""

    init(
        targetsUser: Bool,
        isBusy: Bool,
        errorMessage: String?,
        onSubmit: @escaping (ReportReason, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.targetsUser = targetsUser
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _reason = State(initialValue: ReportReason.initial(targetsUser: targetsUser))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(targetsUser ? L10n.reportUserTitle : L10n.reportTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel, action: onCancel)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isBusy || !TextCheck.isBlank(details))
        .onChange(of: details) { value in
            // Comme Zod : 1000 unités UTF-16 au plus, sans jamais couper un caractère.
            let capped = RepositorySupport.truncatedUTF16(value, max: ReportReason.detailsMax)
            if capped != value {
                details = capped
            }
        }
        .onChange(of: errorMessage) { message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    private var form: some View {
        Form {
            if targetsUser {
                Section {
                    Text(L10n.reportUserHint)
                        .weydaText(.bodyMedium)
                        .foregroundStyle(WeydaColor.onSurfaceVariant)
                        .listRowBackground(WeydaColor.surface)
                }
            }
            Section {
                ForEach(ReportReason.choices(targetsUser: targetsUser), id: \.self) { item in
                    reasonRow(item)
                }
            } header: {
                Text(L10n.reportReason)
            }
            Section {
                TextField(L10n.reportDetailsPlaceholder, text: $details, axis: .vertical)
                    .weydaText(.bodyLarge)
                    .lineLimit(3...6)
                    .disabled(isBusy)
                    .listRowBackground(WeydaColor.surface)
            } header: {
                Text(L10n.reportDetails)
            } footer: {
                if let errorMessage {
                    Text(errorMessage)
                        .weydaText(.bodySmall)
                        .foregroundStyle(WeydaColor.error)
                }
            }
            Section {
                submitButton
            }
        }
        .scrollContentBackground(.hidden)
        .background(WeydaColor.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.report")
    }

    private func reasonRow(_ item: ReportReason) -> some View {
        let selected = item == reason
        return Button {
            reason = item
        } label: {
            HStack(spacing: WeydaSpace.md) {
                Text(item.label)
                    .weydaText(.bodyLarge)
                    .foregroundStyle(WeydaColor.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WeydaColor.primary)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .disabled(isBusy)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .listRowBackground(WeydaColor.surface)
    }

    private var submitButton: some View {
        Button {
            onSubmit(reason, details)
        } label: {
            ZStack {
                if isBusy {
                    ProgressView()
                } else {
                    Text(L10n.reportSubmit)
                        .weydaText(.labelLarge)
                        .foregroundStyle(WeydaColor.error)
                }
            }
            .frame(maxWidth: .infinity, minHeight: WeydaSize.touchTarget)
            .contentShape(Rectangle())
        }
        .disabled(isBusy)
        .listRowBackground(WeydaColor.surface)
        .accessibilityIdentifier("report.submit")
    }
}

// MARK: - Vendeur

/// Portrait rond d'un vendeur ; sans photo, une silhouette sur la pastille verte (comme Android).
struct SellerAvatar: View {
    private let url: String?
    private let size: CGFloat

    init(url: String?, size: CGFloat) {
        self.url = url
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(WeydaColor.primaryContainer)
            .overlay {
                if let url {
                    RemoteImage(urlString: url)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(WeydaColor.onPrimaryContainer)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

/// Badges de confiance du site : recommandé, e-mail vérifié, répond vite.
nonisolated enum TrustBadge: String, CaseIterable, Identifiable, Sendable {
    case recommended
    case verified
    case fastResponder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: L10n.trustRecommended
        case .verified: L10n.trustVerified
        case .fastResponder: L10n.trustFastResponder
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "hand.thumbsup.fill"
        case .verified: "checkmark.seal.fill"
        case .fastResponder: "bolt.fill"
        }
    }

    /// Badges mérités, dans l'ordre d'Android.
    static func badges(for seller: Seller) -> [TrustBadge] {
        var result: [TrustBadge] = []
        if seller.isRecommended { result.append(.recommended) }
        if seller.emailVerified { result.append(.verified) }
        if seller.isFastResponder { result.append(.fastResponder) }
        return result
    }
}

/// Rangée de badges ; passe en colonne si elle ne tient pas sur une ligne (texte agrandi, arabe).
struct TrustBadges: View {
    private let badges: [TrustBadge]

    init(seller: Seller) {
        self.badges = TrustBadge.badges(for: seller)
    }

    var body: some View {
        if !badges.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WeydaSpace.xs) {
                    pills
                }
                VStack(alignment: .leading, spacing: WeydaSpace.xs) {
                    pills
                }
            }
        }
    }

    private var pills: some View {
        ForEach(badges) { badge in
            Label(badge.title, systemImage: badge.symbol)
                .weydaText(.labelSmall)
                .foregroundStyle(WeydaColor.onPrimaryContainer)
                .lineLimit(1)
                .padding(.horizontal, WeydaSpace.sm)
                .padding(.vertical, WeydaSpace.xxs + 1)
                .background(WeydaColor.primaryContainer, in: RoundedRectangle(cornerRadius: WeydaRadius.badge, style: .continuous))
        }
    }
}

// MARK: - Avis

/// Titre « Avis » et moyenne calculée par le serveur sur TOUS les avis (« ★ 4,5 (12) »).
struct ReviewsHeader: View {
    private let summary: ReviewSummary

    init(summary: ReviewSummary) {
        self.summary = summary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
            DetailSectionTitle(L10n.reviewsTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.ratingCount > 0 {
                // VoiceOver : « 4,5 sur 5 (12) » plutôt que « étoile noire 4,5 12 ».
                Text(L10n.sellerRating(summary.average, summary.ratingCount))
                    .weydaText(.labelLarge)
                    .foregroundStyle(WeydaColor.primary)
                    .accessibilityLabel(DetailRatingText.spoken(summary.average, count: summary.ratingCount))
            }
        }
    }
}

/// Un avis reçu : auteur, note, commentaire, date.
struct ReviewCard: View {
    private let review: Review

    init(review: Review) {
        self.review = review
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: WeydaSpace.xs) {
            HStack(alignment: .center, spacing: WeydaSpace.sm) {
                Text(TextCheck.nonBlank(review.authorName) ?? L10n.reviewAnonymous)
                    .weydaText(.titleSmall)
                    .foregroundStyle(WeydaColor.onSurface)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RatingStars(rating: Double(review.rating))
            }
            if let comment = review.comment {
                Text(comment)
                    .weydaText(.bodyMedium)
                    .foregroundStyle(WeydaColor.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = review.createdAt {
                Text(Format.date(date))
                    .weydaText(.labelSmall)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
        }
        .padding(WeydaSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeydaColor.surface, in: shape)
        .overlay {
            shape.strokeBorder(WeydaPalette.cardOutline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Note d'un vendeur en clair pour VoiceOver (logique pure).
nonisolated enum DetailRatingText {
    /// « 4,5 sur 5 (12) » : la moyenne lue comme `RatingStars`, puis le nombre d'avis.
    static func spoken(_ average: Double, count: Int) -> String {
        "\(RatingStarSymbols.spokenLabel(average)) (\(Format.count(count)))"
    }
}

// MARK: - Mise en page

/// Titre d'une section de la fiche ou du profil (« Description », « Vendeur », « Avis »…).
struct DetailSectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .weydaText(.titleMedium)
            .foregroundStyle(WeydaColor.onBackground)
            .accessibilityAddTraits(.isHeader)
    }
}
