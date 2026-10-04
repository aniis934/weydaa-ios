import XCTest

/// Tour de la phase 8, lot DETAIL (11d), en API simulée, membre simulé `-WeydaLoggedIn YES` (utilisateur fictif
/// `mock-me`) : fiche en haut (photo sous la barre transparente, voile, pastilles d'iOS 26) puis défilée (barre visible,
/// titre de l'annonce) ; barre d'actions sur une rangée — acheteur, annonce gratuite, propriétaire, numéro révélé puis
/// son menu ; appui long sur une annonce similaire ; profil vendeur avec « Partager le profil » ; feuille d'actions
/// « Bloquer ». Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourP8DetailTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// « Bloquer cet utilisateur » dans les 3 langues (repli si l'identifiant de l'entrée de menu n'est pas exposé).
    private static let blockLabels: Set<String> = ["Bloquer cet utilisateur", "حظر هذا المستخدم", "Block this user"]

    // MARK: - Barre du haut

    /// Clio (mock-a2) vue par un acheteur, en haut : la photo passe sous la barre d'état et la barre transparente ;
    /// barre d'actions `[numéro] [Faire une offre] [Contacter]`.
    @MainActor
    func test11d01DetailTop() {
        let app = launchDetail("mock-a2", ready: "detail.contact")
        pause()
        capture("11d-01-detail-top-1")
        app.terminate()
    }

    /// Fiche défilée : la photo dépassée, la barre devient visible avec le titre de l'annonce au centre.
    @MainActor
    func test11d02DetailCollapsed() {
        let app = launchDetail("mock-a2", ready: "detail.contact")
        app.swipeUp()
        settle(1.0)
        _ = app.descendants(matching: .any)["detail.barTitle"].waitForExistence(timeout: 5)
        pause()
        capture("11d-02-detail-collapsed-1")
        app.terminate()
    }

    // MARK: - Barre d'actions

    /// Annonce gratuite sans numéro (mock-a24) : « Contacter » seul (pas d'offre sur un don).
    @MainActor
    func test11d03DetailFree() {
        let app = launchDetail("mock-a24", ready: "detail.contact")
        pause()
        capture("11d-03-detail-free-1")
        app.terminate()
    }

    /// Mon annonce (mock-m1) : « Modifier » seul.
    @MainActor
    func test11d04DetailOwner() {
        let app = launchDetail("mock-m1", ready: "detail.edit")
        pause()
        capture("11d-04-detail-owner-1")
        app.terminate()
    }

    /// Numéro : premier appui = révélation (le rond passe à « téléphone plein ») ; second appui = son menu (en-tête =
    /// le numéro, Appeler, Copier le numéro).
    @MainActor
    func test11d05PhoneMenu() {
        let app = launchDetail("mock-a2", ready: "detail.phone")
        tap("detail.phone", in: app)
        settle(1.5)
        pause()
        capture("11d-05-detail-phoneRevealed-1")
        tap("detail.phone", in: app)
        settle(1.0)
        pause()
        capture("11d-05-detail-phoneMenu-2")
        app.terminate()
    }

    // MARK: - Appui long

    /// Appui long sur la première annonce similaire : aperçu de la carte et menu (favori, Partager, Voir le vendeur).
    @MainActor
    func test11d06SimilarLongPress() {
        let app = launchDetail("mock-a2", ready: "detail.contact")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "detail.similar."))
            .firstMatch
        // Les similaires sont en bas de la fiche : on y descend, sans appuyer pendant le défilement.
        var swipes = 0
        while swipes < 8 && !(card.exists && card.isHittable) {
            app.swipeUp()
            settle(0.8)
            swipes += 1
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "aucune annonce similaire")
        if card.exists {
            card.press(forDuration: 1.0)
            settle(1.0)
        }
        pause()
        capture("11d-06-detail-similarMenu-1")
        app.terminate()
    }

    // MARK: - Profil vendeur

    /// Profil de Karim B. (mock-u1) : « Partager le profil » dans la barre, à côté du menu.
    @MainActor
    func test11d07SellerShare() {
        let app = launchSeller("mock-u1")
        _ = app.descendants(matching: .any)["seller.share"].waitForExistence(timeout: 10)
        pause()
        capture("11d-07-seller-share-1")
        app.terminate()
    }

    /// « Bloquer cet utilisateur » : feuille d'actions (plus d'alerte), sur iPhone dans `app.sheets`.
    @MainActor
    func test11d08SellerBlockSheet() {
        let app = launchSeller("mock-u1")
        tap("seller.menu", in: app)
        settle(0.8)
        tapMenuItem("seller.block", labels: Self.blockLabels, in: app)
        XCTAssertNotNil(confirmationDialog(in: app), "feuille d'actions « Bloquer » absente")
        settle(0.8)
        pause()
        capture("11d-08-seller-blockSheet-1")
        app.terminate()
    }

    // MARK: - Outils

    /// Fiche d'un membre, chargée jusqu'à la barre d'actions (`ready` = un de ses boutons).
    @MainActor
    private func launchDetail(_ id: String, ready: String) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "detail:\(id)"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("detail", in: app), "screen.detail introuvable (\(id))")
        let button = app.descendants(matching: .any).matching(identifier: ready).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(ready) absent : barre d'actions de la fiche \(id) non chargée")
        settle()
        return app
    }

    /// Profil d'un vendeur vu par un membre, chargé jusqu'au menu « Signaler / Bloquer ».
    @MainActor
    private func launchSeller(_ id: String) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "seller:\(id)"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("seller", in: app), "screen.seller introuvable (\(id))")
        let menu = app.descendants(matching: .any).matching(identifier: "seller.menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "profil \(id) non chargé")
        settle()
        return app
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(identifier) introuvable")
        if element.exists {
            element.tap()
        }
    }

    /// Entrée d'un menu : par son identifiant, sinon par son libellé (fr / ar / en).
    @MainActor
    private func tapMenuItem(_ identifier: String, labels: Set<String>, in app: XCUIApplication) {
        let byIdentifier = app.buttons.matching(identifier: identifier).firstMatch
        if byIdentifier.waitForExistence(timeout: 3) {
            byIdentifier.tap()
            return
        }
        for label in labels {
            let button = app.buttons[label].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }
        XCTFail("entrée de menu \(identifier) introuvable")
    }
}
