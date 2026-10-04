import XCTest

/// Tour de la phase 8, lot BROWSE (11b), en API simulée : appui long sur une carte d'annonce (aperçu + menu), grands
/// titres de « Mes favoris » et « Mes alertes », favori retiré puis « Annuler » (bannière), alerte supprimée sans
/// confirmation puis « Annuler », filtres modifiés + « Fermer » → feuille d'actions « Abandonner les modifications ? »,
/// raccourci « Rechercher » de l'icône (`-WeydaShortcut search` : onglet Annonces, champ focalisé). Membre simulé
/// `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`) pour les listes. Bannières éphémères : attendues, jamais
/// exigées. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourP8BrowseTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// Bouton du glissement d'un favori (« Retirer des favoris »), dans les 3 langues.
    private static let removeLabels: [String] = ["Retirer des favoris", "إزالة من المفضلة", "Remove from favorites"]
    /// Bouton du glissement d'une alerte (« Supprimer l'alerte »), dans les 3 langues.
    private static let deleteLabels: [String] = ["Supprimer l'alerte", "حذف التنبيه", "Delete alert"]

    // MARK: - Appui long

    /// Appui long sur la première ligne de l'onglet Annonces : l'aperçu (la carte) et le menu (favori, Partager, Voir
    /// le vendeur).
    @MainActor
    func test11b01ListingsLongPress() {
        let app = launch(["-WeydaRoute", "tab:listings"], screen: "listings")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "listings.row."))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "aucune ligne de résultat")
        settle()
        if row.exists {
            row.press(forDuration: 1.0)
            settle(1.0)
        }
        pause()
        capture("11b-01-listings-menu-1")
        app.terminate()
    }

    // MARK: - Favoris

    /// « Mes favoris » en grand titre ; un favori retiré (glissement) → bannière « Retiré des favoris » + « Annuler » ;
    /// « Annuler » → la ligne revient à sa place.
    @MainActor
    func test11b02FavoritesTitleAndUndo() {
        let app = launch(["-WeydaRoute", "favorites"] + Self.member, screen: "favorites")
        let row = waitFor("favorite.row.mock-a3", in: app)
        settle()
        pause()
        capture("11b-02-favorites-title-1")

        revealTrailingActions(of: row)
        settle(0.6)
        tapFirstButton(labeled: Self.removeLabels, in: app)
        waitUntilGone(row)
        let notice = app.descendants(matching: .any)["notice"]
        _ = notice.waitForExistence(timeout: 10)
        settle(0.6)
        pause()
        capture("11b-03-favorites-undo-1")

        let undo = app.buttons["notice.action"]
        if undo.waitForExistence(timeout: 3) {
            undo.tap()
            _ = row.waitForExistence(timeout: 10)
            settle(0.8)
            pause()
            capture("11b-03-favorites-undo-2")
        }
        app.terminate()
    }

    // MARK: - Alertes

    /// « Mes alertes » en grand titre ; une alerte supprimée (glissement, plus de boîte de confirmation) → bannière
    /// « Alerte supprimée » + « Annuler » ; « Annuler » → l'alerte revient à sa place.
    @MainActor
    func test11b04AlertsTitleAndUndo() {
        let app = launch(["-WeydaRoute", "savedSearches"] + Self.member, screen: "savedSearches")
        let row = waitFor("alert.row.mock-s2", in: app)
        settle()
        pause()
        capture("11b-04-alerts-title-1")

        revealTrailingActions(of: row)
        settle(0.6)
        tapFirstButton(labeled: Self.deleteLabels, in: app)
        waitUntilGone(row)
        let notice = app.descendants(matching: .any)["notice"]
        _ = notice.waitForExistence(timeout: 10)
        settle(0.6)
        pause()
        capture("11b-05-alerts-undo-1")

        let undo = app.buttons["notice.action"]
        if undo.waitForExistence(timeout: 3) {
            undo.tap()
            _ = row.waitForExistence(timeout: 10)
            settle(0.8)
            pause()
            capture("11b-05-alerts-undo-2")
        }
        app.terminate()
    }

    // MARK: - Filtres

    /// Feuille de filtres (Véhicules › Voitures, Oran) : « Réinitialiser » modifie le brouillon, « Fermer » demande
    /// « Abandonner les modifications ? » (feuille d'actions) ; « Abandonner » referme la feuille sans rien appliquer.
    @MainActor
    func test11b06FiltersDiscard() {
        let app = launch(
            ["-WeydaRoute", "listings:category=vehicules&subcategory=voitures&wilaya=31"],
            screen: "listings"
        )
        let filtersButton = app.buttons["listings.filters"]
        XCTAssertTrue(filtersButton.waitForExistence(timeout: 10), "bouton Filtres introuvable")
        settle(1.0) // résultats, catalogue et facettes arrivés
        filtersButton.tap()
        let sheetShown = waitForScreen("filters", in: app, timeout: 10)
            || app.buttons["filters.apply"].waitForExistence(timeout: 5)
        XCTAssertTrue(sheetShown, "feuille de filtres introuvable")
        settle(0.8)

        let reset = app.buttons["filters.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "« Réinitialiser » introuvable")
        reset.tap()
        settle(0.5)
        let close = app.buttons["filters.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "« Fermer » introuvable")
        close.tap()

        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "feuille d'actions « Abandonner » absente")
        settle(0.8)
        pause()
        capture("11b-06-filters-discard-1")

        // « Abandonner » : le bouton destructif (identifiant, sinon le premier de la feuille d'actions).
        if dialog.exists {
            let discard = dialog.buttons["filters.discard"]
            if discard.exists {
                discard.tap()
            } else if dialog.buttons.count > 0 {
                dialog.buttons.element(boundBy: 0).tap()
            }
            XCTAssertTrue(waitForScreen("listings", in: app, timeout: 10), "screen.listings introuvable après « Abandonner »")
        }
        app.terminate()
    }

    // MARK: - Raccourci de l'icône

    /// `-WeydaShortcut search` (raccourci « Rechercher » de l'icône) : l'onglet Annonces, champ de recherche focalisé
    /// (clavier sorti), la liste par défaut dessous.
    @MainActor
    func test11b07ShortcutSearch() {
        let app = launch(["-WeydaShortcut", "search"], screen: "listings")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "champ de recherche introuvable")
        // Clavier : attendu, pas exigé (un clavier matériel du simulateur le masquerait).
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 8)
        settle()
        pause()
        capture("11b-07-listings-shortcut-1")
        app.terminate()
    }

    // MARK: - Outils

    /// L'app ouverte avec ces arguments (lancement sauté, animations décoratives figées), son écran attendu.
    @MainActor
    private func launch(_ arguments: [String], screen: String) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES"] + arguments)
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
}
