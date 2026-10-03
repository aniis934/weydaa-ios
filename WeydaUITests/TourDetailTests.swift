import XCTest

/// Tour de la fiche d'une annonce (3x) et du profil vendeur (34) en API simulée (`MockFixtures/routes-detail.json`).
/// Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourDetailTests: TourTestCase {
    /// Fiche d'un véhicule « à la une » : 8 photos, 10 caractéristiques, vendeuse, avis, conseils, similaires ;
    /// barre du bas d'un visiteur (offre, numéro, contact).
    @MainActor
    func test30DetailVehicle() {
        captureRoute("detail:mock-a2", name: "30-detail", scrolls: 3)
    }

    /// Galerie plein écran : appui sur la photo, puis photo suivante.
    @MainActor
    func test31Gallery() {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "detail:mock-a2"])
        app.launch()
        XCTAssertTrue(waitForScreen("detail", in: app), "screen.detail introuvable")
        let gallery = app.descendants(matching: .any)["detail.gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10), "detail.gallery introuvable")
        settle()
        gallery.tap()
        XCTAssertTrue(waitForScreen("gallery", in: app, timeout: 10), "screen.gallery introuvable")
        settle()
        pause()
        capture("31-gallery-1")
        // Photo suivante : à droite en français et en anglais, à gauche en arabe (pages retournées).
        if environment["WEYDA_LANG"] == "ar" {
            app.swipeRight()
        } else {
            app.swipeLeft()
        }
        settle(0.8)
        capture("31-gallery-2")
        app.terminate()
    }

    /// Fiche vendue : bandeau « Article vendu », aucune action de contact.
    @MainActor
    func test32DetailSold() {
        captureRoute("detail:mock-sold-1", name: "32-detail-sold", scrolls: 1)
    }

    /// Feuille « Signaler cette annonce » : réservée aux membres, ouverte en Debug par `-WeydaDetailSheet report`
    /// (l'API simulée n'a pas de session).
    @MainActor
    func test33Report() {
        captureLaunch(
            ["-WeydaRoute", "detail:mock-a2", "-WeydaDetailSheet", "report"],
            name: "33-report",
            screen: "report"
        )
    }

    /// Profil d'un vendeur recommandé : en-tête, badges, avis, vitrine.
    @MainActor
    func test34Seller() {
        captureRoute("seller:mock-u1", name: "34-seller", scrolls: 1)
    }

    /// Annonce disparue : état « Cette annonce n'est plus disponible » (pas de « Réessayer » en boucle).
    @MainActor
    func test35DetailGone() {
        captureRoute("detail:mock-gone", name: "35-detail-gone")
    }
}
