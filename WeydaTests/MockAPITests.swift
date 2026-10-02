#if DEBUG
import XCTest
@testable import Weyda

/// Socle de l'API simulée : une route connue sert sa fixture, une route inconnue répond 404
/// au format de l'API (`{ "error": "notFound" }`).
final class MockAPITests: XCTestCase {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testKnownRouteServesItsFixture() async throws {
        let url = try XCTUnwrap(URL(string: "https://weydaa.com/api/_selftest"))
        let (data, response) = try await session().data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["ok"] as? Bool, true)
        XCTAssertEqual(json["source"] as? String, "mock")
    }

    func testUnknownRouteAnswers404LikeTheAPI() async throws {
        let url = try XCTUnwrap(URL(string: "https://weydaa.com/api/nothing-here"))
        let (data, response) = try await session().data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["error"] as? String, "notFound")
    }

    func testRoutesTableIsBundled() {
        XCTAssertEqual(MockRoutes.shared.reply(method: "get", path: "/api/_selftest").status, 200)
    }
}
#endif
