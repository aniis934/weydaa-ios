import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Sélecteurs de photos de l'assistant de dépôt — portage de `rememberPhotoPickers` (PhotoPickers.kt) : la galerie
// (sélecteur système, sans permission photo), l'appareil photo (permission `NSCameraUsageDescription`, Info.plist) et
// la miniature d'une photo déjà enregistrée en local (`PostPhotoStore`).
// Écarts iOS assumés : les octets sont lus tout de suite (Android gardait des URI `content://` avec un droit de lecture
// durable, perdus sinon à la mort du processus) ; la capture passe par `UIImagePickerController` en mémoire (Android :
// fichier du cache exposé par FileProvider + `TakePicture`).

// MARK: - API (contrat de la phase 4)

extension View {
    /// Galerie : `.photosPicker` d'iOS 16 (multi-sélection ≤ `limit`, images seulement, sans permission photo : le
    /// sélecteur tourne hors de l'app). Les octets d'origine (HEIC compris) sont chargés hors du fil principal puis
    /// remis à `onPicked` sur le fil principal, dans l'ordre de sélection ; un élément illisible est ignoré.
    func postGalleryPicker(isPresented: Binding<Bool>, limit: Int, onPicked: @escaping ([Data]) -> Void) -> some View {
        modifier(PostGalleryPickerModifier(isPresented: isPresented, limit: limit, onPicked: onPicked))
    }

    /// Appareil photo : `UIImagePickerController` (.camera) en plein écran ; la photo prise devient un JPEG 0,9
    /// (calculé hors du fil principal, orientation conservée dans l'EXIF) remis à `onCaptured`. Annulation : rien.
    func postCameraPicker(isPresented: Binding<Bool>, onCaptured: @escaping (Data) -> Void) -> some View {
        modifier(PostCameraPickerModifier(isPresented: isPresented, onCaptured: onCaptured))
    }
}

/// Appareil photo présent sur l'appareil (faux au simulateur) : l'écran masque le bouton « Appareil photo » sinon.
/// Isolé au fil principal (et non `nonisolated` comme prévu au contrat) : `UIImagePickerController` est une classe UIKit,
/// ses méthodes de classe aussi.
enum PostCamera {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}

// MARK: - Galerie

/// La sélection est vidée dès qu'elle arrive : le sélecteur rouvert repart de zéro (les photos déjà choisies vivent
/// dans le ViewModel, qui écarte les doublons). Sélection numérotée (`.ordered`) : la première choisie sera la
/// photo principale.
private struct PostGalleryPickerModifier: ViewModifier {
    @Binding private var isPresented: Bool
    private let limit: Int
    private let onPicked: ([Data]) -> Void
    @State private var selection: [PhotosPickerItem] = []

    init(isPresented: Binding<Bool>, limit: Int, onPicked: @escaping ([Data]) -> Void) {
        _isPresented = isPresented
        self.limit = limit
        self.onPicked = onPicked
    }

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selection,
                maxSelectionCount: max(limit, 1),
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: selection) { items in
                picked(items)
            }
    }

    private func picked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        selection = []
        let onPicked = self.onPicked
        Task {
            let images = await PostPhotoLoading.data(of: items)
            if !images.isEmpty {
                onPicked(images)
            }
        }
    }
}

// MARK: - Appareil photo

/// Plein écran : le sélecteur d'iOS ferme la couverture lui-même (photo gardée ou annulation).
private struct PostCameraPickerModifier: ViewModifier {
    @Binding private var isPresented: Bool
    private let onCaptured: (Data) -> Void

    init(isPresented: Binding<Bool>, onCaptured: @escaping (Data) -> Void) {
        _isPresented = isPresented
        self.onCaptured = onCaptured
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                PostCameraView(onFinish: { image in
                    finish(image)
                })
                .ignoresSafeArea()
            }
    }

    private func finish(_ image: UIImage?) {
        isPresented = false
        guard let image else { return }
        let onCaptured = self.onCaptured
        Task {
            guard let data = await PostPhotoLoading.jpeg(image) else { return }
            onCaptured(data)
        }
    }
}

/// `UIImagePickerController` en mode appareil photo, photos seulement (pas de vidéo : pas de micro à demander),
/// sans recadrage.
private struct PostCameraView: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Filet de sécurité : `.camera` sans appareil photo lève une exception Objective-C (plantage). L'écran masque
        // déjà le bouton dans ce cas ; à défaut, la photothèque (hors processus, sans permission) prend le relais.
        picker.sourceType = PostCamera.isAvailable ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.image.identifier]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    /// Délégué du sélecteur. Isolé au fil principal (isolation par défaut du module) : UIKit l'appelle sur le fil
    /// principal ; les protocoles de délégué d'UIKit le sont aussi (sinon : conformité isolée, déduite).
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

// MARK: - Miniature locale

/// Miniature d'une photo enregistrée en local (photo choisie, pas encore envoyée) : décodée HORS du fil principal à la
/// taille affichée × échelle de l'écran (ImageIO via `ImageDecoder`, le décodeur des photos distantes : réduction à la
/// source, orientation EXIF appliquée), annulée si la vue disparaît. Fond d'attente neutre pendant le décodage, icône
/// si le fichier est illisible. Remplit son cadre (`.scaledToFill`) : l'appelant fixe la taille et la forme.
/// Décorative pour VoiceOver : la cellule qui la porte annonce la photo.
struct LocalPhotoThumbnail: View {
    private let fileURL: URL
    @Environment(\.displayScale) private var displayScale
    @State private var decoded: LocalPhotoImage? = nil
    @State private var unreadableURL: URL? = nil

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    var body: some View {
        GeometryReader { proxy in
            content(size: proxy.size)
        }
        .accessibilityHidden(true)
    }

    private func content(size: CGSize) -> some View {
        let request = ImageRequest(url: fileURL, targetSize: size, scale: displayScale)
        let image: UIImage? = decoded?.url == fileURL ? decoded?.image : nil
        let unreadable = image == nil && unreadableURL == fileURL
        return ZStack {
            WeydaPalette.imagePlaceholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(.opacity)
            } else if unreadable {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(WeydaColor.onSurfaceVariant)
            }
        }
        .frame(width: size.width, height: size.height)
        .weydaAnimation(.easeOut(duration: WeydaDuration.short), value: decoded?.url)
        .task(id: request) {
            await load(request)
        }
    }

    private func load(_ request: ImageRequest) async {
        // Vue pas encore mesurée, ou déjà décodée à cette taille : rien à faire.
        guard request.hasTargetSize else { return }
        if let decoded, decoded.request == request { return }
        let image = await PostPhotoLoading.thumbnail(for: request)
        guard !Task.isCancelled else { return }
        if let image {
            decoded = LocalPhotoImage(request: request, image: image)
        } else {
            unreadableURL = request.url
        }
    }
}

/// Dernière miniature décodée, rattachée à sa demande (fichier + taille).
private struct LocalPhotoImage {
    let request: ImageRequest
    let image: UIImage

    var url: URL { request.url }
}

// MARK: - Travail hors du fil principal

private nonisolated enum PostPhotoLoading {
    /// Qualité du JPEG d'une photo prise (ImagePreparer la réduit ensuite à 1 600 px avant l'envoi).
    static let cameraJPEGQuality: CGFloat = 0.9

    /// Octets des éléments choisis, chargés en parallèle, rendus dans l'ordre de sélection ; illisibles écartés.
    @concurrent
    static func data(of items: [PhotosPickerItem]) async -> [Data] {
        await withTaskGroup(of: (Int, Data?).self, returning: [Data].self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let bytes: Data? = try? await item.loadTransferable(type: Data.self)
                    return (index, bytes)
                }
            }
            var loaded = [Data?](repeating: nil, count: items.count)
            for await result in group {
                loaded[result.0] = result.1
            }
            return loaded.compactMap { $0 }
        }
    }

    /// JPEG d'une photo prise (l'orientation part dans l'EXIF : ImagePreparer et les miniatures l'appliquent).
    @concurrent
    static func jpeg(_ image: UIImage) async -> Data? {
        image.jpegData(compressionQuality: cameraJPEGQuality)
    }

    /// Miniature d'un fichier local ; nil = illisible (ou demande annulée avant la lecture).
    @concurrent
    static func thumbnail(for request: ImageRequest) async -> UIImage? {
        guard !Task.isCancelled,
              let data = try? Data(contentsOf: request.url, options: .mappedIfSafe)
        else {
            return nil
        }
        return ImageDecoder.decode(data, for: request)
    }
}
