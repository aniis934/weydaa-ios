import XCTest

/// Tour du dépôt d'annonce (7x) en API simulée (`MockFixtures/routes-post.json`) : visiteur, assistant vide, chaque
/// étape remplie (brouillons simulés `-WeydaPostDraft`, la Clio 4 de `MockFixtures/post/drafts/`), erreurs de saisie,
/// photo en échec, e-mail à vérifier, publication puis résultat, modification d'une annonce de « Mes annonces ».
/// Le dossier des brouillons est vidé à chaque lancement en API simulée : chaque capture part de son brouillon seul.
/// Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourPostTests: TourTestCase {
    private static let postTab = ["-WeydaRoute", "tab:post"]
    /// Session simulée ouverte, e-mail vérifié (utilisateur fictif `mock-me`, téléphone de démonstration).
    private static let member = ["-WeydaLoggedIn", "YES"]

    private static func draft(_ name: String) -> [String] {
        ["-WeydaPostDraft", name]
    }

    /// Onglet Déposer d'un visiteur : invitation à se connecter.
    @MainActor
    func test70Guest() {
        captureRoute("tab:post", name: "70-post-guest", screen: "postGuest")
    }

    /// Assistant vide : grille des catégories.
    @MainActor
    func test71aEmpty() {
        captureLaunch(Self.postTab + Self.member, name: "71-post-empty", scrolls: 1, screen: "post")
    }

    /// E-mail non vérifié : bandeau « Vérifier » au-dessus de l'assistant.
    @MainActor
    func test71bUnverified() {
        captureLaunch(
            Self.postTab + ["-WeydaLoggedIn", "unverified"] + Self.draft("step-details"),
            name: "71-post-unverified",
            screen: "post"
        )
    }

    /// Catégorie choisie (Véhicules › Voitures) : grille puis sous-catégories.
    @MainActor
    func test72Category() {
        captureLaunch(Self.postTab + Self.member + Self.draft("step-category"), name: "72-post-category", scrolls: 1, screen: "post")
    }

    /// Caractéristiques de la Renault Clio (marque, modèle dépendant, année, kilométrage…).
    @MainActor
    func test73Attributes() {
        captureLaunch(Self.postTab + Self.member + Self.draft("step-attributes"), name: "73-post-attributes", scrolls: 2, screen: "post")
    }

    /// Infos et prix : compteurs, type de prix, prix groupé.
    @MainActor
    func test74aDetails() {
        captureLaunch(Self.postTab + Self.member + Self.draft("step-details"), name: "74-post-details", scrolls: 1, screen: "post")
    }

    /// Infos trop courtes, puis « Suivant » : erreurs sous les champs.
    @MainActor
    func test74bDetailsInvalid() {
        captureAfterNext(
            Self.postTab + Self.member + Self.draft("details-invalid"),
            name: "74-post-details-invalid",
            screen: "post"
        )
    }

    /// Photos envoyées, la première marquée « Principale ».
    @MainActor
    func test75aPhotos() {
        captureLaunch(Self.postTab + Self.member + Self.draft("step-photos"), name: "75-post-photos", screen: "post")
    }

    /// Une photo dont l'envoi a échoué (fichier local absent) : voile rouge et message.
    @MainActor
    func test75bPhotosFailed() {
        continueAfterFailure = true
        let app = launchPost(Self.postTab + Self.member + Self.draft("photos-failed"))
        let failed = app.descendants(matching: .any)["post.photo.2"]
        XCTAssertTrue(failed.waitForExistence(timeout: 15), "post.photo.2 introuvable")
        settle(2.5)
        pause()
        capture("75-post-photos-failed-1")
        app.terminate()
    }

    /// Wilaya et commune choisies, « Afficher mon numéro ».
    @MainActor
    func test76Location() {
        captureLaunch(Self.postTab + Self.member + Self.draft("step-location"), name: "76-post-location", screen: "post")
    }

    /// Récapitulatif complet, de haut en bas.
    @MainActor
    func test77Review() {
        captureLaunch(Self.postTab + Self.member + Self.draft("step-review"), name: "77-post-review", scrolls: 2, screen: "post")
    }

    /// « Publier l'annonce » depuis le récapitulatif : écran de résultat (annonce en vérification).
    @MainActor
    func test78Result() {
        captureAfterNext(
            Self.postTab + Self.member + Self.draft("step-review"),
            name: "78-postResult",
            screen: "postResult"
        )
    }

    /// Modifier une annonce de « Mes annonces » (vélo `mock-m3`) : ouverture sur le récapitulatif.
    @MainActor
    func test79Edit() {
        captureLaunch(["-WeydaRoute", "editListing:mock-m3"] + Self.member, name: "79-postEdit", scrolls: 1, screen: "postEdit")
    }

    // MARK: - Outils

    /// L'app lancée sur l'assistant (lancement sauté, animations figées), `screen.post` attendu.
    @MainActor
    private func launchPost(_ arguments: [String]) -> XCUIApplication {
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES"] + arguments)
        app.launch()
        XCTAssertTrue(waitForScreen("post", in: app), "screen.post introuvable (\(arguments.joined(separator: " ")))")
        return app
    }

    /// Appui sur « Suivant » / « Publier » une fois actif (catégories et attributs chargés), puis capture de l'écran
    /// attendu (`screen.<screen>`).
    @MainActor
    private func captureAfterNext(_ arguments: [String], name: String, screen: String) {
        continueAfterFailure = true
        let app = launchPost(arguments)
        let next = app.buttons["post.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "post.next introuvable")
        waitUntilEnabled(next)
        settle(1)
        next.tap()
        XCTAssertTrue(waitForScreen(screen, in: app, timeout: 30), "screen.\(screen) introuvable après post.next")
        settle()
        pause()
        capture("\(name)-1")
        app.terminate()
    }

    /// « Suivant » reste inactif tant que catégories et attributs se chargent.
    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isEnabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(element.isEnabled, "\(element.identifier) reste inactif")
    }
}
