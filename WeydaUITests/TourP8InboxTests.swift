import XCTest

/// Tour de la phase 8, lot INBOX (11i), en API simulée (`MockFixtures/routes-inbox.json`, `routes-chat.json`) : onglet
/// Messages en grand titre, appui long sur une conversation (aperçu + menu : voir l'annonce, archiver), conversation
/// archivée depuis ce menu puis « Annuler » (bannière), notification supprimée (glissement) puis « Annuler », feuille
/// d'actions « Bloquer » du fil. Membre simulé `-WeydaLoggedIn YES` (utilisateur fictif `mock-me`). Bannières
/// éphémères : attendues, jamais exigées. Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourP8InboxTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// Conversation lue de la boîte de réception (Sofiane T.), visible en tête à toutes les tailles de texte.
    private static let conversation = "mock-c2"
    /// Entrée « Archiver » du menu d'appui long, dans les 3 langues (si l'identifiant n'est pas exposé).
    private static let archiveLabels: [String] = ["Archiver", "أرشفة", "Archive"]
    /// Bouton du glissement d'une notification (« Supprimer la notification », sinon « Supprimer »), dans les 3 langues.
    private static let deleteLabels: [String] = [
        "Supprimer la notification", "حذف الإشعار", "Delete notification", "Supprimer", "حذف", "Delete",
    ]
    /// Entrée « Bloquer cet utilisateur » du menu du fil, dans les 3 langues.
    private static let blockLabels: [String] = ["Bloquer cet utilisateur", "حظر هذا المستخدم", "Block this user"]

    // MARK: - Messages

    /// Onglet Messages d'un membre : grand titre au-dessus de la recherche et du sélecteur Conversations / Archives.
    @MainActor
    func test11i01MessagesLargeTitle() {
        let app = launch(["-WeydaRoute", "tab:messages"] + Self.member, screen: "conversations")
        waitFor("conversation.row.mock-c1", in: app)
        settle()
        pause()
        capture("11i-01-conversations-largeTitle-1")
        app.terminate()
    }

    /// Appui long sur une conversation : l'aperçu (la rangée) et le menu (Voir l'annonce, Archiver).
    @MainActor
    func test11i02ConversationLongPress() {
        let app = launch(["-WeydaRoute", "tab:messages"] + Self.member, screen: "conversations")
        let row = waitFor("conversation.row.\(Self.conversation)", in: app)
        settle()
        if row.exists {
            row.press(forDuration: 1.0)
            settle(1.0)
        }
        pause()
        capture("11i-02-conversations-menu-1")
        app.terminate()
    }

    /// Conversation archivée depuis le menu d'appui long : la rangée part, bannière « Conversation archivée » +
    /// « Annuler » ; « Annuler » → la rangée revient à sa place.
    @MainActor
    func test11i03ArchiveAndUndo() {
        let app = launch(["-WeydaRoute", "tab:messages"] + Self.member, screen: "conversations")
        let row = waitFor("conversation.row.\(Self.conversation)", in: app)
        settle()
        guard row.exists else {
            app.terminate()
            return
        }
        row.press(forDuration: 1.0)
        settle(1.0)
        tapMenuItem("conversation.menu.archive.\(Self.conversation)", labels: Self.archiveLabels, in: app)
        waitUntilGone(row)
        let notice = app.descendants(matching: .any)["notice"]
        _ = notice.waitForExistence(timeout: 10)
        settle(0.6)
        pause()
        capture("11i-03-conversations-archived-1")

        // La bannière à « Annuler » vit ~7 s : l'appui n'est tenté que si elle est encore là (jamais une assertion).
        let undo = app.buttons.matching(identifier: "notice.action").firstMatch
        if undo.exists {
            // Course possible avec la fermeture automatique : un appui manqué n'est pas un échec du tour.
            XCTExpectFailure("bannière fermée juste avant l'appui", strict: false) {
                undo.tap()
            }
            _ = row.waitForExistence(timeout: 10)
            settle(0.8)
            pause()
            capture("11i-03-conversations-archived-2")
        }
        app.terminate()
    }

    // MARK: - Notifications

    /// Notification supprimée (glissement vers le bord de fin, « Supprimer ») : la rangée part, bannière « Notification
    /// supprimée » + « Annuler » ; « Annuler » → la rangée revient à sa place, sans appel au serveur.
    @MainActor
    func test11i04NotificationDeleteAndUndo() {
        let app = launch(["-WeydaRoute", "notifications"] + Self.member, screen: "notifications")
        let row = waitFor("notification.row.mock-n2", in: app)
        settle(0.8)
        revealTrailingActions(of: row)
        settle(0.6)
        tapFirstButton(labeled: Self.deleteLabels, in: app)
        waitUntilGone(row)
        let notice = app.descendants(matching: .any)["notice"]
        _ = notice.waitForExistence(timeout: 10)
        settle(0.6)
        pause()
        capture("11i-04-notifications-deleted-1")

        // La bannière à « Annuler » vit ~7 s : l'appui n'est tenté que si elle est encore là (jamais une assertion).
        let undo = app.buttons.matching(identifier: "notice.action").firstMatch
        if undo.exists {
            // Course possible avec la fermeture automatique : un appui manqué n'est pas un échec du tour.
            XCTExpectFailure("bannière fermée juste avant l'appui", strict: false) {
                undo.tap()
            }
            _ = row.waitForExistence(timeout: 10)
            settle(0.8)
            pause()
            capture("11i-04-notifications-deleted-2")
        }
        app.terminate()
    }

    // MARK: - Fil

    /// Menu du fil → « Bloquer cet utilisateur » : feuille d'actions iOS (bouton rouge, « Annuler » à part).
    @MainActor
    func test11i05ChatBlockSheet() {
        let app = launch(["-WeydaRoute", "chat:\(Self.conversation)"] + Self.member, screen: "chat")
        let menu = app.descendants(matching: .any).matching(identifier: "chat.menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "fil \(Self.conversation) non chargé")
        settle()
        guard menu.exists else {
            app.terminate()
            return
        }
        menu.tap()
        settle(0.8)
        tapMenuItem("chat.menu.block", labels: Self.blockLabels, in: app)
        XCTAssertNotNil(actionSheet(in: app), "feuille d'actions « Bloquer » absente")
        settle(0.8)
        pause()
        capture("11i-05-chat-blockSheet-1")
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

    /// Entrée d'un menu : par son identifiant, sinon par son libellé (fr / ar / en).
    @MainActor
    private func tapMenuItem(_ identifier: String, labels: [String], in app: XCUIApplication) {
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

    /// La feuille d'actions (`confirmationDialog`) : `app.sheets` sur iPhone ; repli sur un popover (iOS 26 peut ancrer
    /// la feuille) puis sur une alerte. Nil au bout du délai.
    @MainActor
    private func actionSheet(in app: XCUIApplication, timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let candidates: [XCUIElement] = [app.sheets.firstMatch, app.popovers.firstMatch, app.alerts.firstMatch]
            if let found = candidates.first(where: { $0.exists }) {
                return found
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return nil
    }
}
