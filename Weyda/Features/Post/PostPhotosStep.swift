import SwiftUI

/// Étape 4 — photos (Android : `PhotosStep`) : conseils, grille de 3 colonnes (la première photo est la principale),
/// puis « Galerie » et « Appareil photo » tant qu'il reste des places, et le compteur « 2 / 5 photos ». Chaque photo
/// ouvre son menu (photo principale, réessayer l'envoi, retirer) ; la croix la retire d'un appui. Envoi en cours :
/// voile et indicateur ; échec : voile rouge, icône et message.
struct PostPhotosStep: View {
    private let state: PostListingState
    private let actions: PostListingActions
    private let cameraAvailable: Bool

    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: WeydaSpace.sm),
        count: 3
    )

    init(state: PostListingState, actions: PostListingActions, cameraAvailable: Bool) {
        self.state = state
        self.actions = actions
        self.cameraAvailable = cameraAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeydaSpace.lg) {
            Text(L10n.postPhotosHint(state.maxPhotos))
                .weydaText(.bodyMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Self.columns, spacing: WeydaSpace.sm) {
                ForEach(Array(state.photos.enumerated()), id: \.element.id) { entry in
                    PostPhotoTile(
                        photo: entry.element,
                        index: entry.offset,
                        count: state.photos.count,
                        actions: actions
                    )
                }
                if state.remainingPhotoSlots > 0 {
                    PostAddPhotoTile(
                        title: L10n.postPhotoGallery,
                        systemImage: "photo.on.rectangle",
                        identifier: "post.photos.gallery",
                        action: actions.openGallery
                    )
                    if cameraAvailable {
                        PostAddPhotoTile(
                            title: L10n.postPhotoCamera,
                            systemImage: "camera",
                            identifier: "post.photos.camera",
                            action: actions.openCamera
                        )
                    }
                }
            }
            .weydaAnimation(.easeOut(duration: WeydaDuration.medium), value: state.photos)
            Text(L10n.postPhotoCount(state.photos.count, state.maxPhotos))
                .weydaText(.labelMedium)
                .foregroundStyle(WeydaColor.onSurfaceVariant)
                .accessibilityIdentifier("post.photos.count")
        }
    }
}

/// Une photo choisie : aperçu carré, état d'envoi, badge « Principale », menu d'actions, croix « Retirer ».
private struct PostPhotoTile: View {
    let photo: PhotoItem
    let index: Int
    let count: Int
    let actions: PostListingActions

    private static let removeSide: CGFloat = 28
    private static let statusIcon: CGFloat = 22

    private var isMain: Bool { index == 0 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Menu {
                menuItems
            } label: {
                tile
            }
            .accessibilityLabel(L10n.postUiPhotoPosition(index + 1, count))
            .accessibilityValue(statusText)
            .accessibilityIdentifier("post.photo.\(index)")
            removeButton
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if photo.status == .failed {
            Button {
                actions.retryPhoto(index)
            } label: {
                Label(L10n.postPhotoRetry, systemImage: "arrow.clockwise")
            }
        }
        if !isMain && photo.status == .done {
            Button {
                actions.makeMainPhoto(index)
            } label: {
                Label(L10n.postPhotoMakeMain, systemImage: "star")
            }
        }
        Button(role: .destructive) {
            actions.removePhoto(index)
        } label: {
            Label(L10n.postPhotoRemove, systemImage: "trash")
        }
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                PostFormPhotoImage(photo: photo, localURL: actions.localPhotoURL)
            }
            .overlay {
                statusOverlay
            }
            .overlay(alignment: .bottom) {
                if isMain && photo.status == .done {
                    mainBadge
                }
            }
            .background(WeydaPalette.imagePlaceholder)
            .clipShape(shape)
            .contentShape(shape)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch photo.status {
        case .uploading:
            ZStack {
                PostFormColors.scrim
                ProgressView()
                    .tint(PostFormColors.onScrim)
            }
        case .failed:
            ZStack {
                WeydaColor.error.opacity(0.8)
                VStack(spacing: WeydaSpace.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: Self.statusIcon))
                    Text(failureText)
                        .weydaText(.labelSmall)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(WeydaColor.onError)
                .padding(WeydaSpace.xs)
            }
        case .done:
            EmptyView()
        }
    }

    /// « Principale » sur un voile dégradé en bas de la première photo (Android : même badge).
    private var mainBadge: some View {
        Text(L10n.postPhotoMain)
            .weydaText(.labelSmall)
            .foregroundStyle(PostFormColors.onScrim)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, WeydaSpace.md)
            .padding(.bottom, WeydaSpace.xs + WeydaSpace.xxs)
            .background {
                LinearGradient(colors: WeydaPalette.photoScrim, startPoint: .top, endPoint: .bottom)
            }
    }

    /// Croix ronde en haut (côté fin de lecture) : 28 pt dessinés, 44 pt touchables.
    private var removeButton: some View {
        Button {
            actions.removePhoto(index)
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(PostFormColors.onScrim)
                .frame(width: Self.removeSide, height: Self.removeSide)
                .background(PostFormColors.removeBadge, in: Circle())
                .frame(width: WeydaSize.touchTarget, height: WeydaSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.postPhotoRemove)
        .accessibilityValue(L10n.postUiPhotoPosition(index + 1, count))
        .accessibilityIdentifier("post.photo.\(index).remove")
    }

    private var failureText: String {
        photo.errorMessage ?? L10n.postUiPhotoFailed
    }

    /// Ce que VoiceOver ajoute au rang de la photo : principale, envoi en cours, ou l'échec et sa raison.
    private var statusText: String {
        switch photo.status {
        case .uploading:
            return L10n.postUiPhotoUploading
        case .failed:
            return failureText
        case .done:
            return isMain ? L10n.postPhotoMain : ""
        }
    }
}

/// Case « Galerie » / « Appareil photo » : contour pointillé, pictogramme et libellé verts.
private struct PostAddPhotoTile: View {
    let title: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WeydaRadius.thumb, style: .continuous)
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: WeydaSpace.xs + WeydaSpace.xxs) {
                        Image(systemName: systemImage)
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(title)
                            .weydaText(.labelMedium)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(WeydaColor.primary)
                    .padding(WeydaSpace.sm)
                }
                .background(WeydaColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(WeydaColor.outline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .contentShape(shape)
        }
        .buttonStyle(WeydaPressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}
