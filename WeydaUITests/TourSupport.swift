import XCTest

/// Socle PARTAGÉ du tour de captures (API simulée). Chaque domaine a son fichier `Tour<Domaine>Tests.swift` dont la
/// classe hérite de celle-ci et n'écrit qu'une ligne par écran :
///
///     final class TourDetailTests: TourTestCase {
///         @MainActor func test30Detail() {
///             captureRoute("detail:mock-a3", name: "30-detail", scrolls: 2)
///         }
///     }
///
/// Lancé par `scripts/ci/screens.sh` pour chaque langue × apparence × appareil :
///   WEYDA_LANG  fr | ar | en   (transmis par xcodebuild via TEST_RUNNER_WEYDA_LANG)
///   WEYDA_SLOW  1 = pauses entre les écrans (la vidéo du parcours reste lisible)
/// Captures « NN-écran[-variante]-<page> ». Numéros : 0x lancement et onglets, 1x accueil, 2x annonces,
/// 3x détail, 4x vendeur, 8x à propos et écrans d'attente, 9x démonstrations (Debug).
/// Aucune méthode `test…` ici : elle serait rejouée par chaque sous-classe.
class TourTestCase: XCTestCase {
    var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// L'app en API simulée, dans la langue du tour, avec ces arguments en plus.
    @MainActor
    func makeApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-WeydaMockAPI", "YES"]
        if let language = environment["WEYDA_LANG"], !language.isEmpty {
            arguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_DZ"]
        }
        app.launchArguments = arguments + extra
        return app
    }

    @MainActor
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Pause visible seulement dans le tour filmé.
    @MainActor
    func pause(_ seconds: TimeInterval = 1.2) {
        if environment["WEYDA_SLOW"] == "1" {
            Thread.sleep(forTimeInterval: seconds)
        }
    }

    /// Laisse arriver les photos de l'API simulée et finir les fondus avant une capture.
    @MainActor
    func settle(_ seconds: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Attend l'écran `screen.<nom>` (identifiant posé à la racine de chaque écran).
    @MainActor
    @discardableResult
    func waitForScreen(_ screen: String, in app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        app.descendants(matching: .any)["screen.\(screen)"].waitForExistence(timeout: timeout)
    }

    /// Ouvre l'app directement sur une route (`-WeydaRoute`, formats de `LaunchRoute` : `detail:<id>`,
    /// `seller:<id>`, `listings:q=…&category=…`, `tab:<onglet>`, `about`…), attend son écran, capture
    /// `<name>-1` puis `<name>-2`, `-3`… après chaque défilement vers le bas.
    /// L'écran attendu est le segment qui suit le numéro (« 30-detail-sold » attend `screen.detail`) ;
    /// `screen:` le remplace quand l'identifiant diffère.
    @MainActor
    func captureRoute(_ route: String, name: String, scrolls: Int = 0, screen: String? = nil) {
        captureLaunch(["-WeydaRoute", route], name: name, scrolls: scrolls, screen: screen ?? Self.screenName(in: name))
    }

    /// Même parcours avec des arguments de lancement libres (`-WeydaScreen components`…). Lancement sauté et
    /// animations décoratives figées (`-WeydaFreezeMotion`) : captures identiques d'un tour à l'autre.
    @MainActor
    func captureLaunch(_ arguments: [String], name: String, scrolls: Int = 0, screen: String) {
        continueAfterFailure = true
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaFreezeMotion", "YES"] + arguments)
        app.launch()
        let found = waitForScreen(screen, in: app)
        XCTAssertTrue(found, "screen.\(screen) introuvable (\(arguments.joined(separator: " ")))")
        settle()
        pause()
        capture("\(name)-1")
        for index in 0..<max(scrolls, 0) {
            app.swipeUp()
            settle(0.8)
            capture("\(name)-\(index + 2)")
        }
        app.terminate()
    }

    /// « 30-detail-sold » → « detail » : le segment qui suit le numéro de la capture.
    static func screenName(in name: String) -> String {
        let parts = name.split(separator: "-").map { String($0) }
        guard let first = parts.first else { return name }
        if parts.count > 1 && first.allSatisfy({ $0.isNumber }) {
            return parts[1]
        }
        return first
    }
}
