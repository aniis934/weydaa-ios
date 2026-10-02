import XCTest
@testable import Weyda

/// Portage de `ValidatorsTest.kt` (Android) — miroir des règles Zod (src/lib/validations.ts).
final class ValidatorsTests: XCTestCase {

    func testNameIsTwoToFiftyCharacters() {
        XCTAssertEqual(Validators.name(" A "), .nameMin)
        XCTAssertNil(Validators.name("Al"))
        XCTAssertNil(Validators.name(String(repeating: "A", count: 50)))
        XCTAssertEqual(Validators.name(String(repeating: "A", count: 51)), .nameMax)
    }

    func testListingTitleDescriptionAndPrice() {
        XCTAssertEqual(Validators.title("  Abcd "), .titleMin)
        XCTAssertNil(Validators.title("Abcde"))
        XCTAssertEqual(Validators.title(String(repeating: "A", count: 101)), .titleMax)
        XCTAssertEqual(Validators.description("Trop court."), .descriptionMin)
        XCTAssertNil(Validators.description(String(repeating: "D", count: 20)))
        XCTAssertEqual(Validators.description(String(repeating: "D", count: 5001)), .descriptionMax)

        XCTAssertNil(Validators.price("", type: .fixed))
        XCTAssertNil(Validators.price("n'importe quoi", type: .free))
        XCTAssertNil(Validators.price("1 500", type: .negotiable))
        XCTAssertEqual(Validators.price("abc", type: .fixed), .priceInvalid)
        XCTAssertEqual(Validators.price("-5", type: .fixed), .priceNegative)
    }

    func testAttributesMirrorValidateListingAttributes() {
        let make = AttributeDefinition(
            key: "make", label: "Marque", type: .select, requirement: .required,
            options: [AttributeOption(value: "renault", label: "Renault")]
        )
        let model = AttributeDefinition(key: "model", label: "Modèle", type: .select, requirement: .recommended, dependsOn: "make")
        let year = AttributeDefinition(key: "year", label: "Année", type: .number, requirement: .required, min: 1970, max: 2027)
        let hand = AttributeDefinition(key: "first_hand", label: "Première main", type: .boolean, requirement: .optional)
        let color = AttributeDefinition(key: "color", label: "Couleur", type: .text, requirement: .optional)

        XCTAssertEqual(Validators.attribute(make, value: nil, options: make.options), .attrRequired)
        XCTAssertEqual(Validators.attribute(make, value: "fiat", options: make.options), .attrOption)
        XCTAssertNil(Validators.attribute(make, value: "renault", options: make.options))
        // Select dépendant sans options chargées : la valeur est acceptée (le serveur tranche).
        XCTAssertNil(Validators.attribute(model, value: "clio", options: []))
        XCTAssertNil(Validators.attribute(model, value: "", options: []))
        XCTAssertEqual(Validators.attribute(year, value: "20x8", options: []), .attrNumber)
        XCTAssertEqual(Validators.attribute(year, value: "1969", options: []), .attrMin)
        XCTAssertEqual(Validators.attribute(year, value: "2030", options: []), .attrMax)
        XCTAssertNil(Validators.attribute(year, value: "2018", options: []))
        XCTAssertNil(Validators.attribute(hand, value: "true", options: []))
        XCTAssertEqual(Validators.attribute(hand, value: "oui", options: []), .attrOption)
        XCTAssertEqual(Validators.attribute(color, value: String(repeating: "c", count: 201), options: []), .attrTextMax)

        let errors = Validators.attributes([make, model, year, hand, color], values: ["year": "1950"]) { $0.options }
        XCTAssertEqual(errors, ["make": .attrRequired, "year": .attrMin])
    }

    func testEmail() {
        XCTAssertNil(Validators.email("amina@example.com"))
        XCTAssertNil(Validators.email("  Amina@Example.DZ "))
        XCTAssertEqual(Validators.email("amina@example"), .email)
        XCTAssertEqual(Validators.email("amina"), .email)
        XCTAssertEqual(Validators.email(""), .email)
        // Cas limites de l'expression du serveur : point en tête de domaine, extension d'une lettre, deux « @ ».
        XCTAssertEqual(Validators.email("amina@.dz"), .email)
        XCTAssertEqual(Validators.email("amina@example.d"), .email)
        XCTAssertEqual(Validators.email("a@b@example.com"), .email)
        XCTAssertEqual(Validators.email("ami na@example.com"), .email)
    }

    func testRegistrationPasswordInZodMessageOrder() {
        XCTAssertEqual(Validators.password("Abc1"), .passwordMin)
        XCTAssertEqual(Validators.password("abcdefg1"), .passwordUppercase)
        XCTAssertEqual(Validators.password("Abcdefgh"), .passwordDigit)
        XCTAssertNil(Validators.password("Abcdefg1"))
        XCTAssertEqual(Validators.passwordRequired(""), .passwordRequired)
        XCTAssertNil(Validators.passwordRequired("x"))
    }

    func testOptionalMobilePhoneWithSpacesTolerated() {
        XCTAssertNil(Validators.mobilePhone(""))
        XCTAssertNil(Validators.mobilePhone("0550123456"))
        XCTAssertNil(Validators.mobilePhone("+213 550 12 34 56"))
        XCTAssertEqual(Validators.mobilePhone("0210123456"), .phone) // fixe : refusé à l'inscription
        XCTAssertEqual(Validators.mobilePhone("055012345"), .phone)
        XCTAssertNil(Validators.contactPhone("0210123456")) // fixe : accepté pour une annonce
        XCTAssertEqual(Validators.normalizePhone("+213 550 12 34 56"), "+213550123456")
        // `\d` du serveur = chiffres ASCII seulement.
        XCTAssertEqual(Validators.mobilePhone("٠٥٥٠١٢٣٤٥٦"), .phone)
        XCTAssertEqual(Validators.mobilePhone("+2130550123456"), .phone)
    }

    func testSixDigitCode() {
        XCTAssertNil(Validators.code6("123456"))
        XCTAssertEqual(Validators.code6("12345"), .code)
        XCTAssertEqual(Validators.code6("12345a"), .code)
    }

    func testArabicOrPersianKeyboardDigitsBecomeAscii() {
        XCTAssertEqual(Validators.asciiDigits("١٢٥٠٠٠٠"), "1250000")
        XCTAssertEqual(Validators.asciiDigits("۱۲۵۰۰۰۰"), "1250000")
        XCTAssertEqual(Validators.asciiDigits("1 250 000 DA"), "1250000")
        XCTAssertEqual(Validators.asciiDecimal("١٢.٥ m²"), "12.5")
        XCTAssertEqual(Validators.asciiDigits("abc"), "")
    }

    /// iOS : le pavé décimal écrit « , » en français et « ٫ » en arabe.
    func testKeyboardDecimalSeparatorsBecomeADot() {
        XCTAssertEqual(Validators.asciiDecimal("12,5"), "12.5")
        XCTAssertEqual(Validators.asciiDecimal("١٢٫٥"), "12.5")
    }

    func testPasswordUppercaseAndDigitInTheServerSense() {
        // « É » et « ٣ » passaient un test Unicode mais pas /[A-Z]/ ni /[0-9]/ côté serveur.
        XCTAssertEqual(Validators.password("motdepasseÉ1"), .passwordUppercase)
        XCTAssertEqual(Validators.password("Motdepasse٣"), .passwordDigit)
        XCTAssertNil(Validators.password("Motdepasse1"))
    }

    /// Longueurs en unités UTF-16 comme Zod : un émoji seul fait deux unités, le serveur l'accepte comme nom.
    func testLengthsAreCountedLikeTheServer() {
        XCTAssertNil(Validators.name("😀"))
        XCTAssertEqual(Validators.title("😀😀"), .titleMin)
        XCTAssertNil(Validators.title("😀😀😀"))
    }

    func testPhoneNumberIsIsolatedForRightToLeftSentences() {
        let wrapped = Format.ltrIsolate("+213550123456")
        XCTAssertEqual(wrapped.unicodeScalars.first?.value, 0x2066)
        XCTAssertEqual(wrapped.unicodeScalars.last?.value, 0x2069)
        XCTAssertEqual(String(wrapped.dropFirst().dropLast()), "+213550123456")
    }

    func testEveryMessageIsTranslated() {
        for message in ValidationMessage.allCases {
            XCTAssertFalse(message.text.isEmpty, message.rawValue)
            XCTAssertNotEqual(message.text, message.rawValue)
        }
    }
}
