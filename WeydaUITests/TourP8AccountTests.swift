import XCTest

/// Tour de la phase 8 côté compte (11a) en API simulée : grands titres (Mes annonces, Profil visiteur, porte « Se
/// connecter »), appui long sur une carte de « Mes annonces » (menu et aperçu), feuilles d'actions iOS (déconnexion,
/// vendu, supprimer, abandon des modifications), feuille de connexion remplie qu'un glissement ne ferme pas. Session
/// simulée `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`). Socle commun : `TourSupport.swift`.
final class TourP8AccountTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// Annonce en ligne de « Mes annonces » (vendre, supprimer, appui long) et annonce à modifier.
    private static let active = "mock-m1"
    private static let editable = "mock-m3"

    // MARK: - Grands titres

    /// « Mes annonces » : grand titre, puces de statut en tête de la liste ; puis défilée (titre replié).
    @MainActor
    func test11a01MyListingsLargeTitle() {
        captureLaunch(
            ["-WeydaRoute", "myListings"] + Self.member,
            name: "11a-01-myListings-largeTitle",
            scrolls: 1,
            screen: "myListings"
        )
    }

    /// Profil d'un visiteur : grand titre.
    @MainActor
    func test11a08GuestProfileLargeTitle() {
        captureRoute("tab:account", name: "11a-08-account-guestLargeTitle", screen: "account")
    }

    /// Écran de membre ouvert par un visiteur : la porte « Se connecter », en grand titre.
    @MainActor
    func test11a09LoginRequiredLargeTitle() {
        captureRoute("myListings", name: "11a-09-loginRequired-largeTitle", screen: "loginRequired")
    }

    // MARK: - Appui long

    /// Appui long sur la carte d'une annonce en ligne : aperçu et menu (Modifier, Marquer vendu, Supprimer…).
    @MainActor
    func test11a02MyListingsContextMenu() {
        let app = openActiveListings()
        let row = app.buttons.matching(identifier: "myListings.row.\(Self.active)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "myListings.row.\(Self.active) introuvable")
        settle(0.8)
        row.press(forDuration: 1.0)
        settle(1.0)
        capture("11a-02-myListings-contextMenu-1")
        pause()
        app.terminate()
    }

    // MARK: - Feuilles d'actions

    /// « Marquer comme vendu ? » en feuille d'actions.
    @MainActor
    func test11a03SoldSheet() {
        let app = openActiveListings()
        tapButton("myListing.sold.\(Self.active)", in: app)
        XCTAssertNotNil(actionSheet(in: app), "feuille « vendu » absente")
        settle(0.8)
        capture("11a-03-myListings-soldSheet-1")
        pause()
        app.terminate()
    }

    /// « Supprimer l'annonce ? » en feuille d'actions (bouton rouge).
    @MainActor
    func test11a04DeleteSheet() {
        let app = openActiveListings()
        tapButton("myListing.delete.\(Self.active)", in: app)
        XCTAssertNotNil(actionSheet(in: app), "feuille « supprimer » absente")
        settle(0.8)
        capture("11a-04-myListings-deleteSheet-1")
        pause()
        app.terminate()
    }

    /// Profil d'un membre : « Se déconnecter » (en bas de la liste) → feuille d'actions.
    @MainActor
    func test11a05LogoutSheet() {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "tab:account"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("profile", in: app), "screen.profile introuvable")
        settle()
        let logout = reveal("profile.logout", in: app)
        guard logout.exists else {
            XCTFail("profile.logout introuvable")
            app.terminate()
            return
        }
        logout.tap()
        XCTAssertNotNil(actionSheet(in: app), "feuille « déconnexion » absente")
        settle(0.8)
        capture("11a-05-profile-logoutSheet-1")
        pause()
        app.terminate()
    }

    /// Modification d'une annonce : une étape rouverte depuis le récapitulatif (modification en cours), retour au
    /// récapitulatif, puis retour → feuille « Abandonner les modifications ? ».
    @MainActor
    func test11a06DiscardSheet() {
        continueAfterFailure = true
        let app = makeApp(
            ["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "editListing:\(Self.editable)"] + Self.member
        )
        app.launch()
        XCTAssertTrue(waitForScreen("postEdit", in: app), "screen.postEdit introuvable")
        tapButton("post.review.edit.category", in: app, timeout: 20)
        settle(1.0)
        // Étape rouverte : le retour maison ramène au récapitulatif…
        tapButton("post.navBack", in: app)
        settle(1.0)
        // … puis, modifications en cours, demande confirmation.
        tapButton("post.navBack", in: app)
        XCTAssertNotNil(actionSheet(in: app), "feuille « abandonner » absente")
        settle(0.8)
        capture("11a-06-postEdit-discardSheet-1")
        pause()
        app.terminate()
    }

    // MARK: - Connexion

    /// Feuille de connexion remplie (inscription pré-remplie `-WeydaAuthDemo invalid`, sans clavier : fiable dans les
    /// trois langues) : glissée vers le bas par sa barre, elle reste ouverte.
    @MainActor
    func test11a07FilledSignInSheetStaysOpen() {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "register", "-WeydaAuthDemo", "invalid"])
        app.launch()
        XCTAssertTrue(waitForScreen("register", in: app), "screen.register introuvable")
        settle()
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        settle()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.register"].exists,
            "la feuille remplie s'est fermée d'un glissement"
        )
        capture("11a-07-register-filled-1")
        pause()
        app.terminate()
    }

    // MARK: - Outils

    /// « Mes annonces », onglet « En ligne » (2e puce, toujours à l'écran) : l'annonce active est en tête.
    @MainActor
    private func openActiveListings() -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "myListings"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("myListings", in: app), "screen.myListings introuvable")
        let chip = app.descendants(matching: .any)["myListings.filter.active"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "myListings.filter.active introuvable")
        settle(0.8)
        chip.tap()
        settle()
        let sold = app.buttons.matching(identifier: "myListing.sold.\(Self.active)").firstMatch
        XCTAssertTrue(sold.waitForExistence(timeout: 10), "myListing.sold.\(Self.active) introuvable")
        return app
    }

    @MainActor
    private func tapButton(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(identifier) introuvable")
        button.tap()
    }

    /// Fait défiler la liste jusqu'à ce que le bouton soit bien à l'écran (cadres comparés : `isHittable` échoue sur un
    /// élément hors écran au lieu de répondre faux).
    @MainActor
    private func reveal(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        for _ in 0..<6 {
            if button.exists && isOnScreen(button, in: app) {
                return button
            }
            app.swipeUp()
            settle(0.8)
        }
        return button
    }

    /// Sous la barre de navigation ; son milieu (là où `tap()` appuie) au-dessus de la barre d'onglets.
    @MainActor
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        guard !frame.isEmpty, !window.isEmpty else { return false }
        return frame.minY > window.minY + 120 && frame.midY < window.maxY - 100
    }

    /// La feuille d'actions (`confirmationDialog`) : `app.sheets` sur iPhone ; repli sur un popover (iOS 26 peut ancrer
    /// la feuille) puis sur une alerte. Nil au bout du délai.
    @MainActor
    private func actionSheet(in app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let candidates: [XCUIElement] = [app.sheets.firstMatch, app.popovers.firstMatch, app.alerts.firstMatch]
            if let found = candidates.first(where: { $0.exists }) {
                return found
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }
}
