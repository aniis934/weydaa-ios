import XCTest

/// Tour des actions de « Mes annonces » (8x, après 80-about / 81-comingSoon) en API simulée : boutons sous chaque
/// annonce, confirmations « vendu » et « supprimer », message après la vente, annonce expirée à renouveler puis
/// renouvelée. Session simulée `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`), réponses des actions :
/// `MockFixtures/routes-mylistings.json`. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourMyListingsTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// Annonce en ligne (vendre, supprimer) et annonce expirée à renouveler, dans les données simulées.
    private static let active = "mock-m1"
    private static let expired = "mock-m5"
    /// « Annuler » dans les 3 langues : l'autre bouton de la confirmation est celui qui confirme, quel que soit l'ordre
    /// d'affichage (côte à côte, empilés, de droite à gauche).
    private static let cancelLabels: Set<String> = ["Annuler", "إلغاء", "Cancel"]

    /// Toutes les annonces, avec leurs boutons (modifier, vendu, renouveler, supprimer selon le statut).
    @MainActor
    func test82MyListingsActions() {
        captureLaunch(["-WeydaRoute", "myListings"] + Self.member, name: "82-myListings-actions", scrolls: 1, screen: "myListings")
    }

    /// Confirmation « Marquer comme vendu ? » (onglet « En ligne », première annonce).
    @MainActor
    func test83SoldConfirmation() {
        let app = openActiveListings()
        tapButton("myListing.sold.\(Self.active)", in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "confirmation « vendu » absente")
        settle(0.8)
        pause()
        capture("83-myListings-soldConfirm-1")
        app.terminate()
    }

    /// Confirmation « Supprimer l'annonce ? » (bouton rouge).
    @MainActor
    func test84DeleteConfirmation() {
        let app = openActiveListings()
        tapButton("myListing.delete.\(Self.active)", in: app)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "confirmation « supprimer » absente")
        settle(0.8)
        pause()
        capture("84-myListings-deleteConfirm-1")
        app.terminate()
    }

    /// Vente confirmée : l'annonce passe « Vendue » et le message bref s'affiche (4 s : capture sans attendre).
    @MainActor
    func test85SoldNotice() {
        let app = openActiveListings()
        tapButton("myListing.sold.\(Self.active)", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "confirmation « vendu » absente")
        settle(0.5)
        guard let confirm = confirmButton(in: alert) else {
            XCTFail("bouton de confirmation introuvable")
            app.terminate()
            return
        }
        confirm.tap()
        let notice = app.descendants(matching: .any)["notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "message après la vente absent")
        settle(0.6)
        capture("85-myListings-soldDone-1")
        pause()
        app.terminate()
    }

    /// Annonce expirée (en bas de la liste) : « Renouveler 60 j (2) », puis le message après le renouvellement.
    @MainActor
    func test86RenewExpired() {
        let app = launchMyListings()
        let renew = reveal("myListing.renew.\(Self.expired)", in: app)
        settle()
        pause()
        capture("86-myListings-renew-1")
        guard renew.exists else {
            XCTFail("myListing.renew.\(Self.expired) introuvable")
            app.terminate()
            return
        }
        renew.tap()
        let notice = app.descendants(matching: .any)["notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "message après le renouvellement absent")
        settle(0.6)
        capture("87-myListings-renewed-1")
        pause()
        app.terminate()
    }

    // MARK: - Outils

    /// « Mes annonces » d'un membre, tous statuts.
    @MainActor
    private func launchMyListings() -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "myListings"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("myListings", in: app), "screen.myListings introuvable")
        return app
    }

    /// Onglet « En ligne » (2e puce, toujours à l'écran) : l'annonce active est en tête, ses boutons visibles.
    @MainActor
    private func openActiveListings() -> XCUIApplication {
        let app = launchMyListings()
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
    private func tapButton(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(identifier) introuvable")
        button.tap()
    }

    /// Fait défiler la liste jusqu'à ce que le bouton soit bien à l'écran. Pas d'`isHittable` : sur un élément hors
    /// écran, il échoue (« Activation point invalid ») au lieu de répondre faux — on compare les cadres.
    @MainActor
    private func reveal(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        for _ in 0..<5 {
            if button.exists && isOnScreen(button, in: app) {
                return button
            }
            app.swipeUp()
            settle(0.8)
        }
        return button
    }

    /// Sous la barre de navigation et les puces, au-dessus de la barre d'onglets.
    @MainActor
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        guard !frame.isEmpty, !window.isEmpty else { return false }
        return frame.minY > window.minY + 150 && frame.maxY < window.maxY - 90
    }

    /// Le bouton de la confirmation qui n'est pas « Annuler ».
    @MainActor
    private func confirmButton(in alert: XCUIElement) -> XCUIElement? {
        alert.buttons.allElementsBoundByIndex.first { !Self.cancelLabels.contains($0.label) }
    }
}
