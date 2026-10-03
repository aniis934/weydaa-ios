import Combine
import SwiftUI

/// Feuille de connexion (`AppRouter.authFlow`, présentée par `RootView`) : connexion, inscription, mot de passe oublié,
/// nouveau mot de passe, code e-mail — les routes `auth/*` d'Android regroupées dans UNE feuille avec sa propre pile
/// (convention iOS : l'écran d'où l'on vient reste en place dessous). Elle suit la session : une connexion réussie la
/// ferme d'elle-même ; un compte à l'e-mail non vérifié passe à l'étape du code dans la même feuille (Android :
/// `afterAuth`, qui retire les écrans d'auth puis ouvre la vérification).
struct AuthFlowView: View {
    @EnvironmentObject private var container: AppContainer
    private let entry: AuthEntry

    init(entry: AuthEntry) {
        self.entry = entry
    }

    var body: some View {
        AuthFlowHost(
            model: AuthFlowModel(
                entry: entry,
                currentUser: container.sessionManager.user,
                sessionUser: container.sessionManager.$user.eraseToAnyPublisher()
            )
        )
    }
}

/// Pile de la feuille et suivi de la session (sans interface : testé seul).
final class AuthFlowModel: ObservableObject {
    /// Première étape (sans bouton retour) ; remplacée après une connexion (code e-mail) ou un nouveau mot de passe.
    @Published private(set) var root: AuthEntry
    /// Étapes poussées au-dessus de la racine (pile de navigation de la feuille).
    @Published var path: [AuthEntry] = []
    /// Connexion aboutie (e-mail vérifié) : la feuille se ferme.
    @Published private(set) var isFinished: Bool = false
    /// Le code e-mail vient de partir (inscription) : l'étape du code démarre avec le délai de renvoi.
    private(set) var codeJustSent: Bool = false

    private var userId: String?
    private var subscription: AnyCancellable?

    init(entry: AuthEntry, currentUser: User?, sessionUser: AnyPublisher<User?, Never>) {
        userId = currentUser?.id
        root = AuthFlowModel.initialRoot(for: entry, user: currentUser)
        subscription = sessionUser.sink { [weak self] user in
            self?.sessionChanged(to: user)
        }
    }

    /// Un visiteur n'a pas d'e-mail à vérifier : il se connecte d'abord (Android : garde des écrans de membre).
    nonisolated static func initialRoot(for entry: AuthEntry, user: User?) -> AuthEntry {
        if entry == .verifyEmail && user == nil {
            return .login
        }
        return entry
    }

    /// L'étape visible.
    var current: AuthEntry { path.last ?? root }

    /// Ouverture ou fermeture de session pendant que la feuille est là.
    func sessionChanged(to user: User?) {
        let previous = userId
        userId = user?.id
        guard let user else {
            // Session fermée pendant le code (jetons révoqués, compte supprimé ailleurs) : plus rien à vérifier.
            if previous != nil && (root == .verifyEmail || path.contains(.verifyEmail)) {
                path = []
                root = .login
            }
            return
        }
        // Même compte (code accepté, profil relu…) : la feuille ne bouge pas.
        guard user.id != previous else { return }
        if user.emailVerified {
            isFinished = true
        } else {
            codeJustSent = current == .register
            path = []
            root = .verifyEmail
        }
    }

    /// Ouvre une étape ; déjà dans la pile (ou à la racine), on y revient au lieu de l'empiler encore : Connexion et
    /// Inscription ne s'empilent jamais sans fin (Android : `popBackStack(Login)`, sinon `navigate`).
    func show(_ entry: AuthEntry) {
        if root == entry {
            path = []
            return
        }
        if let index = path.firstIndex(of: entry) {
            path = Array(path.prefix(through: index))
            return
        }
        path.append(entry)
    }

    /// Repart de cette étape (nouveau mot de passe enregistré → connexion).
    func restart(at entry: AuthEntry) {
        path = []
        root = entry
    }

    /// « Plus tard », « Continuer », « Fermer ».
    func finish() {
        isFinished = true
    }
}

/// Possède le modèle de la feuille ; la ferme en remettant `router.authFlow` à nil (glissée vers le bas, SwiftUI le
/// fait seul). Une page légale touchée sous un formulaire s'ouvre par-dessus, la saisie reste en place.
private struct AuthFlowHost: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: AuthFlowModel
    @State private var presentedPage: WebPage? = nil

    init(model: @autoclosure @escaping () -> AuthFlowModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            step(model.root)
                .navigationDestination(for: AuthEntry.self) { entry in
                    step(entry)
                }
        }
        .tint(WeydaColor.primary)
        .sheet(item: $presentedPage) { page in
            WebPageView(page: page)
        }
        .onChange(of: model.isFinished) { finished in
            if finished {
                router.authFlow = nil
            }
        }
    }

    private func step(_ entry: AuthEntry) -> some View {
        AuthStep(entry: entry, model: model, onOpenPage: openPage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.close, action: close)
                        .accessibilityIdentifier("auth.close")
                }
            }
    }

    private func openPage(_ page: WebPage) {
        presentedPage = page
    }

    private func close() {
        model.finish()
    }
}

/// L'écran d'une étape et ses enchaînements.
private struct AuthStep: View {
    let entry: AuthEntry
    let model: AuthFlowModel
    let onOpenPage: (WebPage) -> Void

    var body: some View {
        switch entry {
        case .login:
            LoginView(
                onRegister: { model.show(.register) },
                onForgotPassword: { model.show(.forgotPassword) },
                onOpenPage: onOpenPage
            )
        case .register:
            RegisterView(
                onLogin: { model.show(.login) },
                onOpenPage: onOpenPage
            )
        case .forgotPassword:
            ForgotPasswordView(onLogin: { model.show(.login) })
        case .verifyEmail:
            VerifyEmailView(
                startsWithCooldown: model.codeJustSent,
                onDone: { model.finish() }
            )
        case .resetPassword(let token):
            ResetPasswordView(token: token, onLogin: { model.restart(at: .login) })
        }
    }
}
