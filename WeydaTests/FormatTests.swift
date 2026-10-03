import XCTest
@testable import Weyda

/// Formats (prix, nombres, dates) en fr / ar / en. Les CHIFFRES sont vérifiés (latins partout), jamais le
/// séparateur de milliers : iOS groupe selon la locale (« 12 500 », « 12.500 », « 12,500 »), voulu.
final class FormatTests: XCTestCase {
    private let languages = ["fr", "ar", "en"]
    private let algiers = TimeZone(identifier: "Africa/Algiers")!

    private func locale(_ language: String) -> Locale {
        WeydaLocale.latinDigits(language: language, region: "DZ")
    }

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj absent de l'app")
        return try XCTUnwrap(Bundle(path: path))
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = algiers
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func assertLatinDigits(_ text: String, _ digits: String, _ language: String, file: StaticString = #filePath, line: UInt = #line) {
        assertNoEasternDigits(text, language, file: file, line: line)
        XCTAssertEqual(String(text.filter { $0.isASCII && $0.isNumber }), digits, "en \(language) : « \(text) »", file: file, line: line)
    }

    private func assertNoEasternDigits(_ text: String, _ language: String, file: StaticString = #filePath, line: UInt = #line) {
        let eastern = text.unicodeScalars.filter { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) }
        XCTAssertTrue(eastern.isEmpty, "chiffres arabes-indiens en \(language) : « \(text) »", file: file, line: line)
    }

    // MARK: - Nombres et prix

    func testIntegersAreGroupedWithLatinDigitsInEveryLanguage() {
        for language in languages {
            let integer = Format.integer(1_250_000.9, locale: locale(language))
            assertLatinDigits(integer, "1250000", language)
            XCTAssertGreaterThan(integer.count, 7, "milliers non groupés en \(language) : « \(integer) »")
            assertLatinDigits(Format.count(1_234, locale: locale(language)), "1234", language)
        }
        XCTAssertEqual(Format.integer(.nan), "")
        XCTAssertEqual(Format.integer(.infinity), "")
    }

    func testDecimalsKeepAtMostThreeFractionDigits() {
        for language in languages {
            assertLatinDigits(Format.decimal(12.5, locale: locale(language)), "125", language)
            assertLatinDigits(Format.decimal(3.14159, locale: locale(language)), "3142", language)
            assertLatinDigits(Format.decimal(2_000, locale: locale(language)), "2000", language)
        }
    }

    func testPriceTextsComeFromTheCatalog() {
        let fr = locale("fr")
        XCTAssertEqual(Format.price(nil, type: .free, locale: fr), L10n.priceFree)
        XCTAssertEqual(Format.price(5_000, type: .free, locale: fr), L10n.priceFree)
        XCTAssertEqual(Format.price(nil, type: .fixed, locale: fr), L10n.priceOnRequest)
        XCTAssertEqual(Format.price(nil, type: .negotiable, locale: fr), L10n.priceOnRequest)
        XCTAssertEqual(Format.price(12_500, type: .fixed, locale: fr), L10n.priceDzd(Format.integer(12_500, locale: fr)))
        XCTAssertEqual(Format.amount(1_950_000, locale: fr), L10n.priceDzd(Format.integer(1_950_000, locale: fr)))
        XCTAssertEqual(Format.negotiableLabel(price: 1_000, type: .negotiable), L10n.priceNegotiable)
        XCTAssertNil(Format.negotiableLabel(price: nil, type: .negotiable))
        XCTAssertNil(Format.negotiableLabel(price: 1_000, type: .fixed))
    }

    /// Le prix tel qu'il s'affiche dans chaque langue : gabarit du catalogue + nombre formaté.
    func testPriceReadsInEachLanguageWithLatinDigits() throws {
        let currencies = ["fr": "DA", "ar": "دج", "en": "DZD"]
        for language in languages {
            let template = try bundle(language).localizedString(forKey: "price_dzd", value: nil, table: "Localizable")
            let text = String(format: template, locale: locale(language), Format.integer(12_500, locale: locale(language)))
            XCTAssertTrue(text.contains(currencies[language] ?? "?"), "en \(language) : « \(text) »")
            assertLatinDigits(text, "12500", language)
        }
    }

    func testBadgesAreCapped() {
        XCTAssertEqual(Format.badge(3, cap: 9), "3")
        XCTAssertEqual(Format.badge(12, cap: 9), "9+")
        XCTAssertEqual(Format.badge(99, cap: 99), "99")
        XCTAssertEqual(Format.badge(150, cap: 99), "99+")
        XCTAssertEqual(Format.badge(-2, cap: 9), "0")
    }

    func testEasternDigitsAreBroughtBackToAscii() {
        XCTAssertEqual(Format.latinDigits("١٢٣ ۴۵۶ abc"), "123 456 abc")
        XCTAssertEqual(Format.latinDigits("12 500 DA"), "12 500 DA")
    }

    // MARK: - Dates

    /// Mêmes seuils qu'Android (DateUtils) : minute, heure, jour de calendrier, puis date au-delà d'une semaine.
    /// Comparé au formateur système de référence : le test ne dépend pas des textes exacts d'une version d'iOS.
    func testRelativeTimeFollowsTheAndroidThresholds() throws {
        let now = try makeDate(2026, 9, 15, 12, 0)
        for language in languages {
            let loc = locale(language)
            let reference = RelativeDateTimeFormatter()
            reference.locale = loc
            reference.unitsStyle = .short
            reference.dateTimeStyle = .named
            func relative(_ secondsAgo: TimeInterval) -> String {
                Format.relativeTime(now.addingTimeInterval(-secondsAgo), now: now, locale: loc, timeZone: algiers)
            }

            let justNow = relative(20)
            XCTAssertEqual(justNow, Format.latinDigits(reference.localizedString(fromTimeInterval: 0)))
            XCTAssertFalse(justNow.contains { $0.isNumber }, "en \(language) : « \(justNow) »")
            // Horloge serveur en avance : plafonnée à maintenant, jamais « dans 1 min ».
            XCTAssertEqual(Format.relativeTime(now.addingTimeInterval(45), now: now, locale: loc, timeZone: algiers), justNow)

            XCTAssertEqual(relative(3 * 60 + 20), Format.latinDigits(reference.localizedString(from: DateComponents(minute: -3))))
            assertLatinDigits(relative(3 * 60 + 20), "3", language)
            XCTAssertEqual(relative(5 * 3_600), Format.latinDigits(reference.localizedString(from: DateComponents(hour: -5))))
            assertLatinDigits(relative(5 * 3_600), "5", language)
            // 26 h avant midi : la veille au calendrier.
            XCTAssertEqual(relative(26 * 3_600), Format.latinDigits(reference.localizedString(from: DateComponents(day: -1))))
            XCTAssertEqual(relative(4 * 86_400), Format.latinDigits(reference.localizedString(from: DateComponents(day: -4))))
            assertLatinDigits(relative(4 * 86_400), "4", language)
        }
        XCTAssertEqual(Format.relativeTime(nil), "")
    }

    func testYesterdayIsNamedInEachLanguage() throws {
        let now = try makeDate(2026, 9, 15, 12, 0)
        let yesterday = now.addingTimeInterval(-26 * 3_600)
        XCTAssertEqual(Format.relativeTime(yesterday, now: now, locale: locale("fr"), timeZone: algiers), "hier")
        XCTAssertEqual(Format.relativeTime(yesterday, now: now, locale: locale("en"), timeZone: algiers), "yesterday")
        XCTAssertEqual(Format.relativeTime(yesterday, now: now, locale: locale("ar"), timeZone: algiers), "أمس")
    }

    func testBeyondAWeekTheDateIsShownWithTheYearOnlyIfItDiffers() throws {
        let now = try makeDate(2026, 9, 15, 12, 0)
        let sameYear = try makeDate(2026, 8, 3, 9, 0)
        let lastYear = try makeDate(2025, 8, 3, 9, 0)
        for language in languages {
            assertLatinDigits(Format.relativeTime(sameYear, now: now, locale: locale(language), timeZone: algiers), "3", language)
            assertLatinDigits(Format.relativeTime(lastYear, now: now, locale: locale(language), timeZone: algiers), "32025", language)
        }
    }

    func testAbsoluteDatesUseLatinDigits() throws {
        let moment = try makeDate(2026, 9, 15, 14, 5)
        for language in languages {
            let loc = locale(language)
            let medium = Format.date(moment, locale: loc, timeZone: algiers)
            XCTAssertTrue(medium.contains("2026") && medium.contains("15"), "en \(language) : « \(medium) »")
            assertNoEasternDigits(medium, language)
            assertLatinDigits(Format.monthYear(moment, locale: loc, timeZone: algiers), "2026", language)
            let time = Format.time(moment, locale: loc, timeZone: algiers)
            XCTAssertTrue(time.contains("05"), "en \(language) : « \(time) »")
            assertNoEasternDigits(time, language)
        }
        XCTAssertEqual(Format.date(nil), "")
        XCTAssertEqual(Format.monthYear(nil), "")
        XCTAssertEqual(Format.time(nil), "")
    }

    /// Le groupe des milliers reste VISIBLE en français : espace insécable ordinaire, jamais l'espace fine
    /// (U+202F) que le format système produit et qui disparaît dans le gras serré des prix.
    func testFrenchThousandsUseAVisibleNoBreakSpace() {
        let french = WeydaLocale.latinDigits(language: "fr", region: "DZ")
        let price = Format.price(3_150_000, type: .fixed, locale: french)
        XCTAssertFalse(price.unicodeScalars.contains { $0.value == 0x202F }, price)
        XCTAssertEqual(price.unicodeScalars.filter { $0.value == 0x00A0 }.count >= 2, true, price)
        XCTAssertEqual(String(price.filter { $0.isASCII && $0.isNumber }), "3150000")
        XCTAssertFalse(WeydaLocale.visibleGrouping("1\u{202F}284").unicodeScalars.contains { $0.value == 0x202F })
    }
}
