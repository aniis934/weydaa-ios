import SafariServices
import SwiftUI
import UIKit

/// Page du site dans SFSafariViewController (Android : navigateur externe) : texte du site, cookies et lecteur
/// de Safari, l'utilisateur reste dans l'app. D'ordinaire présentée en feuille par `RootView`
/// (`router.push(.webPage(…))`) ; poussée par un `NavigationLink`, elle masque les barres de l'app (Safari a
/// les siennes) et son bouton « Fermer » revient en arrière.
struct WebPageView: View {
    private let page: WebPage
    @Environment(\.dismiss) private var dismiss

    init(page: WebPage) {
        self.page = page
    }

    var body: some View {
        SafariView(url: page.url()) {
            dismiss()
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.webPage")
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(WeydaColor.primary)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    /// « Fermer » de Safari : la feuille (ou l'écran poussé) se ferme côté SwiftUI, qui remet son état à zéro.
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        // `nonisolated` + `assumeIsolated` : juste, que le SDK isole ou non ce protocole sur le fil principal
        // (Safari appelle son délégué sur le fil principal).
        nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            MainActor.assumeIsolated {
                onFinish()
            }
        }
    }
}
