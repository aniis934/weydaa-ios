import XCTest

/// Tour de la boîte de réception (9i) en API simulée (`MockFixtures/routes-inbox.json` + `inbox/`) : conversations
/// (non lue en tête, interlocuteur bloqué masqué), recherche, archives, glisser pour archiver, visiteur ;
/// notifications (non lues, après « tout lu », glisser pour supprimer) ; utilisateurs bloqués (liste, confirmation,
/// déblocage jusqu'à la liste vide) ; ligne « Utilisateurs bloqués » du Profil. Session simulée `-WeydaLoggedIn YES`
/// (utilisateur fictif `mock-me`). Socle commun (lancement, attente, captures) : `TourSupport.swift`.
final class TourInboxTests: TourTestCase {
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]
    /// « Annuler » dans les 3 langues : l'autre bouton de la confirmation est celui qui confirme, quel que soit l'ordre
    /// d'affichage (côte à côte, empilés, de droite à gauche).
    private static let cancelLabels: Set<String> = ["Annuler", "إلغاء", "Cancel"]

    // MARK: - Conversations

    /// Boîte de réception : c1 non lue en tête (pastille, gras), c5 dont l'interlocuteur est bloqué (aperçu masqué).
    /// On n'attend que la PREMIÈRE rangée : en très grand texte, c5 est hors écran et la liste ne crée pas les rangées
    /// invisibles (attendre c5 échouait alors que l'écran était juste).
    @MainActor
    func test9i01Conversations() {
        let app = launch(route: "tab:messages", screen: "conversations")
        waitFor("conversation.row.mock-c1", in: app)
        settle()
        pause()
        capture("9i-01-conversations-1")
        app.terminate()
    }

    /// Recherche locale : « clio » ne garde que la conversation de la Clio.
    @MainActor
    func test9i02Search() {
        let app = launch(route: "tab:messages", screen: "conversations")
        waitFor("conversation.row.mock-c1", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "champ de recherche introuvable")
        field.tap()
        field.typeText("clio")
        settle(0.8)
        pause()
        capture("9i-02-conversations-search-1")
        app.terminate()
    }

    /// Segment « Archives » : la conversation archivée (MacBook vendu).
    @MainActor
    func test9i03Archives() {
        let app = launch(route: "tab:messages", screen: "conversations")
        waitFor("conversation.row.mock-c1", in: app)
        let control = app.segmentedControls.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10), "sélecteur Conversations / Archives introuvable")
        let archived = app.descendants(matching: .any)["conversation.row.mock-c6"]
        control.buttons.element(boundBy: 1).tap()
        if !archived.waitForExistence(timeout: 5) {
            // Ordre des segments inversé (arabe) : l'autre segment.
            control.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(archived.waitForExistence(timeout: 10), "conversation.row.mock-c6 introuvable")
        settle()
        pause()
        capture("9i-03-conversations-archives-1")
        app.terminate()
    }

    /// Glisser une conversation vers le bord de fin : l'action « Archiver » apparaît (sans être déclenchée).
    @MainActor
    func test9i04SwipeToArchive() {
        let app = launch(route: "tab:messages", screen: "conversations")
        let row = waitFor("conversation.row.mock-c2", in: app)
        settle(0.8)
        revealTrailingActions(of: row)
        settle(0.8)
        pause()
        capture("9i-04-conversations-swipe-1")
        app.terminate()
    }

    /// Visiteur : l'invitation à se connecter.
    @MainActor
    func test9i05Guest() {
        captureLaunch(["-WeydaRoute", "tab:messages"], name: "9i-05-conversations-guest", screen: "conversationsGuest")
    }

    // MARK: - Notifications

    /// Notifications : 3 non lues en tête, puis la suite de la liste.
    @MainActor
    func test9i06Notifications() {
        let app = launch(route: "notifications", screen: "notifications")
        waitFor("notification.row.mock-n1", in: app)
        settle()
        pause()
        capture("9i-06-notifications-1")
        app.swipeUp()
        settle(0.8)
        capture("9i-06-notifications-2")
        app.terminate()
    }

    /// « Tout marquer comme lu » : plus de pastille, le bouton disparaît.
    @MainActor
    func test9i07MarkAllRead() {
        let app = launch(route: "notifications", screen: "notifications")
        waitFor("notification.row.mock-n1", in: app)
        let markAll = app.buttons.matching(identifier: "notifications.markAll").firstMatch
        XCTAssertTrue(markAll.waitForExistence(timeout: 10), "notifications.markAll introuvable")
        markAll.tap()
        for _ in 0..<20 where markAll.exists {
            settle(0.25)
        }
        XCTAssertFalse(markAll.exists, "« Tout marquer comme lu » toujours affiché")
        settle(0.8)
        pause()
        capture("9i-07-notifications-allRead-1")
        app.terminate()
    }

    /// Glisser une notification vers le bord de fin : l'action « Supprimer » apparaît (sans être déclenchée).
    @MainActor
    func test9i08SwipeToDelete() {
        let app = launch(route: "notifications", screen: "notifications")
        let row = waitFor("notification.row.mock-n2", in: app)
        settle(0.8)
        revealTrailingActions(of: row)
        settle(0.8)
        pause()
        capture("9i-08-notifications-swipe-1")
        app.terminate()
    }

    // MARK: - Utilisateurs bloqués

    /// Liste : Lyes A. (bloqué le 30 sept.) et un compte supprimé, note de bas de section.
    @MainActor
    func test9i09BlockedUsers() {
        let app = launch(route: "blockedUsers", screen: "blockedUsers")
        waitFor("blocked.unblock.mock-u6", in: app)
        settle()
        pause()
        capture("9i-09-blockedUsers-1")
        app.terminate()
    }

    /// Confirmation « Débloquer cet utilisateur ? ».
    @MainActor
    func test9i10UnblockConfirmation() {
        let app = launch(route: "blockedUsers", screen: "blockedUsers")
        waitFor("blocked.unblock.mock-u6", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "confirmation de déblocage absente")
        settle(0.8)
        pause()
        capture("9i-10-blockedUsers-confirm-1")
        app.terminate()
    }

    /// Déblocage confirmé (ligne retirée, « Utilisateur débloqué »), puis le second : la liste vide explique comment
    /// bloquer quelqu'un.
    @MainActor
    func test9i11UnblockUntilEmpty() {
        let app = launch(route: "blockedUsers", screen: "blockedUsers")
        unblock("mock-u6", in: app)
        let notice = app.descendants(matching: .any)["notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "message après le déblocage absent")
        settle(0.6)
        capture("9i-11-blockedUsers-unblocked-1")
        unblock("mock-u9", in: app)
        let remaining = app.buttons.matching(identifier: "blocked.unblock.mock-u9").firstMatch
        for _ in 0..<20 where remaining.exists {
            settle(0.25)
        }
        XCTAssertFalse(remaining.exists, "la liste des bloqués n'est pas vide")
        settle()
        pause()
        capture("9i-12-blockedUsers-empty-1")
        app.terminate()
    }

    /// Profil d'un membre : la ligne « Utilisateurs bloqués » du menu du compte.
    @MainActor
    func test9i13ProfileBlockedUsersRow() {
        let app = launch(route: "tab:account", screen: "profile")
        let row = app.descendants(matching: .any)["profile.blockedUsers"]
        for _ in 0..<5 {
            if row.exists && isOnScreen(row, in: app) { break }
            app.swipeUp()
            settle(0.8)
        }
        XCTAssertTrue(row.exists, "profile.blockedUsers introuvable")
        settle(0.6)
        pause()
        capture("9i-13-profile-blockedUsers-1")
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

    /// Glissement lent vers le bord de FIN (gauche en français / anglais, droite en arabe), sur un tiers de la
    /// largeur : l'action du bord apparaît et reste ouverte, sans le glissement complet qui la déclencherait.
    @MainActor
    private func revealTrailingActions(of row: XCUIElement) {
        let rtl = environment["WEYDA_LANG"] == "ar"
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.1 : 0.9, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: rtl ? 0.45 : 0.55, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// « Débloquer » sur la ligne, puis le bouton de la confirmation qui n'est pas « Annuler ».
    @MainActor
    private func unblock(_ userId: String, in app: XCUIApplication) {
        let button = app.buttons.matching(identifier: "blocked.unblock.\(userId)").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "blocked.unblock.\(userId) introuvable")
        button.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "confirmation de déblocage absente")
        settle(0.5)
        guard let confirm = alert.buttons.allElementsBoundByIndex.first(where: { !Self.cancelLabels.contains($0.label) }) else {
            XCTFail("bouton de confirmation introuvable")
            return
        }
        confirm.tap()
    }

    /// Sous la barre de navigation, au-dessus de la barre d'onglets. Pas d'`isHittable` : sur un élément hors écran,
    /// il échoue (« Activation point invalid ») au lieu de répondre faux — on compare les cadres.
    @MainActor
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        guard !frame.isEmpty, !window.isEmpty else { return false }
        return frame.minY > window.minY + 120 && frame.maxY < window.maxY - 90
    }
}
