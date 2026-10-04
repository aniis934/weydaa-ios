import XCTest

/// Tour « Laisser un avis » (10r) en API simulée (`MockFixtures/routes-reviews.json` + `reviews/`), session simulée
/// `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`) : profil de Karim B. (mock-u1 : droit de noter, pas encore
/// d'avis de moi) avec « Laisser un avis », feuille neuve, feuille remplie (`-WeydaReviewDemo filled` : jamais de
/// saisie au clavier dans le tour), envoi → message ; profil d'Amina K. (mock-u2 : mon avis existe) avec « Modifier mon
/// avis » et la feuille pré-remplie. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourReviewsTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]

    /// Karim B. : « Laisser un avis » sous la note moyenne, au-dessus des avis reçus.
    @MainActor
    func test10r01LeaveButton() {
        let app = launchSeller("mock-u1")
        pause()
        capture("10r-seller-leave-1")
        app.terminate()
    }

    /// « Laisser un avis » touché : feuille neuve (5 étoiles proposées, commentaire vide, compteur).
    @MainActor
    func test10r02EmptySheet() {
        let app = launchSeller("mock-u1")
        tap("seller.review.open", in: app)
        XCTAssertTrue(waitForScreen("review", in: app, timeout: 10), "feuille d'avis absente")
        settle()
        pause()
        capture("10r-review-empty-1")
        app.terminate()
    }

    /// Feuille remplie : 4 étoiles et un commentaire fictif, posés par `-WeydaReviewDemo filled`.
    @MainActor
    func test10r03FilledSheet() {
        let app = launchFilledSheet()
        pause()
        capture("10r-review-filled-1")
        app.terminate()
    }

    /// « Publier » : la feuille se ferme, « Merci, votre avis est publié » sur le profil, bouton « Modifier mon avis ».
    @MainActor
    func test10r04Sent() {
        let app = launchFilledSheet()
        tap("review.submit", in: app)
        let notice = app.descendants(matching: .any).matching(identifier: "notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "message « avis publié » absent")
        settle(0.8)
        pause()
        capture("10r-review-sent-1")
        app.terminate()
    }

    /// Amina K. : mon avis existe → « Modifier mon avis », puis la feuille pré-remplie (4 étoiles + mon commentaire).
    @MainActor
    func test10r05EditExisting() {
        let app = launchSeller("mock-u2")
        pause()
        capture("10r-seller-edit-1")
        tap("seller.review.open", in: app)
        XCTAssertTrue(waitForScreen("review", in: app, timeout: 10), "feuille d'avis absente")
        settle()
        pause()
        capture("10r-review-edit-1")
        app.terminate()
    }

    // MARK: - Outils

    /// Profil d'un vendeur vu par un membre, chargé jusqu'au bouton d'avis (droit de noter lu).
    @MainActor
    private func launchSeller(_ id: String) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "seller:\(id)"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("seller", in: app), "screen.seller introuvable (\(id))")
        let button = app.buttons.matching(identifier: "seller.review.open").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "bouton d'avis absent (\(id))")
        settle()
        return app
    }

    /// Profil de Karim B., feuille d'avis ouverte et remplie dès le chargement (Debug, API simulée).
    @MainActor
    private func launchFilledSheet() -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(
            ["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "seller:mock-u1", "-WeydaReviewDemo", "filled"]
                + Self.member
        )
        app.launch()
        XCTAssertTrue(waitForScreen("review", in: app), "feuille d'avis remplie absente")
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
}
