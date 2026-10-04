import XCTest

/// Tour de « Mes favoris » et « Mes alertes » (10l) en API simulée (`MockFixtures/routes-lists.json` + `lists/`) :
/// favoris (liste, glisser pour retirer, liste vidée, e-mail à vérifier) ; alertes (liste et critères, confirmation de
/// suppression, suppression jusqu'à la liste vide, ouverture d'une alerte → onglet Annonces filtré). Session simulée
/// `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`). Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourListsTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// « Annuler » dans les 3 langues : l'autre bouton de la confirmation est celui qui confirme.
    private static let cancelLabels: Set<String> = ["Annuler", "إلغاء", "Cancel"]
    /// Bouton du glissement d'un favori (« Retirer des favoris »), dans les 3 langues.
    private static let removeLabels: [String] = ["Retirer des favoris", "إزالة من المفضلة", "Remove from favorites"]
    /// Bouton du glissement d'une alerte (« Supprimer l'alerte »), dans les 3 langues.
    private static let deleteLabels: [String] = ["Supprimer l'alerte", "حذف التنبيه", "Delete alert"]
    private static let favoriteIds = ["mock-a3", "mock-a25", "mock-a17", "mock-a10", "mock-a14"]
    private static let alertIds = ["mock-s1", "mock-s2", "mock-s3", "mock-s4"]

    // MARK: - Favoris

    /// Cinq favoris (appartement, Clio, MacBook, Golf, Accent), cœurs pleins ; puis le bas de la liste.
    @MainActor
    func test10l01Favorites() {
        let app = launch(route: "favorites", screen: "favorites")
        waitFor("favorite.row.mock-a3", in: app)
        settle()
        pause()
        capture("10l-01-favorites-1")
        app.swipeUp()
        settle(0.8)
        capture("10l-01-favorites-2")
        app.terminate()
    }

    /// Glisser un favori vers le bord de fin : l'action « Retirer des favoris » apparaît (sans être déclenchée).
    @MainActor
    func test10l02FavoritesSwipe() {
        let app = launch(route: "favorites", screen: "favorites")
        let row = waitFor("favorite.row.mock-a25", in: app)
        settle(0.8)
        revealTrailingActions(of: row)
        settle(0.8)
        pause()
        capture("10l-02-favorites-swipe-1")
        app.terminate()
    }

    /// Les cinq retirés un à un (glisser puis « Retirer ») : l'état vide et « Parcourir les annonces ».
    @MainActor
    func test10l03FavoritesEmpty() {
        let app = launch(route: "favorites", screen: "favorites")
        waitFor("favorite.row.mock-a3", in: app)
        settle(0.8)
        for _ in 0..<(Self.favoriteIds.count + 3) {
            guard let row = firstExisting(Self.favoriteIds, prefix: "favorite.row.", in: app) else { break }
            revealTrailingActions(of: row)
            settle(0.6)
            tapFirstButton(labeled: Self.removeLabels, in: app)
            waitUntilGone(row)
        }
        XCTAssertNil(firstExisting(Self.favoriteIds, prefix: "favorite.row.", in: app), "la liste des favoris n'est pas vide")
        settle()
        pause()
        capture("10l-03-favorites-empty-1")
        app.terminate()
    }

    /// E-mail à vérifier (session simulée `unverified`) : bandeau « Vérifier » et explication, aucune requête.
    @MainActor
    func test10l04FavoritesUnverified() {
        continueAfterFailure = true
        let app = makeApp([
            "-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "favorites", "-WeydaLoggedIn", "unverified",
        ])
        app.launch()
        XCTAssertTrue(waitForScreen("favorites", in: app), "screen.favorites introuvable")
        waitFor("verifyEmailBanner", in: app)
        settle()
        pause()
        capture("10l-04-favorites-unverified-1")
        app.terminate()
    }

    // MARK: - Alertes

    /// Quatre alertes : nom, critères en puces (recherche, catégorie, lieu, prix, « +1 filtre »), date ; compteur
    /// « 4 / 5 » ; puis le bas : note et « Lancer une recherche ».
    @MainActor
    func test10l05Alerts() {
        let app = launch(route: "savedSearches", screen: "savedSearches")
        waitFor("alert.row.mock-s1", in: app)
        settle()
        pause()
        capture("10l-05-alerts-1")
        app.swipeUp()
        settle(0.8)
        capture("10l-05-alerts-2")
        app.terminate()
    }

    /// Glisser une alerte puis « Supprimer » : la confirmation « Supprimer cette alerte ? ».
    @MainActor
    func test10l06AlertDeleteConfirmation() {
        let app = launch(route: "savedSearches", screen: "savedSearches")
        let row = waitFor("alert.row.mock-s2", in: app)
        settle(0.8)
        revealTrailingActions(of: row)
        settle(0.6)
        tapFirstButton(labeled: Self.deleteLabels, in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "confirmation de suppression absente")
        settle(0.8)
        pause()
        capture("10l-06-alerts-confirm-1")
        app.terminate()
    }

    /// Suppression confirmée (ligne retirée, « Alerte supprimée », compteur « 3 / 5 »), puis les autres : la liste vide
    /// explique comment créer une alerte.
    @MainActor
    func test10l07AlertsDeleteUntilEmpty() {
        let app = launch(route: "savedSearches", screen: "savedSearches")
        waitFor("alert.row.mock-s1", in: app)
        settle(0.8)
        deleteAlert("mock-s1", in: app)
        let notice = app.descendants(matching: .any)["notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "message après la suppression absent")
        settle(0.6)
        capture("10l-07-alerts-deleted-1")
        for id in Self.alertIds.dropFirst() {
            deleteAlert(id, in: app)
        }
        XCTAssertNil(firstExisting(Self.alertIds, prefix: "alert.row.", in: app), "la liste des alertes n'est pas vide")
        settle()
        pause()
        capture("10l-08-alerts-empty-1")
        app.terminate()
    }

    /// Appui sur « Clio à Alger » : l'onglet Annonces, recherche « clio » + Véhicules + Alger appliquée, la Clio d'Alger.
    @MainActor
    func test10l09OpenAlert() {
        let app = launch(route: "savedSearches", screen: "savedSearches")
        waitFor("alert.row.mock-s1", in: app).tap()
        XCTAssertTrue(waitForScreen("listings", in: app), "screen.listings introuvable après l'ouverture de l'alerte")
        waitFor("listings.row.mock-a25", in: app)
        settle()
        pause()
        capture("10l-09-alerts-open-1")
        app.terminate()
    }

    // MARK: - Outils

    /// L'app d'un membre ouverte sur une route, son écran attendu.
    @MainActor
    private func launch(route: String, screen: String) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", route] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen(screen, in: app), "screen.\(screen) introuvable")
        return app
    }

    @MainActor
    @discardableResult
    private func waitFor(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(identifier) introuvable")
        return element
    }

    /// Première rangée encore présente parmi ces identifiants (`<prefix><id>`).
    @MainActor
    private func firstExisting(_ ids: [String], prefix: String, in app: XCUIApplication) -> XCUIElement? {
        for id in ids {
            let element = app.descendants(matching: .any)["\(prefix)\(id)"]
            if element.exists {
                return element
            }
        }
        return nil
    }

    /// Premier bouton dont le libellé est l'un de ceux-ci (bouton révélé par un glissement).
    @MainActor
    private func tapFirstButton(labeled labels: [String], in app: XCUIApplication) {
        let button = app.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [labels])).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "bouton \(labels.first ?? "") introuvable")
        if button.exists {
            button.tap()
        }
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement) {
        for _ in 0..<20 where element.exists {
            settle(0.25)
        }
    }

    /// Glissement lent vers le bord de FIN (gauche en français / anglais, droite en arabe), sur un tiers de la
    /// largeur : l'action du bord apparaît et reste ouverte, sans le glissement complet qui la déclencherait.
    @MainActor
    private func revealTrailingActions(of row: XCUIElement) {
        let rtl = environment["WEYDA_LANG"] == "ar"
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.1 : 0.9, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.45 : 0.55, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Glisser l'alerte, « Supprimer l'alerte », puis le bouton de la confirmation qui n'est pas « Annuler » ; attend
    /// que la rangée parte.
    @MainActor
    private func deleteAlert(_ id: String, in app: XCUIApplication) {
        let row = waitFor("alert.row.\(id)", in: app)
        revealTrailingActions(of: row)
        settle(0.6)
        tapFirstButton(labeled: Self.deleteLabels, in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "confirmation de suppression absente")
        settle(0.5)
        guard let confirm = alert.buttons.allElementsBoundByIndex.first(where: { !Self.cancelLabels.contains($0.label) }) else {
            XCTFail("bouton de confirmation introuvable")
            return
        }
        confirm.tap()
        waitUntilGone(row)
    }
}
