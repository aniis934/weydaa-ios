import XCTest

/// Tour de la coquille, en API simulée : lancement, onglets, démonstrations (Debug), À propos et écran
/// d'attente. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourTests: TourTestCase {
    /// Image figée de l'animation de lancement (le W à moitié écrit, puis le mot posé).
    @MainActor
    func test01LaunchFrames() {
        for (index, frame) in ["0.45", "0.95"].enumerated() {
            let app = makeApp(["-WeydaLaunchFrame", frame])
            app.launch()
            Thread.sleep(forTimeInterval: 1.5)
            capture(String(format: "00-launch-%d", index + 1))
            app.terminate()
        }
    }

    /// L'animation de lancement réelle, jusqu'à la barre d'onglets, puis chaque onglet.
    @MainActor
    func test02Tabs() {
        continueAfterFailure = true
        let app = makeApp()
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "barre d'onglets introuvable")
        pause()
        let buttons = tabBar.buttons
        let count = buttons.count
        XCTAssertEqual(count, 5, "5 onglets attendus")
        for index in 0..<count {
            buttons.element(boundBy: index).tap()
            let screen = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "screen."))
                .firstMatch
            XCTAssertTrue(screen.waitForExistence(timeout: 10), "écran de l'onglet \(index) introuvable")
            let name = screen.identifier.replacingOccurrences(of: "screen.", with: "")
            pause()
            capture(String(format: "%02d-%@", index + 1, name))
        }
    }

    /// Démonstration du système de design (Debug), parcourue de haut en bas.
    @MainActor
    func test03Showcase() {
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaScreen", "showcase"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.showcase"].waitForExistence(timeout: 20))
        pause()
        capture("90-showcase-1")
        for page in 2...3 {
            app.swipeUp()
            pause(0.8)
            capture("90-showcase-\(page)")
        }
    }

    /// Démonstration de la couche données (Debug) : vrais repositories sur l'API simulée, photos fictives.
    @MainActor
    func test04Data() {
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaScreen", "data"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.data"].waitForExistence(timeout: 20))
        // Données chargées (catégories de MockFixtures/catalog), puis le temps que les photos s'affichent.
        XCTAssertTrue(app.descendants(matching: .any)["data.category.vehicules"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.0)
        pause()
        capture("91-data-1")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.0)
        pause(0.8)
        capture("91-data-2")
    }

    /// Les composants communs seuls (cartes, lignes, puces, états, squelettes figés), de haut en bas.
    @MainActor
    func test04Components() {
        captureLaunch(["-WeydaScreen", "components"], name: "92-components", scrolls: 8, screen: "components")
    }

    /// « À propos et informations légales » (poussé sur l'onglet Profil), puis un écran d'attente (phase 3).
    @MainActor
    func test80About() {
        captureRoute("about", name: "80-about")
        captureRoute("favorites", name: "81-comingSoon")
    }
}
