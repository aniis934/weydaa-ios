import XCTest

/// Tour de finition (10p) en API simulée. Bandeau « hors ligne » : `-WeydaForceOffline YES` (Debug, API simulée) fait
/// annoncer « hors ligne » au moniteur de connexion, l'API simulée répond quand même — accueil, onglet Annonces, fiche
/// et fil de discussion, le bandeau devant rester visible SOUS la barre de navigation (sur iOS 26, l'ancien encart du
/// haut passait sous son effet de bord). Puis le composeur du fil en ligne (capsule de verre sur iOS 26). Socle commun
/// (lancement, attente, captures) : `TourSupport.swift`.
final class TourPolishTests: TourTestCase {
    private static let offline = ["-WeydaForceOffline", "YES"]
    /// Session simulée ouverte, e-mail vérifié.
    private static let member = ["-WeydaLoggedIn", "YES"]

    /// Accueil hors ligne : bandeau sous la marque, sections chargées dessous.
    @MainActor
    func test10p01HomeOffline() {
        captureOffline(["-WeydaRoute", "tab:home"], name: "10p-01-home-offline", screen: "home")
    }

    /// Onglet Annonces hors ligne (barre de navigation masquée : bandeau sous la barre d'état, au-dessus de la recherche).
    @MainActor
    func test10p02ListingsOffline() {
        captureOffline(["-WeydaRoute", "tab:listings"], name: "10p-02-listings-offline", screen: "listings")
    }

    /// Fiche hors ligne.
    @MainActor
    func test10p03DetailOffline() {
        captureOffline(["-WeydaRoute", "detail:mock-a2"], name: "10p-03-detail-offline", screen: "detail")
    }

    /// Fil hors ligne : bandeau sous l'en-tête opaque, au-dessus de l'annonce du fil.
    @MainActor
    func test10p04ChatOffline() {
        captureOffline(["-WeydaRoute", "chat:mock-c1"] + Self.member, name: "10p-04-chat-offline", screen: "chat")
    }

    /// Composeur du fil en ligne : capsule de verre (champ + bouton d'envoi) sur iOS 26, champ cerné avant.
    @MainActor
    func test10p05ChatComposer() {
        captureLaunch(["-WeydaRoute", "chat:mock-c1"] + Self.member, name: "10p-05-chat-composer", screen: "chat")
    }

    /// Lance l'app hors ligne sur la route, attend l'écran et le bandeau, capture `<name>-1`.
    @MainActor
    private func captureOffline(_ arguments: [String], name: String, screen: String) {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES"] + Self.offline + arguments)
        app.launch()
        let found = waitForScreen(screen, in: app)
        XCTAssertTrue(found, "screen.\(screen) introuvable (\(arguments.joined(separator: " ")))")
        let banner = app.descendants(matching: .any)["offline.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "bandeau hors ligne absent (\(screen))")
        settle()
        pause()
        capture("\(name)-1")
        app.terminate()
    }
}
