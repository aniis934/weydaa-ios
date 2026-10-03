import CoreGraphics
import ImageIO
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Weyda

/// Pipeline d'images : réduction à la taille affichée, caches mémoire et disque, demandes fusionnées,
/// annulation, préchargement. Aucun réseau : `ImageStubProtocol` sert des PNG synthétiques.
final class ImagePipelineTests: XCTestCase {
    private let stub = ImageStubProtocol.stub

    private func makePNG(width: Int, height: Int) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.06, green: 0.73, blue: 0.51, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// Une URL neuve par test : le compteur de requêtes du faux serveur lui est propre.
    private func uniqueURL() throws -> URL {
        try XCTUnwrap(URL(string: "https://images.weydaa.test/\(UUID().uuidString).png"))
    }

    private func makePipeline(memory: ImageMemoryCache? = ImageMemoryCache(), disk: ImageDiskCache? = nil) -> ImagePipeline {
        ImagePipeline(session: ImagePipeline.makeSession(protocolClasses: [ImageStubProtocol.self]), memory: memory, disk: disk)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ImagePipelineTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Réduction

    func testDecodingCoversTheDisplaySizeWithoutDecodingTheOriginal() throws {
        let data = try makePNG(width: 2_000, height: 1_000)
        let url = try uniqueURL()
        // 100 × 100 pt en 2x → 200 px, palier 256 : pour COUVRIR 256 × 256, la hauteur fait 256, la largeur 512.
        let request = ImageRequest(url: url, targetSize: CGSize(width: 100, height: 100), scale: 2)
        XCTAssertEqual(request.pixelWidth, 256)
        XCTAssertEqual(request.pixelHeight, 256)
        let image = try XCTUnwrap(ImageDecoder.decode(data, for: request))
        let bitmap = try XCTUnwrap(image.cgImage)
        XCTAssertLessThanOrEqual(bitmap.width, 520)
        XCTAssertGreaterThanOrEqual(bitmap.height, 250)
        XCTAssertLessThanOrEqual(bitmap.height, 260)
        XCTAssertEqual(image.scale, 2)
    }

    func testASmallImageIsNeverEnlargedAndAnUnknownSizeKeepsTheOriginal() throws {
        let data = try makePNG(width: 300, height: 200)
        let url = try uniqueURL()
        let large = ImageRequest(url: url, targetSize: CGSize(width: 400, height: 400), scale: 3)
        XCTAssertEqual(try XCTUnwrap(ImageDecoder.decode(data, for: large)?.cgImage).width, 300)
        let unknown = ImageRequest(url: url, targetSize: .zero, scale: 3)
        XCTAssertFalse(unknown.hasTargetSize)
        XCTAssertEqual(try XCTUnwrap(ImageDecoder.decode(data, for: unknown)?.cgImage).width, 300)
        XCTAssertNil(ImageDecoder.decode(Data("pas une image".utf8), for: large))
    }

    func testNeighbouringCellSizesShareOneCacheKey() throws {
        let url = try uniqueURL()
        let first = ImageRequest(url: url, targetSize: CGSize(width: 172.5, height: 129.4), scale: 3)
        let second = ImageRequest(url: url, targetSize: CGSize(width: 173, height: 129), scale: 3)
        XCTAssertEqual(first.cacheKey, second.cacheKey)
        XCTAssertEqual(first.pixelWidth, 576)
        XCTAssertNotEqual(first.cacheKey, ImageRequest(url: url, targetSize: CGSize(width: 400, height: 300), scale: 3).cacheKey)
    }

    // MARK: - Caches

    func testTheSecondCallIsServedFromMemory() async throws {
        let url = try uniqueURL()
        let png = try makePNG(width: 400, height: 300)
        stub.serve(url, body: png)
        let pipeline = makePipeline()
        let request = ImageRequest(url: url, targetSize: CGSize(width: 100, height: 75), scale: 2)
        XCTAssertNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.image(for: request)
        XCTAssertEqual(stub.requestCount(for: url), 1)
        XCTAssertNotNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.image(for: request)
        XCTAssertEqual(stub.requestCount(for: url), 1)
    }

    func testADiskCacheServesAFreshPipeline() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ImageDiskCache(directory: directory, sizeLimit: 10 * 1024 * 1024)
        let url = try uniqueURL()
        let png = try makePNG(width: 400, height: 300)
        stub.serve(url, body: png)
        let request = ImageRequest(url: url, targetSize: CGSize(width: 100, height: 75), scale: 2)

        _ = try await makePipeline(disk: disk).image(for: request)
        _ = try await makePipeline(disk: disk).image(for: request)
        XCTAssertEqual(stub.requestCount(for: url), 1)
    }

    func testTheDiskCacheDropsTheLeastRecentlyUsedFilesFirst() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ImageDiskCache(directory: directory, sizeLimit: 1_000)
        let old = try uniqueURL()
        let recent = try uniqueURL()
        let newest = try uniqueURL()

        disk.store(Data(count: 400), for: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: disk.fileURL(for: old).path)
        disk.store(Data(count: 400), for: recent)
        disk.store(Data(count: 400), for: newest) // 1 200 > 1 000 : élagage jusqu'à 800, le plus ancien part

        XCTAssertNil(disk.data(for: old))
        XCTAssertNotNil(disk.data(for: recent))
        XCTAssertNotNil(disk.data(for: newest))
    }

    func testAMissingImageFailsOnceThenWithoutTheNetwork() async throws {
        let url = try uniqueURL() // non servie → 404
        let pipeline = makePipeline()
        let request = ImageRequest(url: url, targetSize: CGSize(width: 50, height: 50), scale: 2)
        for _ in 0..<2 {
            do {
                _ = try await pipeline.image(for: request)
                XCTFail("une image absente a été rendue")
            } catch {
                XCTAssertEqual(error as? ImageLoadingError, .httpStatus(404))
            }
        }
        XCTAssertEqual(stub.requestCount(for: url), 1)
    }

    // MARK: - Demandes en vol

    /// Sans aucun cache, seule la fusion des demandes explique un téléchargement unique.
    func testIdenticalRequestsInFlightShareOneDownload() async throws {
        let url = try uniqueURL()
        let png = try makePNG(width: 300, height: 300)
        stub.serve(url, body: png, delay: 0.8)
        let pipeline = makePipeline(memory: nil)
        let request = ImageRequest(url: url, targetSize: CGSize(width: 50, height: 50), scale: 2)

        async let first = pipeline.image(for: request)
        async let second = pipeline.image(for: request)
        let images = try await [first, second]
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(stub.requestCount(for: url), 1)
        XCTAssertEqual(pipeline.inFlightCount, 0)

        _ = try await pipeline.image(for: request) // sans cache : nouvelle requête
        XCTAssertEqual(stub.requestCount(for: url), 2)
    }

    func testCancellingTheOnlyWaiterReturnsAtOnce() async throws {
        let url = try uniqueURL()
        let png = try makePNG(width: 300, height: 300)
        stub.serve(url, body: png, delay: 2)
        let pipeline = makePipeline(memory: nil)
        let request = ImageRequest(url: url, targetSize: CGSize(width: 50, height: 50), scale: 2)

        let task = Task { try await pipeline.image(for: request) }
        try await Task.sleep(nanoseconds: 150_000_000)
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("l'annulation a été ignorée")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
        XCTAssertEqual(pipeline.inFlightCount, 0)
    }

    // MARK: - Préchargement

    func testAViewJoinsAPrefetchInsteadOfDownloadingAgain() async throws {
        let url = try uniqueURL()
        let png = try makePNG(width: 300, height: 300)
        stub.serve(url, body: png, delay: 0.5)
        let pipeline = makePipeline()
        let size = CGSize(width: 50, height: 50)

        pipeline.prefetch(urls: [url], targetSize: size, scale: 2)
        _ = try await pipeline.image(for: url, targetSize: size, scale: 2)
        XCTAssertEqual(stub.requestCount(for: url), 1)
        XCTAssertNotNil(pipeline.cachedImage(for: ImageRequest(url: url, targetSize: size, scale: 2)))
    }

    func testACancelledPrefetchDoesNotLeakIntoTheNextRequest() async throws {
        let url = try uniqueURL()
        let png = try makePNG(width: 300, height: 300)
        stub.serve(url, body: png, delay: 0.3)
        let pipeline = makePipeline()
        let size = CGSize(width: 50, height: 50)

        pipeline.prefetch(urls: [url], targetSize: size, scale: 2)
        XCTAssertEqual(pipeline.inFlightCount, 1)
        pipeline.cancelPrefetch(urls: [url], targetSize: size, scale: 2)
        XCTAssertEqual(pipeline.inFlightCount, 0)
        // Une vue qui demande ensuite la même image l'obtient (elle n'hérite pas du chargement annulé).
        _ = try await pipeline.image(for: url, targetSize: size, scale: 2)
    }

    // MARK: - Vue

    @MainActor
    func testRemoteImageLaysOutWithoutAnURL() {
        let host = UIHostingController(rootView: RemoteImage(url: nil).frame(width: 120, height: 90))
        host.view.frame = CGRect(x: 0, y: 0, width: 120, height: 90)
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.size, CGSize(width: 120, height: 90))
    }
}

/// Faux serveur d'images : réponses par URL, compteur de requêtes, délai réglable (en bloquant le fil de
/// chargement d'URLSession, jamais celui du test).
final class ImageStubProtocol: URLProtocol {
    static let stub = ImageStub()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = Self.stub.reply(for: url)
        if reply.delay > 0 { Thread.sleep(forTimeInterval: reply.delay) }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ImageStub: Sendable {
    struct Route: Sendable {
        let status: Int
        let body: Data
        let delay: TimeInterval
    }

    private struct State: Sendable {
        var routes: [URL: Route] = [:]
        var counts: [URL: Int] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func serve(_ url: URL, body: Data, status: Int = 200, delay: TimeInterval = 0) {
        state.withLockUnchecked { $0.routes[url] = Route(status: status, body: body, delay: delay) }
    }

    func requestCount(for url: URL) -> Int {
        state.withLockUnchecked { $0.counts[url] ?? 0 }
    }

    func reply(for url: URL) -> Route {
        state.withLockUnchecked { state in
            state.counts[url, default: 0] += 1
            return state.routes[url] ?? Route(status: 404, body: Data(), delay: 0)
        }
    }
}
