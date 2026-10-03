#if DEBUG
import ImageIO
import XCTest
@testable import Weyda

/// Socle de l'API simulée : une route connue sert sa fixture, une route inconnue répond 404
/// au format de l'API (`{ "error": "notFound" }`), la route la plus précise gagne, et les photos
/// fictives sont dessinées à la bonne taille.
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
        XCTAssertGreaterThanOrEqual(MockRoutes.shared.count, 2)
        XCTAssertEqual(MockRoutes.shared.reply(method: "get", path: "/api/_selftest").status, 200)
    }

    func testMostSpecificRouteWins() throws {
        let json = Data("""
        [
          { "method": "GET", "path": "/api/annonces/*", "status": 201 },
          { "method": "GET", "path": "/api/annonces", "status": 202 },
          { "method": "GET", "path": "/api/annonces", "query": { "featured": "1" }, "status": 203 },
          { "method": "GET", "path": "/api/annonces/featured-car", "status": 204 },
          { "method": "POST", "path": "/api/annonces/*/view", "status": 205 },
          { "method": "GET", "path": "/api/wilayas", "query": { "wilayaId": "*" }, "status": 206 },
          { "method": "GET", "path": "/api/wilayas", "query": { "wilayaId": "16" }, "status": 207 },
          { "method": "GET", "path": "/api/wilayas", "status": 208 }
        ]
        """.utf8)
        let routes = MockRoutes(routes: try JSONDecoder().decode([MockRoute].self, from: json), root: nil)
        func status(_ method: String, _ path: String) throws -> Int {
            routes.reply(method: method, url: try XCTUnwrap(URL(string: "https://weydaa.com\(path)"))).status
        }
        XCTAssertEqual(try status("GET", "/api/annonces/abc"), 201)
        XCTAssertEqual(try status("GET", "/api/annonces?page=2"), 202)
        XCTAssertEqual(try status("GET", "/api/annonces?featured=1&limit=8"), 203)
        XCTAssertEqual(try status("GET", "/api/annonces/featured-car"), 204)
        XCTAssertEqual(try status("POST", "/api/annonces/abc/view"), 205)
        XCTAssertEqual(try status("DELETE", "/api/annonces/abc"), 404)
        XCTAssertEqual(try status("GET", "/api/annonces/abc/extra"), 404)
        // Joker de requête : présent, valeur quelconque ; une valeur exacte reste prioritaire.
        XCTAssertEqual(try status("GET", "/api/wilayas?wilayaId=9"), 206)
        XCTAssertEqual(try status("GET", "/api/wilayas?wilayaId=16"), 207)
        XCTAssertEqual(try status("GET", "/api/wilayas"), 208)
    }

    func testPhotosAreDrawnAtFullAndThumbnailSize() throws {
        let full = MockRoutes.shared.reply(method: "GET", url: try XCTUnwrap(URL(string: "https://photos.mock.weydaa/annonces/car-1.webp")))
        XCTAssertEqual(full.status, 200)
        XCTAssertEqual(full.contentType, "image/jpeg")
        XCTAssertEqual(try pixelSize(full.body), CGSize(width: 1200, height: 900))

        let thumb = MockRoutes.shared.reply(method: "GET", url: try XCTUnwrap(URL(string: "https://photos.mock.weydaa/annonces/car-1_thumb.webp")))
        XCTAssertEqual(try pixelSize(thumb.body), CGSize(width: 400, height: 300))

        // Reproductible : même nom, mêmes octets (captures identiques d'un tour à l'autre).
        XCTAssertEqual(MockPhotos.jpeg(named: "sofa-2.webp"), MockPhotos.jpeg(named: "sofa-2.webp"))
        XCTAssertNotEqual(MockPhotos.jpeg(named: "sofa-2.webp"), MockPhotos.jpeg(named: "house-2.webp"))
    }

    private func pixelSize(_ data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return CGSize(width: width, height: height)
    }
}
#endif
