import XCTest

/// Tour de la feuille de connexion (5x) en API simulée (`MockFixtures/routes-auth.json`) : chaque route `-WeydaRoute`
/// (`login`, `register`, `forgot`, `verify`, `reset:<jeton>`) ouvre la feuille à cette étape, au-dessus de l'onglet
/// Profil. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourAuthTests: TourTestCase {
    /// Connexion : e-mail, mot de passe, « Mot de passe oublié ? », Apple (simulé), conditions, lien d'inscription.
    @MainActor
    func test50Login() {
        captureRoute("login", name: "50-login", scrolls: 1)
    }

    /// Inscription : nom, e-mail, mot de passe (règles), téléphone facultatif, Apple, conditions.
    @MainActor
    func test51Register() {
        captureRoute("register", name: "51-register", scrolls: 1)
    }

    /// Inscription en erreur : valeurs refusées pré-remplies (`-WeydaAuthDemo invalid`, sans clavier : fiable dans
    /// les trois langues), une erreur sous chaque champ.
    @MainActor
    func test52RegisterErrors() {
        captureLaunch(
            ["-WeydaRoute", "register", "-WeydaAuthDemo", "invalid"],
            name: "52-register-errors",
            scrolls: 1,
            screen: "register"
        )
    }

    /// Mot de passe oublié : l'e-mail du compte.
    @MainActor
    func test53ForgotPassword() {
        captureRoute("forgot", name: "53-forgotPassword")
    }

    /// Nouveau mot de passe (lien de l'e-mail) : deux champs, règles.
    @MainActor
    func test54ResetPassword() {
        captureRoute("reset:mock-reset-token", name: "54-resetPassword")
    }

    /// Code e-mail d'un compte à vérifier (session simulée `unverified`) : code à 6 chiffres, renvoi, « Plus tard ».
    @MainActor
    func test55VerifyEmail() {
        captureLaunch(
            ["-WeydaRoute", "verify", "-WeydaLoggedIn", "unverified"],
            name: "55-verifyEmail",
            screen: "verifyEmail"
        )
    }
}
