import AuthenticationServices
import Foundation
import os
import UIKit

/// Connexions Apple / Google SIMULÉES : en API simulée (Debug, `-WeydaMockAPI YES`), aucune fenêtre système ne
/// s'ouvre — les captures restent reproductibles et l'entitlement « Sign in with Apple » n'est pas requis.
nonisolated enum AuthSimulation {
    static var isEnabled: Bool {
        #if DEBUG
        return LaunchOptions.mockAPI
        #else
        return false
        #endif
    }
}

/// Reprise UNIQUE d'une continuation : un rappel du système arrivé deux fois (délégué, fin de session web, échec de
/// `start()`) est ignoré au lieu de faire planter l'app.
nonisolated final class SingleResume<Value: Sendable>: @unchecked Sendable {
    // `@unchecked` : le seul état mutable (la continuation) est protégé par le verrou.
    private let lock = OSAllocatedUnfairLock()
    private var continuation: CheckedContinuation<Value, any Error>?

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, any Error>) {
        let pending: CheckedContinuation<Value, any Error>? = lock.withLockUnchecked {
            let current = continuation
            continuation = nil
            return current
        }
        pending?.resume(with: result)
    }
}

/// Ancrage des fenêtres système de connexion (feuille Apple, page Google) : la fenêtre clé de la scène active.
nonisolated final class AuthPresentationContext: NSObject,
    ASAuthorizationControllerPresentationContextProviding,
    ASWebAuthenticationPresentationContextProviding {

    // Le système appelle ces méthodes sur le fil principal. `nonisolated` + `assumeIsolated` : juste, que le SDK
    // isole ou non ces protocoles sur le fil principal (même principe que `WebPageView`).
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.keyWindow() }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { Self.keyWindow() }
    }

    @MainActor
    static func keyWindow() -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first {
            return window
        }
        if let scene {
            return UIWindow(windowScene: scene)
        }
        return UIWindow()
    }
}
