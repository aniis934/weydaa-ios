import SwiftUI
import UIKit
import XCTest
@testable import Weyda

final class BrandTests: XCTestCase {
    func testMarkPathMatchesTheAndroidPath() {
        let commands = WeydaMarkPath.commands
        XCTAssertEqual(commands.count, 7)
        XCTAssertEqual(commands.first, .move(CGPoint(x: 29.51, y: 20.5)))
        XCTAssertEqual(commands.last, .line(CGPoint(x: 86.79, y: 20.5)))
        XCTAssertEqual(
            commands[2],
            .curve(
                control1: CGPoint(x: 7.04, y: 84.75),
                control2: CGPoint(x: 29.95, y: 84.75),
                end: CGPoint(x: 39.11, y: 63.72)
            )
        )
    }

    func testMarkStaysInsideItsViewport() {
        let bounds = WeydaMarkPath.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, 0)
        XCTAssertGreaterThanOrEqual(bounds.minY, 0)
        XCTAssertLessThanOrEqual(bounds.maxX, 100)
        XCTAssertLessThanOrEqual(bounds.maxY, 100)
        // W visuel centré sur (50, 50), à quelques unités près (tracé de 14,4 d'épaisseur en plus).
        XCTAssertEqual(bounds.midX, 50, accuracy: 6)
    }

    func testPathIsCenteredInNonSquareRects() {
        let wide = WeydaMarkPath.path(in: CGRect(x: 0, y: 0, width: 300, height: 100)).boundingRect
        XCTAssertEqual(wide.midX, 150, accuracy: 6)
        XCTAssertLessThanOrEqual(wide.maxY, 100)
    }

    func testCurvesMatchMaterialEndpoints() {
        for curve in [WeydaCurve.emphasized, .emphasizedDecelerate, .emphasizedAccelerate, .standardAccelerate] {
            XCTAssertEqual(curve(0), 0, accuracy: 1e-9)
            XCTAssertEqual(curve(1), 1, accuracy: 1e-9)
        }
        // Courbe décélérée : plus de la moitié du chemin à mi-temps.
        XCTAssertGreaterThan(WeydaCurve.emphasizedDecelerate(0.5), 0.5)
        // Courbe accélérée : moins de la moitié.
        XCTAssertLessThan(WeydaCurve.emphasizedAccelerate(0.5), 0.5)
        // Monotone.
        var previous = 0.0
        for step in 1...20 {
            let value = WeydaCurve.emphasized(Double(step) / 20)
            XCTAssertGreaterThanOrEqual(value, previous - 1e-9)
            previous = value
        }
    }

    func testPhaseIsClamped() {
        XCTAssertEqual(weydaPhase(0.2, from: 0.5, to: 0.75), 0)
        XCTAssertEqual(weydaPhase(0.625, from: 0.5, to: 0.75), 0.5, accuracy: 1e-9)
        XCTAssertEqual(weydaPhase(0.9, from: 0.5, to: 0.75), 1)
    }

    func testEveryCategorySlugHasAnIcon() {
        for slug in CategoryIcon.knownSlugs {
            let name = CategoryIcon.assetName(forSlug: slug)
            XCTAssertNotNil(UIImage(named: name), "icône absente : \(name)")
        }
        XCTAssertEqual(CategoryIcon.assetName(forSlug: "inconnue"), "ic_cat_autres")
        XCTAssertNotNil(UIImage(named: CategoryIcon.all))
        XCTAssertNotNil(UIImage(named: CategoryIcon.place))
    }

    func testEveryCategorySlugHasAnArtwork() {
        let side = WeydaSize.categoryArtwork
        for slug in CategoryIcon.knownSlugs {
            let name = CategoryIcon.artworkName(forSlug: slug)
            let image = UIImage(named: name)
            XCTAssertNotNil(image, "illustration absente : \(name)")
            // Rendus @2x/@3x d'une tuile de 64 pt : la tuile de l'accueil est dessinée pixel pour pixel.
            XCTAssertEqual(image?.size, CGSize(width: side, height: side), name)
        }
        XCTAssertEqual(CategoryIcon.artworkName(forSlug: "materiel-pro"), "art_cat_materiel_pro")
        XCTAssertEqual(CategoryIcon.artworkName(forSlug: "inconnue"), "art_cat_autres")
        XCTAssertEqual(CategoryIcon.artworkName(forSlug: nil), "art_cat_autres")
    }

    func testLaunchAssetsExist() {
        XCTAssertNotNil(UIImage(named: "SplashMark"))
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
        XCTAssertNotNil(UIColor(named: "AccentColor"))
    }

    func testConfigReadsHostsAndTreatsEmptyAsAbsent() {
        let config = AppConfig(info: ["WeydaAPIHost": "weydaa.com", "WeydaSupabaseHost": " ", "WeydaSupabaseAnonKey": ""])
        XCTAssertEqual(config.apiBaseURL.absoluteString, "https://weydaa.com/")
        XCTAssertNil(config.supabaseURL)
        XCTAssertNil(config.supabaseAnonKey)
        XCTAssertEqual(AppConfig(info: [:]).apiBaseURL.absoluteString, "https://weydaa.com/")
    }
}
