import XCTest

/// Tour automatique de l'app en API simulée : une capture par écran, relue à chaque phase.
/// Lancé par `scripts/ci/screens.sh` pour chaque langue × apparence × appareil.
///   WEYDA_LANG  fr | ar | en   (transmis par xcodebuild via TEST_RUNNER_WEYDA_LANG)
///   WEYDA_SLOW  1 = pauses entre les écrans (la vidéo du parcours reste lisible)
final class TourTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor
    private func makeApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-WeydaMockAPI", "YES"]
        if let language = environment["WEYDA_LANG"], !language.isEmpty {
            arguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_DZ"]
        }
        app.launchArguments = arguments + extra
        return app
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func pause(_ seconds: TimeInterval = 1.2) {
        if environment["WEYDA_SLOW"] == "1" {
            Thread.sleep(forTimeInterval: seconds)
        }
    }

    /// Image figée de l'animation de lancement (le W à moitié écrit, puis le mot posé).
    @MainActor
    func test01LaunchFrames() {
        for (index, frame) in ["0.45", "0.95"].enumerated() {
            let app = makeApp(["-WeydaLaunchFrame", frame])
            app.launch()
            Thread.sleep(forTimeInterval: 1.5)
            capture(String(format: "00-launch-%d", index + 1))
            app.terminate()
        }
    }

    /// L'animation de lancement réelle, jusqu'à la barre d'onglets, puis chaque onglet.
    @MainActor
    func test02Tabs() {
        continueAfterFailure = true
        let app = makeApp()
        app.launch()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "barre d'onglets introuvable")
        pause()
        let buttons = tabBar.buttons
        let count = buttons.count
        XCTAssertEqual(count, 5, "5 onglets attendus")
        for index in 0..<count {
            buttons.element(boundBy: index).tap()
            let screen = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "screen."))
                .firstMatch
            XCTAssertTrue(screen.waitForExistence(timeout: 10), "écran de l'onglet \(index) introuvable")
            let name = screen.identifier.replacingOccurrences(of: "screen.", with: "")
            pause()
            capture(String(format: "%02d-%@", index + 1, name))
        }
    }

    /// Démonstration du système de design (Debug), parcourue de haut en bas.
    @MainActor
    func test03Showcase() {
        let app = makeApp(["-WeydaSkipLaunch", "YES", "-WeydaScreen", "showcase"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["screen.showcase"].waitForExistence(timeout: 20))
        pause()
        capture("90-showcase-1")
        for page in 2...3 {
            app.swipeUp()
            pause(0.8)
            capture("90-showcase-\(page)")
        }
    }
}
