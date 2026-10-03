import XCTest

/// Tour de l'onglet Annonces, en API simulée (MockFixtures/routes-search.json + la liste de référence de l'accueil) :
/// liste par défaut, recherche « clio », catégorie avec puces actives, feuille de filtres (ouverte puis défilée),
/// suggestions pendant la saisie, résultat vide avec « Vouliez-vous dire ». Socle commun : `TourSupport.swift`.
final class TourListingsTests: TourTestCase {
    /// Liste par défaut (les annonces récentes), puis un défilement.
    @MainActor
    func test20Listings() {
        captureRoute("tab:listings", name: "20-listings", scrolls: 1)
    }

    /// Recherche par mot-clé : « clio ».
    @MainActor
    func test21SearchClio() {
        captureRoute("listings:q=clio", name: "21-search-clio", screen: "listings")
    }

    /// Catégorie Véhicules, sous-catégorie Voitures, wilaya d'Oran : puces sélectionnées et filtres actifs.
    @MainActor
    func test22Category() {
        captureRoute("listings:category=vehicules&subcategory=voitures&wilaya=31", name: "22-category", screen: "listings")
    }

    /// Feuille de filtres de la catégorie Véhicules (facettes marque, carburant…), ouverte puis défilée.
    @MainActor
    func test23Filters() {
        continueAfterFailure = true
        let app = makeApp([
            "-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "listings:category=vehicules",
        ])
        app.launch()
        XCTAssertTrue(waitForScreen("listings", in: app), "screen.listings introuvable")
        let filtersButton = app.buttons["listings.filters"]
        XCTAssertTrue(filtersButton.waitForExistence(timeout: 10), "bouton Filtres introuvable")
        settle(1.0) // résultats et facettes arrivés
        filtersButton.tap()
        let sheetShown = waitForScreen("filters", in: app, timeout: 10)
            || app.buttons["filters.apply"].waitForExistence(timeout: 5)
        XCTAssertTrue(sheetShown, "feuille de filtres introuvable")
        settle()
        pause()
        capture("23-filters-1")
        for page in 2...3 {
            app.swipeUp(velocity: .fast)
            settle(0.8)
            capture("23-filters-\(page)")
        }
        app.terminate()
    }

    /// Saisie de « cl » : suggestions du serveur (sous-catégorie, titres d'annonces).
    @MainActor
    func test24Suggestions() {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "tab:listings"])
        app.launch()
        XCTAssertTrue(waitForScreen("listings", in: app), "screen.listings introuvable")
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "champ de recherche introuvable")
        field.tap()
        field.typeText("cl")
        // Un titre d'annonce identique dans les trois langues et absent de la première page de résultats : la liste
        // vient bien du serveur (ni l'historique ni une ligne de résultat derrière le panneau).
        let suggestion = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Climatiseur Condor"))
            .firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "suggestions introuvables")
        settle(0.8)
        pause()
        capture("24-suggestions")
        app.terminate()
    }

    /// Mot-clé sans résultat (« clyo ») : état vide et « Vouliez-vous dire clio ? ».
    @MainActor
    func test25Empty() {
        captureRoute("listings:q=clyo", name: "25-empty", screen: "listings")
    }
}
