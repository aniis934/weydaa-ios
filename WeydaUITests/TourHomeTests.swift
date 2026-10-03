import XCTest

/// Tour de l'accueil, en API simulée (`MockFixtures/routes-home.json` + le catalogue de la phase 1) : l'écran de
/// haut en bas, puis la feuille des catégories, ouverte dès le lancement par `-WeydaHomeSheet categories` (une
/// feuille n'a pas de route `-WeydaRoute`) — aucun appui hasardeux dans une rangée qui défile.
final class TourHomeTests: TourTestCase {
    /// `10-home-1` (recherche, catégories, À la une) puis 3 défilements (Tendances, Annonces récentes…).
    @MainActor
    func test10Home() {
        captureRoute("tab:home", name: "10-home", scrolls: 3)
    }

    /// `11-categories-1` : les catégories racines ; `11-categories-2` : les sous-catégories de Véhicules.
    @MainActor
    func test11Categories() {
        continueAfterFailure = true
        let app = launchWithCategoriesSheet()
        guard waitForScreen("categories", in: app) else {
            XCTFail("screen.categories introuvable")
            app.terminate()
            return
        }
        settle()
        pause()
        capture("11-categories-1")

        let vehicles = app.descendants(matching: .any)["categories.row.vehicules"]
        if vehicles.waitForExistence(timeout: 10) {
            vehicles.tap()
            XCTAssertTrue(waitForScreen("subcategories", in: app, timeout: 10), "screen.subcategories introuvable")
            settle(0.8)
            pause()
            capture("11-categories-2")
        } else {
            XCTFail("ligne « Véhicules » introuvable")
        }
        app.terminate()
    }

    /// `12-categories-search-1` : « electro » tapé sans accent trouve Électronique, Électroménager et Petit
    /// électroménager (noms dans la langue de l'app : la recherche porte sur les trois langues à la fois).
    @MainActor
    func test12CategoriesSearch() {
        continueAfterFailure = true
        let app = launchWithCategoriesSheet()
        XCTAssertTrue(waitForScreen("categories", in: app), "screen.categories introuvable")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 10) {
            field.tap()
            field.typeText("electro")
            settle(0.8)
            pause()
            capture("12-categories-search-1")
        } else {
            XCTFail("champ de recherche de la feuille introuvable")
        }
        app.terminate()
    }

    /// L'accueil, feuille des catégories ouverte (lancement sauté, animations décoratives figées).
    @MainActor
    private func launchWithCategoriesSheet() -> XCUIApplication {
        let app = makeApp([
            "-WeydaSkipLaunch", "YES",
            "-WeydaFreezeMotion", "YES",
            "-WeydaRoute", "tab:home",
            "-WeydaHomeSheet", "categories",
        ])
        app.launch()
        return app
    }
}
