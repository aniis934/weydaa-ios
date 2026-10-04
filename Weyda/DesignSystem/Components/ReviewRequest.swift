import StoreKit
import SwiftUI

extension View {
    /// Demande une note sur l'App Store quand `shouldAsk` PASSE à vrai (jamais au simple affichage d'un écran dont le
    /// drapeau est déjà vrai) ; le drapeau vient de `ReviewPrompter.record(_:)`. Petit délai : le résultat (annonce
    /// publiée, avis envoyé…) s'affiche d'abord. iOS décide seul d'afficher la demande.
    func requestsReview(when shouldAsk: Bool) -> some View {
        modifier(ReviewRequestModifier(shouldAsk: shouldAsk))
    }
}

private struct ReviewRequestModifier: ViewModifier {
    let shouldAsk: Bool
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content
            .onChange(of: shouldAsk) { asks in
                guard asks else { return }
                let request = requestReview
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    request()
                }
            }
    }
}
