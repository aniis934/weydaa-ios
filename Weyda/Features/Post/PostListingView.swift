import SwiftUI

/// Déposer une annonce (racine de l'onglet Déposer) ou la modifier (`AppRoute.editListing`, poussée sur la pile) —
/// portage de `PostListingRoute` (PostListingScreen.kt) et des deux entrées de WeydaRoot.kt :
///  · onglet : un visiteur voit l'invitation à se connecter (Android : `LoginRequired`) ; un membre, l'assistant,
///    recréé pour un autre compte (`.id`) — ni le brouillon ni le numéro d'un compte ne passent au suivant ;
///  · édition : écran de membre (`AccountMemberGate` : il se retire si la session se ferme), ouvert sur le
///    récapitulatif une fois l'annonce relue.
struct PostListingView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var router: AppRouter
    private let editingId: String?

    init(editingId: String? = nil) {
        self.editingId = editingId
    }

    var body: some View {
        if let editingId {
            AccountMemberGate(title: L10n.postEditTitle) { _ in
                PostListingHost(
                    model: PostListingViewModel.make(container: container, editingId: editingId),
                    isEditing: true
                )
            }
        } else if let user = session.user {
            PostListingHost(
                model: PostListingViewModel.make(container: container, editingId: nil),
                isEditing: false
            )
            .id(user.id)
        } else {
            LoginRequired(
                title: L10n.loginRequiredTitle,
                message: L10n.loginRequiredBody,
                onLogin: { router.requestLogin() }
            )
            .navigationTitle(L10n.postTitle)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("screen.postGuest")
        }
    }
}

/// Possède le ViewModel (créé une fois par `@StateObject`) et l'état de présentation des sélecteurs de photos ;
/// branche les actions de l'écran sur le ViewModel et le routeur.
private struct PostListingHost: View {
    @StateObject private var model: PostListingViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showsGallery: Bool = false
    @State private var showsCamera: Bool = false
    private let isEditing: Bool

    init(model: @autoclosure @escaping () -> PostListingViewModel, isEditing: Bool) {
        _model = StateObject(wrappedValue: model())
        self.isEditing = isEditing
    }

    var body: some View {
        PostListingScreen(state: model.state, actions: makeActions(), cameraAvailable: PostCamera.isAvailable)
            // Galerie : sélection multiple bornée aux places restantes (au moins 1 : le sélecteur l'exige).
            .postGalleryPicker(
                isPresented: $showsGallery,
                limit: max(model.state.remainingPhotoSlots, 1),
                onPicked: { (images: [Data]) in
                    _ = model.onPhotosPicked(images)
                }
            )
            .postCameraPicker(
                isPresented: $showsCamera,
                onCaptured: { (image: Data) in
                    _ = model.onPhotosPicked([image])
                }
            )
    }

    private func makeActions() -> PostListingActions {
        let model = self.model
        let store = model.photoStore
        var leave: (() -> Void)? = nil
        if isEditing {
            leave = { dismiss() }
        }
        return PostListingActions(
            retryCategories: { _ = model.loadCategories() },
            selectParent: { (id: String) in _ = model.onSelectParent(id) },
            selectSubcategory: { (id: String) in _ = model.onSelectSubcategory(id) },
            attributeChange: { (key: String, value: String) in _ = model.onAttributeChange(key, value) },
            titleChange: { (value: String) in model.onTitleChange(value) },
            descriptionChange: { (value: String) in model.onDescriptionChange(value) },
            priceTypeChange: { (type: PriceType) in model.onPriceTypeChange(type) },
            priceChange: { (value: String) in model.onPriceChange(value) },
            openGallery: { showsGallery = true },
            openCamera: { openCamera() },
            removePhoto: { (index: Int) in model.onRemovePhoto(at: index) },
            makeMainPhoto: { (index: Int) in model.onMakeMainPhoto(at: index) },
            retryPhoto: { (index: Int) in _ = model.onRetryPhoto(at: index) },
            photosNoticeShown: { model.photosNoticeShown() },
            localPhotoURL: { (ref: String) -> URL in store.fileURL(for: ref) },
            wilayaChange: { (id: Int?) in _ = model.onWilayaChange(id) },
            communeChange: { (id: Int?) in model.onCommuneChange(id) },
            showPhoneChange: { (show: Bool) in model.onShowPhoneChange(show) },
            next: { _ = model.next() },
            back: { model.back() },
            goTo: { (step: PostStep) in model.goTo(step) },
            viewListing: { (listing: Listing) in openListing(listing) },
            myListings: { openMyListings() },
            postAnother: { model.clearDraft() },
            retryEditing: { _ = model.loadEditing() },
            verifyEmail: { router.requestEmailVerification() },
            leave: leave
        )
    }

    /// Simulateur ou appareil sans caméra : le bouton est masqué (`PostCamera.isAvailable`) ; l'avis d'Android reste
    /// en filet de sécurité.
    private func openCamera() {
        if PostCamera.isAvailable {
            showsCamera = true
        } else {
            model.onCameraUnavailable()
        }
    }

    /// Nouveau dépôt : la fiche s'empile sur l'onglet Déposer. Modification : règles d'Android (voir
    /// `PostEditNavigation`).
    private func openListing(_ listing: Listing) {
        guard isEditing else {
            router.push(.detail(idOrSlug: listing.id))
            return
        }
        let tab = router.selectedTab
        router.setStack(PostEditNavigation.showingListing(listing.id, from: router.stack(for: tab)), for: tab)
    }

    private func openMyListings() {
        guard isEditing else {
            router.push(.myListings)
            return
        }
        let tab = router.selectedTab
        router.setStack(PostEditNavigation.showingMyListings(from: router.stack(for: tab)), for: tab)
    }
}
