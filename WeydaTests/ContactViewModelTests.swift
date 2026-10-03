import Foundation
import XCTest
@testable import Weyda

/// « Nous contacter » (ContactViewModel, ContactScreen.kt — sans test Android : cas tirés du ViewModel et de
/// `contactSchema`) : pré-remplissage d'un membre, règles locales, envoi nettoyé, erreurs du serveur. Données fictives.
final class ContactViewModelTests: XCTestCase {
    static func member() -> User {
        User(id: "user_1", name: "Amina", email: "amina@example.com", avatarUrl: nil, role: "USER", emailVerified: true)
    }

    @MainActor
    func testMemberIsPrefilledAndVisitorStartsEmpty() {
        let api = FakeWeydaAPI()
        let member = ContactViewModel(api: api, user: Self.member())
        XCTAssertEqual(member.state.name, "Amina")
        XCTAssertEqual(member.state.email, "amina@example.com")
        XCTAssertEqual(member.state.subject, "")
        let visitor = ContactViewModel(api: api, user: nil)
        XCTAssertEqual(visitor.state.name, "")
        XCTAssertEqual(visitor.state.email, "")
    }

    @MainActor
    func testLocalRulesBlockTheSendingAndTypingClearsTheFieldError() {
        let api = FakeWeydaAPI()
        let model = ContactViewModel(api: api, user: nil)
        model.update(.name, to: " A ")
        model.update(.email, to: "amina@")
        model.update(.subject, to: "Ok")
        model.update(.message, to: "Trop court")  // 10 caractères : accepté
        XCTAssertNil(model.send())
        XCTAssertEqual(model.state.nameError, L10n.validationNameMin)
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        XCTAssertEqual(model.state.subjectError, L10n.validationSubjectMin)
        XCTAssertNil(model.state.messageError)
        XCTAssertFalse(model.state.isSending)
        XCTAssertEqual(api.count("contact"), 0)

        model.update(.message, to: "  court  ")
        XCTAssertNil(model.send())
        XCTAssertEqual(model.state.messageError, L10n.validationMessageMin)
        model.update(.name, to: "Amina")
        XCTAssertNil(model.state.nameError)
        XCTAssertEqual(model.value(of: .name), "Amina")
    }

    @MainActor
    func testInputIsBoundedLikeTheServerAndTheEmailLosesItsSpaces() {
        let model = ContactViewModel(api: FakeWeydaAPI(), user: nil)
        model.onName(String(repeating: "n", count: 150))
        XCTAssertEqual(model.state.name.utf16.count, ContactState.nameMax)
        model.onSubject(String(repeating: "s", count: 250))
        XCTAssertEqual(model.state.subject.utf16.count, ContactState.subjectMax)
        model.onMessage(String(repeating: "m", count: 6000))
        XCTAssertEqual(model.state.message.utf16.count, ContactState.messageMax)
        model.onEmail("  amina@example.com ")
        XCTAssertEqual(model.state.email, "amina@example.com")
    }

    @MainActor
    func testSendingTrimsTheFieldsThenClearsSubjectAndMessage() async {
        let api = FakeWeydaAPI()
        let model = ContactViewModel(api: api, user: Self.member())
        model.onSubject("  Annonce introuvable ")
        model.onMessage("  Mon annonce n'apparaît plus dans les résultats.  ")
        api.onContact = { body in
            XCTAssertEqual(body.name, "Amina")
            XCTAssertEqual(body.email, "amina@example.com")
            XCTAssertEqual(body.subject, "Annonce introuvable")
            XCTAssertEqual(body.message, "Mon annonce n'apparaît plus dans les résultats.")
            return SimpleResponseDTO()
        }
        let sending = model.send()
        XCTAssertTrue(model.state.isSending)
        XCTAssertNil(model.send())  // un seul envoi à la fois
        await sending?.value
        XCTAssertTrue(model.state.isSent)
        XCTAssertFalse(model.state.isSending)
        XCTAssertEqual(model.state.subject, "")
        XCTAssertEqual(model.state.message, "")
        XCTAssertEqual(model.state.name, "Amina")  // gardés pour un autre message
        XCTAssertEqual(api.count("contact"), 1)
    }

    @MainActor
    func testServerRefusalShowsTheMessageAndTheFieldErrors() async {
        let api = FakeWeydaAPI()
        let model = ContactViewModel(api: api, user: Self.member())
        model.onSubject("Question")
        model.onMessage("Bonjour, une question sur mon compte.")
        api.onContact = { _ in throw FakeWeydaAPI.apiError(429, #"{"error":"rateLimited"}"#) }
        await model.send()?.value
        XCTAssertEqual(model.state.errorMessage, L10n.errorRateLimited)
        XCTAssertFalse(model.state.isSent)
        XCTAssertFalse(model.state.isSending)
        XCTAssertEqual(model.state.subject, "Question")  // rien n'est perdu

        api.onContact = { _ in
            throw FakeWeydaAPI.apiError(400, #"{"error":"invalidData","details":{"fieldErrors":{"email":["validation.emailInvalid"]}}}"#)
        }
        await model.send()?.value
        XCTAssertEqual(model.state.emailError, L10n.validationEmail)
        model.onEmail("amina@example.com")
        XCTAssertNil(model.state.emailError)
        XCTAssertNil(model.state.errorMessage)
    }
}
