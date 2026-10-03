import XCTest

/// Tour du compte (6x) en API simulée (`MockFixtures/routes-account.json`) : profil visiteur puis membre (session
/// simulée `-WeydaLoggedIn`, utilisateur fictif `mock-me`), formulaires du compte, mes annonces, mes données, contact.
/// Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourAccountTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]

    /// Profil d'un visiteur : se connecter / créer un compte, langue (vers les Réglages), contact, informations légales.
    @MainActor
    func test60ProfileGuest() {
        captureRoute("tab:account", name: "60-account-guest", screen: "account")
    }

    /// Profil d'un membre : en-tête, statistiques, menu du compte, langue, déconnexion.
    @MainActor
    func test61Profile() {
        captureLaunch(["-WeydaRoute", "tab:account"] + Self.member, name: "61-profile", scrolls: 2, screen: "profile")
    }

    /// Profil dont l'e-mail reste à vérifier : badge « non vérifié » et bandeau « Vérifier ».
    @MainActor
    func test62ProfileUnverified() {
        captureLaunch(
            ["-WeydaRoute", "tab:account", "-WeydaLoggedIn", "unverified"],
            name: "62-profile-unverified",
            screen: "profile"
        )
    }

    /// Modifier le profil, pré-rempli par `GET /api/users/me`.
    @MainActor
    func test63EditProfile() {
        captureLaunch(["-WeydaRoute", "editProfile"] + Self.member, name: "63-editProfile", screen: "editProfile")
    }

    /// Changer le mot de passe.
    @MainActor
    func test64ChangePassword() {
        captureLaunch(["-WeydaRoute", "changePassword"] + Self.member, name: "64-changePassword", screen: "changePassword")
    }

    /// Mes annonces, tous statuts : en attente, refusée (motifs de modération), en ligne, vendue, expirée.
    @MainActor
    func test65MyListings() {
        captureLaunch(["-WeydaRoute", "myListings"] + Self.member, name: "65-myListings", scrolls: 1, screen: "myListings")
    }

    /// Mes annonces filtrées sur « Refusées » (appui sur la puce).
    @MainActor
    func test66MyListingsRejected() {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "myListings"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("myListings", in: app), "screen.myListings introuvable")
        let chip = app.descendants(matching: .any)["myListings.filter.rejected"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "myListings.filter.rejected introuvable")
        settle()
        // Libellés plus longs en français : la dernière puce dépasse l'écran → faire défiler la barre d'abord (vers
        // la fin de la lecture : à gauche en LTR, à droite en arabe).
        if !chip.isHittable {
            let bar = app.scrollViews.containing(.any, identifier: "myListings.filter.all").firstMatch
            if environment["WEYDA_LANG"] == "ar" {
                bar.swipeRight()
            } else {
                bar.swipeLeft()
            }
            settle(1)
        }
        chip.tap()
        let row = app.descendants(matching: .any)["myListings.row.mock-m6"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "myListings.row.mock-m6 introuvable")
        settle()
        pause()
        capture("66-myListings-rejected-1")
        app.terminate()
    }

    /// Mes données : export, puis suppression du compte (mot de passe).
    @MainActor
    func test67AccountData() {
        captureLaunch(["-WeydaRoute", "accountData"] + Self.member, name: "67-accountData", scrolls: 1, screen: "accountData")
    }

    /// Nous contacter, pré-rempli pour un membre.
    @MainActor
    func test68Contact() {
        captureLaunch(["-WeydaRoute", "contact"] + Self.member, name: "68-contact", screen: "contact")
    }
}
