import XCTest

/// Tour du fil de discussion (9c) en API simulée (`MockFixtures/routes-chat.json` + `chat/`), session simulée
/// `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`) : offre ouverte à laquelle répondre, feuille de contre-offre,
/// offre acceptée, annonce gratuite, interlocuteur bloqué, fil archivé (annonce vendue), menu, confirmation de blocage
/// (feuille d'actions depuis la phase 8), signalement, « écrit… », e-mail à vérifier, contact et offre depuis la fiche,
/// visiteur. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourChatTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// Libellés des entrées du menu dans les 3 langues (si l'identifiant d'une entrée de menu n'est pas exposé).
    private static let blockLabels: Set<String> = ["Bloquer cet utilisateur", "حظر هذا المستخدم", "Block this user"]
    private static let reportLabels: Set<String> = ["Signaler cet utilisateur", "الإبلاغ عن هذا المستخدم", "Report this user"]

    private static func chat(_ id: String) -> [String] {
        ["-WeydaRoute", "chat:\(id)"]
    }

    /// Clio : contre-offre OUVERTE d'Amina (Accepter / Contrer / Refuser), un de mes messages supprimé, « Lu ».
    @MainActor
    func test9c01OpenOffer() {
        captureLaunch(Self.chat("mock-c1") + Self.member, name: "9c-chat-openOffer", screen: "chat")
    }

    /// Même fil, « Contrer » : feuille du montant (prix demandé et offre actuelle rappelés).
    @MainActor
    func test9c02CounterSheet() {
        let app = launchChat("mock-c1")
        // Le fil descend tout seul en bas à l'ouverture : un appui pendant ce défilement tombe à côté (17e, constaté
        // deux fois). On attend qu'il soit posé, puis un second appui si la feuille n'est pas venue.
        settle()
        tap("chat.offer.counter", in: app)
        if !waitForSheet(["chat.offer.sheet", "offer.amount"], in: app, timeout: 4) {
            settle(0.8)
            tap("chat.offer.counter", in: app)
        }
        XCTAssertTrue(waitForSheet(["chat.offer.sheet", "offer.amount"], in: app), "feuille de contre-offre absente")
        settle()
        pause()
        capture("9c-chat-counterSheet-1")
        app.terminate()
    }

    /// iPhone : négociation close (offre acceptée), « Faire une offre » de nouveau proposé ; puis le début de la
    /// négociation (le fil s'ouvre en bas : on remonte).
    @MainActor
    func test9c03Accepted() {
        let app = launchChat("mock-c3")
        settle()
        pause()
        capture("9c-chat-accepted-1")
        app.swipeDown()
        settle(0.8)
        capture("9c-chat-accepted-2")
        app.terminate()
    }

    /// Canapé à donner : pas d'offre possible, mon dernier message « Lu ».
    @MainActor
    func test9c04Free() {
        captureLaunch(Self.chat("mock-c4") + Self.member, name: "9c-chat-free", screen: "chat")
    }

    /// Lyes bloqué : le composeur laisse place à l'encart « Débloquer ».
    @MainActor
    func test9c05Blocked() {
        captureLaunch(Self.chat("mock-c5") + Self.member, name: "9c-chat-blocked", screen: "chat")
    }

    /// Fil archivé (annonce vendue) puis son menu : « Désarchiver ».
    @MainActor
    func test9c06Archived() {
        let app = launchChat("mock-c6", extra: ["-WeydaChatDemo", "archived"])
        settle()
        pause()
        capture("9c-chat-archived-1")
        tap("chat.menu", in: app)
        settle(0.8)
        capture("9c-chat-archived-2")
        app.terminate()
    }

    /// Menu du fil : voir l'annonce, voir le profil, archiver, bloquer, signaler.
    @MainActor
    func test9c07Menu() {
        let app = launchChat("mock-c2")
        tap("chat.menu", in: app)
        settle(0.8)
        pause()
        capture("9c-chat-menu-1")
        app.terminate()
    }

    /// « Bloquer cet utilisateur » : confirmation (feuille d'actions depuis la phase 8 : `app.sheets`).
    @MainActor
    func test9c08BlockConfirmation() {
        let app = launchChat("mock-c2")
        tap("chat.menu", in: app)
        settle(0.8)
        tapMenuItem("chat.menu.block", labels: Self.blockLabels, in: app)
        XCTAssertNotNil(actionSheet(in: app), "confirmation de blocage absente")
        settle(0.8)
        pause()
        capture("9c-chat-blockConfirm-1")
        app.terminate()
    }

    /// « Signaler cet utilisateur » : feuille de signalement (motifs sans « annonce en double »).
    @MainActor
    func test9c09Report() {
        let app = launchChat("mock-c5")
        tap("chat.menu", in: app)
        settle(0.8)
        tapMenuItem("chat.menu.report", labels: Self.reportLabels, in: app)
        XCTAssertTrue(waitForScreen("report", in: app, timeout: 10), "screen.report introuvable")
        settle()
        pause()
        capture("9c-chat-report-1")
        app.terminate()
    }

    /// Interlocuteur « en ligne » qui écrit (démonstration sans temps réel : `-WeydaChatDemo typing`).
    @MainActor
    func test9c10Typing() {
        captureLaunch(
            Self.chat("mock-c2") + Self.member + ["-WeydaChatDemo", "typing"],
            name: "9c-chat-typing",
            screen: "chat"
        )
    }

    /// E-mail non vérifié : bandeau « Vérifier » au-dessus du composeur.
    @MainActor
    func test9c11Unverified() {
        captureLaunch(Self.chat("mock-c2") + ["-WeydaLoggedIn", "unverified"], name: "9c-chat-unverified", screen: "chat")
    }

    /// Fiche de la Clio → « Contacter » : feuille du premier message ; un modèle de message, « Envoyer », puis le fil.
    @MainActor
    func test9c12ContactFromListing() {
        let app = launchDetail("mock-a2")
        tap("detail.contact", in: app)
        XCTAssertTrue(waitForSheet(["detail.contact.sheet", "contact.message"], in: app), "feuille « Contacter » absente")
        settle()
        tap("contact.template.1", in: app)
        settle(0.8)
        pause()
        capture("9c-detail-contactSheet-1")
        tap("contact.send", in: app)
        XCTAssertTrue(waitForScreen("chat", in: app, timeout: 15), "le fil ne s'est pas ouvert après l'envoi")
        settle()
        pause()
        capture("9c-detail-contactThread-1")
        app.terminate()
    }

    /// Fiche de la Clio → « Faire une offre » : feuille du montant (prix demandé rappelé).
    @MainActor
    func test9c13OfferFromListing() {
        let app = launchDetail("mock-a2")
        tap("detail.offer", in: app)
        XCTAssertTrue(waitForSheet(["detail.offer.sheet", "offer.amount"], in: app), "feuille d'offre absente")
        settle()
        pause()
        capture("9c-detail-offerSheet-1")
        app.terminate()
    }

    /// Visiteur sur un lien vers un fil : invitation à se connecter.
    @MainActor
    func test9c14Visitor() {
        captureLaunch(Self.chat("mock-c1"), name: "9c-chat-visitor", screen: "loginRequired")
    }

    // MARK: - Outils

    /// Fil d'un membre, chargé (en-tête et messages à l'écran).
    @MainActor
    private func launchChat(_ id: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES"] + Self.chat(id) + Self.member + extra)
        app.launch()
        XCTAssertTrue(waitForScreen("chat", in: app), "screen.chat introuvable (\(id))")
        let menu = app.descendants(matching: .any).matching(identifier: "chat.menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "fil \(id) non chargé")
        settle(0.8)
        return app
    }

    /// Fiche d'un membre, chargée (barre d'actions à l'écran).
    @MainActor
    private func launchDetail(_ id: String) -> XCUIApplication {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES", "-WeydaRoute", "detail:\(id)"] + Self.member)
        app.launch()
        XCTAssertTrue(waitForScreen("detail", in: app), "screen.detail introuvable (\(id))")
        let contact = app.buttons.matching(identifier: "detail.contact").firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 15), "barre d'actions de la fiche absente")
        settle(0.8)
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

    /// Une feuille ouverte : son identifiant posé par l'écran, ou à défaut celui de son champ.
    @MainActor
    private func waitForSheet(_ identifiers: [String], in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers where app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
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

    /// La feuille d'actions (`confirmationDialog`) : `app.sheets` sur iPhone ; repli sur un popover (iOS 26 peut ancrer
    /// la feuille) puis sur une alerte. Nil au bout du délai.
    @MainActor
    private func actionSheet(in app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement? {
        // Aide commune (TourSupport) : repli iOS 16, où XCUITest ne range pas la feuille dans `sheets`.
        confirmationDialog(in: app, timeout: timeout)
    }
}
