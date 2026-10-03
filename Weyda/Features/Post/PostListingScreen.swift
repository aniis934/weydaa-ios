import SwiftUI
import UIKit

/// Actions de l'assistant (Android : `PostListingActions`), branchées par `PostListingHost` sur le ViewModel, le
/// routeur et les sélecteurs de photos. L'écran et ses étapes n'ont pas d'autre accès au monde.
struct PostListingActions {
    var retryCategories: () -> Void
    var selectParent: (String) -> Void
    var selectSubcategory: (String) -> Void
    var attributeChange: (String, String) -> Void
    var titleChange: (String) -> Void
    var descriptionChange: (String) -> Void
    var priceTypeChange: (PriceType) -> Void
    var priceChange: (String) -> Void
    var openGallery: () -> Void
    var openCamera: () -> Void
    var removePhoto: (Int) -> Void
    var makeMainPhoto: (Int) -> Void
    var retryPhoto: (Int) -> Void
    var photosNoticeShown: () -> Void
    /// Fichier local d'une photo pas encore en ligne (`PostPhotoStore.fileURL(for:)`).
    var localPhotoURL: (String) -> URL
    var wilayaChange: (Int?) -> Void
    var communeChange: (Int?) -> Void
    var showPhoneChange: (Bool) -> Void
    var next: () -> Void
    var back: () -> Void
    var goTo: (PostStep) -> Void
    var viewListing: (Listing) -> Void
    var myListings: () -> Void
    var postAnother: () -> Void
    var retryEditing: () -> Void
    var verifyEmail: () -> Void
    /// Édition : quitter l'écran (retour à « Mes annonces » ou à la fiche) ; nil dans l'onglet Déposer.
    var leave: (() -> Void)?
}

/// L'assistant de dépôt, sans état propre (hors confirmation d'abandon) — portage de `PostListingScreen`
/// (PostListingScreen.kt) : résultat, chargement / erreur de l'annonce à modifier, ou bien bandeaux (hors ligne,
/// e-mail à vérifier), progression « Étape x sur y », contenu de l'étape (qui repart du haut), bandeau d'erreur et
/// barre Retour / Suivant fixée en bas, au-dessus du clavier.
///
/// Édition : le retour de la barre de navigation suit le `BackHandler` d'Android — d'une étape, retour au
/// récapitulatif (point d'entrée) ; du récapitulatif, confirmation avant d'abandonner des modifications. Le geste
/// de retour est coupé quand il ferait perdre quelque chose (bouton système masqué).
struct PostListingScreen: View {
    private let state: PostListingState
    private let actions: PostListingActions
    private let cameraAvailable: Bool
    @State private var confirmsDiscard: Bool = false

    init(state: PostListingState, actions: PostListingActions, cameraAvailable: Bool) {
        self.state = state
        self.actions = actions
        self.cameraAvailable = cameraAvailable
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WeydaColor.background)
            .navigationTitle(state.isEditing ? L10n.postEditTitle : L10n.postTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(hidesSystemBack)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if hidesSystemBack {
                        Button(action: navigateBack) {
                            Label(L10n.back, systemImage: "chevron.backward")
                        }
                        .disabled(state.isSubmitting)
                        .accessibilityIdentifier("post.navBack")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        PostKeyboard.hide()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel(L10n.close)
                }
            }
            .alert(L10n.postDiscardTitle, isPresented: $confirmsDiscard) {
                Button(L10n.postDiscardConfirm, role: .destructive) {
                    actions.leave?()
                }
                Button(L10n.postDiscardKeep, role: .cancel) {}
            } message: {
                Text(L10n.postDiscardMessage)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(rootIdentifier)
    }

    @ViewBuilder
    private var content: some View {
        if let listing = state.result {
            PostResultScreen(
                listing: listing,
                isEditing: state.isEditing,
                onViewListing: { actions.viewListing(listing) },
                onMyListings: actions.myListings,
                onPostAnother: actions.postAnother
            )
        } else if state.editLoading {
            LoadingState()
        } else if let message = state.editError {
            ErrorState(message: message, onRetry: actions.retryEditing)
        } else {
            wizard
        }
    }

    /// Bandeaux et progression dans une pile AU-DESSUS de la vue défilante (sur iOS 26, un encart du haut passe sous
    /// l'effet de bord de la barre de navigation) ; barre d'actions en encart du bas : elle remonte avec le clavier.
    private var wizard: some View {
        VStack(spacing: 0) {
            OfflineBanner()
            if !state.emailVerified {
                VerifyEmailBanner(onVerifyEmail: actions.verifyEmail)
                    .padding(.horizontal, WeydaSpace.screen)
                    .padding(.vertical, WeydaSpace.sm)
            }
            PostStepProgress(step: state.step, index: state.stepIndex, total: state.steps.count)
            PostStepScroll(state: state, actions: actions, cameraAvailable: cameraAvailable)
        }
        // Avant la barre : le message bref (limite de photos atteinte…) s'affiche au-dessus d'elle.
        .floatingNotice(state.photosNotice, onShown: actions.photosNoticeShown)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PostStepBar(state: state, onBack: actions.back, onNext: actions.next)
        }
    }

    private var rootIdentifier: String {
        if state.result != nil { return "screen.postResult" }
        return state.isEditing ? "screen.postEdit" : "screen.post"
    }

    /// Bouton retour maison (édition prête, formulaire affiché) dès que le retour système ferait perdre quelque
    /// chose : hors du récapitulatif, modifications en cours, ou envoi en cours.
    private var hidesSystemBack: Bool {
        guard state.isEditing, state.result == nil, !state.editLoading, state.editError == nil else { return false }
        return state.isSubmitting || state.step != .review || state.isDirty
    }

    private func navigateBack() {
        guard !state.isSubmitting else { return }
        if state.step != .review {
            actions.goTo(.review)
        } else if state.isDirty {
            confirmsDiscard = true
        } else {
            actions.leave?()
        }
    }
}

// MARK: - Contenu défilant

/// La vue défilante de l'étape : repart du haut à chaque étape (Android : `scrollTo(0)`), descend jusqu'au bandeau
/// d'erreur quand il apparaît, rabat le clavier en défilant.
private struct PostStepScroll: View {
    let state: PostListingState
    let actions: PostListingActions
    let cameraAvailable: Bool

    private static let topAnchor = "post.scroll.top"
    private static let errorAnchor = "post.scroll.error"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchor)
                    stepContent
                        .padding(.top, WeydaSpace.md)
                    if let message = state.errorMessage {
                        ErrorBanner(message: message)
                            .padding(.top, WeydaSpace.lg)
                            .id(Self.errorAnchor)
                    }
                }
                .frame(maxWidth: WeydaSize.formMaxWidth, alignment: .leading)
                .padding(.horizontal, WeydaSpace.xl)
                .padding(.bottom, WeydaSpace.xxl)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: state.step) { _ in
                proxy.scrollTo(Self.topAnchor, anchor: .top)
                // VoiceOver repart du haut : la nouvelle étape s'annonce par son titre.
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
            .onChange(of: state.errorMessage) { message in
                if message != nil {
                    proxy.scrollTo(Self.errorAnchor, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if state.isSubmitting {
            PostSubmittingView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                step
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("post.step.\(state.step.rawValue.lowercased())")
        }
    }

    @ViewBuilder
    private var step: some View {
        switch state.step {
        case .category:
            PostCategoryStep(state: state, actions: actions)
        case .attributes:
            PostAttributesStep(state: state, actions: actions)
        case .details:
            PostDetailsStep(state: state, actions: actions)
        case .photos:
            PostPhotosStep(state: state, actions: actions, cameraAvailable: cameraAvailable)
        case .location:
            PostLocationStep(state: state, actions: actions)
        case .review:
            PostReviewStep(state: state, actions: actions)
        }
    }
}

// MARK: - Progression

/// « Caractéristiques — Étape 2 sur 6 » et la barre de progression (Android : `WizardProgress`). Un seul élément
/// VoiceOver, en titre.
struct PostStepProgress: View {
    private let step: PostStep
    private let index: Int
    private let total: Int

    init(step: PostStep, index: Int, total: Int) {
        self.step = step
        self.index = index
        self.total = total
    }

    var body: some View {
        let count = max(total, 1)
        let current = min(max(index, 0) + 1, count)
        VStack(spacing: WeydaSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: WeydaSpace.sm) {
                Text(PostFormText.stepTitle(step))
                    .weydaText(.titleMedium)
                    .foregroundStyle(WeydaColor.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.postStepOf(current, count))
                    .weydaText(.labelMedium)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
            ProgressView(value: Double(current), total: Double(count))
                .tint(WeydaColor.primary)
                .weydaAnimation(.easeOut(duration: WeydaDuration.medium), value: current)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, WeydaSpace.xl)
        .padding(.vertical, WeydaSpace.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("post.progress")
    }
}

// MARK: - Barre d'actions

/// « Retour » (sauf à la première étape) et « Suivant » / « Publier l'annonce » / « Enregistrer » — Android :
/// `WizardBottomBar`. « Suivant » reste inactif pendant un chargement, un envoi de photo ou la publication (le W
/// s'écrit alors dans le bouton). En très grand texte, les deux boutons s'empilent.
struct PostStepBar: View {
    private let state: PostListingState
    private let onBack: () -> Void
    private let onNext: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(state: PostListingState, onBack: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.state = state
        self.onBack = onBack
        self.onNext = onNext
    }

    var body: some View {
        buttons
            .padding(.horizontal, WeydaSpace.screen)
            .padding(.vertical, WeydaSpace.md)
            .frame(maxWidth: .infinity)
            .background(WeydaColor.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WeydaColor.outlineVariant)
                    .frame(height: 1)
            }
    }

    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: WeydaSpace.sm) {
                nextButton
                if !state.isFirstStep {
                    backButton(fillsWidth: true)
                }
            }
        } else {
            HStack(spacing: WeydaSpace.md) {
                if !state.isFirstStep {
                    backButton(fillsWidth: false)
                }
                nextButton
            }
        }
    }

    private var nextButton: some View {
        PostPrimaryButton(
            nextTitle,
            isEnabled: state.canGoNext,
            isLoading: state.isSubmitting,
            identifier: "post.next",
            action: onNext
        )
    }

    private func backButton(fillsWidth: Bool) -> some View {
        PostSecondaryButton(
            L10n.postBack,
            fillsWidth: fillsWidth,
            isEnabled: !state.isSubmitting,
            identifier: "post.back",
            action: onBack
        )
    }

    private var nextTitle: String {
        if !state.isLastStep { return L10n.postNext }
        return state.isEditing ? L10n.postSave : L10n.postPublish
    }
}

// MARK: - Publication en cours

/// Pendant `POST /api/annonces` : la modération IA du serveur peut prendre jusqu'à 15 s (Android : `SubmittingView`).
struct PostSubmittingView: View {
    private static let loaderSide: CGFloat = WeydaSize.stateIcon
    private static let verticalPadding: CGFloat = 64

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            WeydaLoader()
                .frame(width: Self.loaderSide, height: Self.loaderSide)
            Text(L10n.postAnalyzing)
                .weydaText(.titleSmall)
                .foregroundStyle(WeydaColor.onBackground)
                .multilineTextAlignment(.center)
                .padding(.top, WeydaSpace.lg)
            Text(L10n.postSuccessDesc)
                .weydaText(.bodySmall)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.top, WeydaSpace.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Self.verticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("post.submitting")
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: L10n.postAnalyzing)
        }
    }
}

// MARK: - Navigation après une modification

/// Piles après le résultat d'une MODIFICATION (Android : routes de `EditListing` dans WeydaRoot.kt) :
///  · « Voir l'annonce » = `navigate(Detail) { popUpTo(MyListings) }` — l'écran de modification (et ce qui suit
///    « Mes annonces ») part, la fiche s'ouvre ;
///  · « Mes annonces » = `popBackStack(MyListings)` — retour à la liste, ou elle s'ouvre si l'on venait d'ailleurs.
nonisolated enum PostEditNavigation {
    static func showingListing(_ id: String, from stack: [AppRoute]) -> [AppRoute] {
        var routes = withoutEditing(stack)
        if let mine = routes.lastIndex(of: AppRoute.myListings) {
            routes = Array(routes.prefix(through: mine))
        }
        // Ouvert depuis la fiche de cette annonce : on y revient au lieu d'en empiler une seconde.
        let detail = AppRoute.detail(idOrSlug: id)
        if routes.last != detail {
            routes.append(detail)
        }
        return routes
    }

    static func showingMyListings(from stack: [AppRoute]) -> [AppRoute] {
        var routes = withoutEditing(stack)
        if let mine = routes.lastIndex(of: AppRoute.myListings) {
            return Array(routes.prefix(through: mine))
        }
        routes.append(AppRoute.myListings)
        return routes
    }

    private static func withoutEditing(_ stack: [AppRoute]) -> [AppRoute] {
        let index: Int? = stack.lastIndex(where: { (route: AppRoute) -> Bool in
            if case .editListing = route { return true }
            return false
        })
        guard let index else { return stack }
        return Array(stack.prefix(upTo: index))
    }
}
