import XCTest
@testable import Weyda

/// Parité des chaînes : chaque clé existe et est traduite en fr, ar et en dans l'app COMPILÉE
/// (le catalogue .xcstrings est transformé par Xcode : on vérifie le résultat, pas la source).
final class LocalizationTests: XCTestCase {
    private let missing = "\u{27C2}__absent__"

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "\(language).lproj absent de l'app"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    func testEveryKeyIsTranslatedInEveryLanguage() throws {
        XCTAssertGreaterThan(L10n.allKeys.count, 500)
        for language in WeydaLocale.supported {
            let localized = try bundle(language)
            var absent: [String] = []
            for key in L10n.allKeys {
                let value = localized.localizedString(forKey: key, value: missing, table: "Localizable")
                if value == missing || value.isEmpty { absent.append(key) }
            }
            XCTAssertEqual(absent, [], "Clés absentes en \(language)")
        }
    }

    func testArabicPluralsCoverTheSixForms() throws {
        let format = try bundle("ar").localizedString(forKey: "results_count", value: nil, table: "Localizable")
        let arabic = WeydaLocale.latinDigits(language: "ar", region: "DZ")
        XCTAssertEqual(String(format: format, locale: arabic, 0), "لا توجد إعلانات")
        XCTAssertEqual(String(format: format, locale: arabic, 1), "إعلان واحد")
        XCTAssertEqual(String(format: format, locale: arabic, 2), "إعلانان")
        XCTAssertEqual(String(format: format, locale: arabic, 5), "5 إعلانات")
        XCTAssertEqual(String(format: format, locale: arabic, 11), "11 إعلانًا")
        XCTAssertEqual(String(format: format, locale: arabic, 100), "100 إعلان")
    }

    func testFrenchAndEnglishPlurals() throws {
        let french = try bundle("fr").localizedString(forKey: "results_count", value: nil, table: "Localizable")
        let fr = WeydaLocale.latinDigits(language: "fr", region: "DZ")
        XCTAssertEqual(String(format: french, locale: fr, 1), "1 annonce")
        XCTAssertEqual(String(format: french, locale: fr, 3), "3 annonces")

        let english = try bundle("en").localizedString(forKey: "results_count", value: nil, table: "Localizable")
        let en = WeydaLocale.latinDigits(language: "en", region: "DZ")
        XCTAssertEqual(String(format: english, locale: en, 1), "1 listing")
        XCTAssertEqual(String(format: english, locale: en, 4), "4 listings")
    }

    func testArgumentsAreSubstituted() throws {
        let format = try bundle("fr").localizedString(forKey: "price_dzd", value: nil, table: "Localizable")
        XCTAssertEqual(String(format: format, locale: WeydaLocale.latinDigits(language: "fr", region: "DZ"), "12 500"), "12 500 DA")
    }

    /// iOS groupe les milliers selon la locale, y compris dans `String(format:)` (« 1.234 » en ar_DZ,
    /// constaté sur iOS 26) : on vérifie les CHIFFRES (latins), pas le séparateur.
    func testArabicUsesLatinDigits() {
        let arabic = WeydaLocale.latinDigits(language: "ar", region: "DZ")
        assertLatinDigits(String(format: "%lld", locale: arabic, 1234), "1234")
        assertLatinDigits(1_234_567.formatted(.number.locale(arabic)), "1234567")
        assertLatinDigits(L10n.resultsCount(25), "25")
    }

    private func assertLatinDigits(_ text: String, _ digits: String, file: StaticString = #filePath, line: UInt = #line) {
        let arabicIndic = text.unicodeScalars.filter { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) }
        XCTAssertTrue(arabicIndic.isEmpty, "chiffres arabes-indiens dans « \(text) »", file: file, line: line)
        XCTAssertEqual(String(text.filter { $0.isASCII && $0.isNumber }), digits, file: file, line: line)
    }

    func testGeneratedAccessorsResolve() {
        XCTAssertNotEqual(L10n.navHome, "nav_home")
        XCTAssertFalse(L10n.navHome.isEmpty)
        XCTAssertTrue(L10n.priceDzd("900").contains("900"))
    }
}
