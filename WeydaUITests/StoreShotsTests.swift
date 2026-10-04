import XCTest

/// Captures de la fiche App Store (phase 7) : les 8 écrans de `docs/store/screenshots.md`, dans l'ordre, en mode vitrine
/// (`-WeydaStoreCaption <n>` : légende de marque au-dessus de l'app réduite, `StoreFrame`, Debug + API simulée).
/// Chaque capture s'ouvre DIRECTEMENT sur l'état voulu (route, session simulée, brouillon) : aucun appui à travers le
/// cadre réduit, dont les coordonnées ne sont pas celles de l'écran. Écrans 1 à 7 au passage clair, écran 8 au passage
/// sombre : l'apparence vient de `scripts/ci/screens.sh` (`TEST_RUNNER_WEYDA_APPEARANCE` → `WEYDA_APPEARANCE`).
/// iPhone 17 Pro Max = 1320 × 2868 (6,9 pouces) :
///   gh workflow run ios-screens.yml --ref <branche> -f tests="StoreShotsTests" -f devices="iPhone 17 Pro Max"
///     -f appearances="light dark"
/// Cadrages relus (phase 6) : aucune autre plateforme mobile à l'écran (règle 2.3.10). Socle commun : `TourSupport.swift`.
final class StoreShotsTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié (utilisateur fictif `mock-me`).
    private static let member = ["-WeydaLoggedIn", "YES"]

    /// 1. Accueil d'un visiteur : recherche, catégories, « À la une » (Clio, F3), début des Tendances.
    @MainActor
    func test01Home() throws {
        try requireAppearance("light")
        shoot(1, name: "store-01-accueil", ["-WeydaRoute", "tab:home"], screen: "home", ready: "home.category.vehicules")
    }

    /// 2. Annonces filtrées : Véhicules › Voitures (puces actives, « Filtres », 6 voitures). Avec la wilaya en plus, l'API
    /// simulée n'en a que 2 (écran à moitié vide) ; le prix n'est pas porté par `-WeydaRoute`.
    @MainActor
    func test02Listings() throws {
        try requireAppearance("light")
        shoot(
            2,
            name: "store-02-annonces",
            ["-WeydaRoute", "listings:category=vehicules&subcategory=voitures"],
            screen: "listings",
            ready: "listings.row.mock-a2"
        )
    }

    /// 3. Fiche de la Clio « à la une » : galerie (1 / 8), prix, titre, caractéristiques, barre d'actions d'un visiteur.
    @MainActor
    func test03Detail() throws {
        try requireAppearance("light")
        shoot(3, name: "store-03-fiche", ["-WeydaRoute", "detail:mock-a2"], screen: "detail", ready: "detail.gallery")
    }

    /// 4. Fil de la Clio : mon offre « Lu », la contre-offre d'Amina (Accepter / Contrer / Refuser).
    @MainActor
    func test04Chat() throws {
        try requireAppearance("light")
        shoot(
            4,
            name: "store-04-messagerie",
            ["-WeydaRoute", "chat:mock-c1"] + Self.member,
            screen: "chat",
            ready: "chat.offer.counter"
        )
    }

    /// 5. Dépôt, étape « Caractéristiques » de la Clio (marque, modèle, année, kilométrage, carburant…).
    @MainActor
    func test05Post() throws {
        try requireAppearance("light")
        shoot(
            5,
            name: "store-05-depot",
            ["-WeydaRoute", "tab:post", "-WeydaPostDraft", "step-attributes"] + Self.member,
            screen: "post",
            ready: "post.next",
            waitEnabled: true
        )
    }

    /// 6. Profil de Karim B. vu par un visiteur : note 4,8, badges, avis reçus.
    @MainActor
    func test06Seller() throws {
        try requireAppearance("light")
        shoot(6, name: "store-06-vendeur", ["-WeydaRoute", "seller:mock-u1"], screen: "seller", ready: "seller.header")
    }

    /// 7. Mes favoris : cinq annonces (appartement, Clio, MacBook, Golf, Accent), cœurs pleins.
    @MainActor
    func test07Favorites() throws {
        try requireAppearance("light")
        shoot(
            7,
            name: "store-07-favoris",
            ["-WeydaRoute", "favorites"] + Self.member,
            screen: "favorites",
            ready: "favorite.row.mock-a3"
        )
    }

    /// 8. L'accueil de la capture 1, en sombre (passage `dark` seulement).
    @MainActor
    func test08HomeDark() throws {
        try requireAppearance("dark")
        shoot(8, name: "store-08-sombre", ["-WeydaRoute", "tab:home"], screen: "home", ready: "home.category.vehicules")
    }

    // MARK: - Outils

    /// Apparence du passage (`light` / `dark`), posée par `screens.sh` ; absente (lancement à la main) = clair.
    private var appearance: String {
        let value = environment["WEYDA_APPEARANCE"] ?? ""
        return value.isEmpty ? "light" : value
    }

    /// Chaque écran n'est pris qu'à un passage : les 7 premiers en clair, le 8e en sombre.
    private func requireAppearance(_ expected: String) throws {
        if appearance != expected {
            throw XCTSkip("capture du passage \(expected) (passage en cours : \(appearance))")
        }
    }

    /// L'app en vitrine (légende `caption`), ouverte sur son état, attendue jusqu'à son contenu (`ready`) puis
    /// ses photos simulées ; une capture `name`, sans aucun appui.
    @MainActor
    private func shoot(
        _ caption: Int,
        name: String,
        _ arguments: [String],
        screen: String,
        ready: String,
        waitEnabled: Bool = false
    ) {
        continueAfterFailure = true
        let launch = ["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaStoreCaption", String(caption)]
        let app = makeApp(launch + arguments)
        app.launch()
        XCTAssertTrue(waitForScreen(screen, in: app), "screen.\(screen) introuvable (\(name))")
        let legend = app.descendants(matching: .any).matching(identifier: "store.caption").firstMatch
        XCTAssertTrue(legend.waitForExistence(timeout: 10), "légende de la vitrine absente (\(name))")
        let content = app.descendants(matching: .any).matching(identifier: ready).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 15), "\(ready) introuvable (\(name))")
        if waitEnabled {
            waitUntilEnabled(content)
        }
        settle(2.5)
        pause()
        capture(name)
        app.terminate()
    }

    /// « Suivant » du dépôt reste inactif tant que catégories et caractéristiques se chargent.
    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && !element.isEnabled && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
    }
}
