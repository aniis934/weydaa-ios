import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Weyda

/// Préparation des photos avant envoi : JPEG valide, côté long ≤ 1600 px, orientation EXIF appliquée,
/// aucune métadonnée de position, erreurs typées.
final class ImagePreparerTests: XCTestCase {

    /// Image synthétique (deux aplats) encodée au format demandé, avec des propriétés facultatives (EXIF, GPS).
    private func makeImage(
        width: Int,
        height: Int,
        type: UTType = .jpeg,
        transparent: Bool = false,
        properties: [CFString: Any] = [:]
    ) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedLast : .noneSkipLast
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: alpha.rawValue
        ))
        if transparent {
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            context.setFillColor(CGColor(srgbRed: 0.06, green: 0.73, blue: 0.51, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(CGColor(srgbRed: 0.86, green: 0.15, blue: 0.15, alpha: 1))
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int) {
        let values = try properties(of: data)
        let width = try XCTUnwrap(values[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(values[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }

    private func isJPEG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier
    }

    func testALargePhotoIsReducedTo1600PixelsOnTheLongSide() throws {
        let input = try makeImage(width: 3_000, height: 2_000)
        let output = try ImagePreparer().prepareSynchronously(input)
        XCTAssertTrue(isJPEG(output))
        let size = try pixelSize(of: output)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 1_600)
        XCTAssertGreaterThanOrEqual(max(size.width, size.height), 1_590)
        XCTAssertEqual(Double(size.width) / Double(size.height), 1.5, accuracy: 0.01)
        XCTAssertLessThanOrEqual(output.count, 4 * 1024 * 1024)
    }

    func testASmallPhotoIsNotEnlarged() throws {
        let input = try makeImage(width: 800, height: 600, type: .png)
        let output = try ImagePreparer().prepareSynchronously(input)
        XCTAssertTrue(isJPEG(output))
        let size = try pixelSize(of: output)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)
    }

    /// Orientation EXIF 6 (photo prise en portrait) : les pixels sont tournés, plus aucune balise à interpréter.
    func testExifOrientationIsAppliedToThePixels() throws {
        let input = try makeImage(width: 400, height: 200, properties: [kCGImagePropertyOrientation: 6])
        let output = try ImagePreparer().prepareSynchronously(input)
        let size = try pixelSize(of: output)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 400)
        let orientation = try properties(of: output)[kCGImagePropertyOrientation] as? Int
        XCTAssertTrue(orientation == nil || orientation == 1, "orientation restante : \(String(describing: orientation))")
    }

    func testNoLocationOrExifLeavesTheDevice() throws {
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 36.75, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 3.06, kCGImagePropertyGPSLongitudeRef: "E",
        ]
        let exif: [CFString: Any] = [kCGImagePropertyExifUserComment: "Karim B."]
        let input = try makeImage(width: 1_200, height: 900, properties: [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyExifDictionary: exif])
        // Contrôle du test lui-même : la source porte bien une position.
        XCTAssertNotNil(try properties(of: input)[kCGImagePropertyGPSDictionary])

        let output = try ImagePreparer().prepareSynchronously(input)
        let values = try properties(of: output)
        XCTAssertNil(values[kCGImagePropertyGPSDictionary])
        let outputExif = values[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(outputExif?[kCGImagePropertyExifUserComment])
    }

    /// Transparence posée sur du blanc (le JPEG l'aurait rendue noire).
    func testTransparencyBecomesWhite() throws {
        let input = try makeImage(width: 64, height: 64, type: .png, transparent: true)
        let output = try ImagePreparer().prepareSynchronously(input)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drawn)
        XCTAssertGreaterThan(pixel[0], 240)
        XCTAssertGreaterThan(pixel[1], 240)
        XCTAssertGreaterThan(pixel[2], 240)
    }

    func testUnreadableDataIsATypedError() {
        XCTAssertThrowsError(try ImagePreparer().prepareSynchronously(Data("pas une image".utf8))) { error in
            XCTAssertEqual(error as? ImagePreparationError, .unreadable)
        }
        XCTAssertThrowsError(try ImagePreparer().prepareSynchronously(Data())) { error in
            XCTAssertEqual(error as? ImagePreparationError, .unreadable)
        }
    }

    func testAnImpossibleSizeLimitOrAHugeSourceIsTooLarge() throws {
        let input = try makeImage(width: 300, height: 200)
        XCTAssertThrowsError(try ImagePreparer(maxBytes: 100).prepareSynchronously(input)) { error in
            XCTAssertEqual(error as? ImagePreparationError, .tooLarge)
        }
        XCTAssertThrowsError(try ImagePreparer(maxSourcePixels: 1_000).prepareSynchronously(input)) { error in
            XCTAssertEqual(error as? ImagePreparationError, .tooLarge)
        }
    }

    func testAsyncVersionRunsOffTheCallerAndMatches() async throws {
        let input = try makeImage(width: 2_400, height: 1_200)
        let output = try await ImagePreparer().prepare(input)
        XCTAssertTrue(isJPEG(output))
        let size = try pixelSize(of: output)
        XCTAssertLessThanOrEqual(size.width, 1_600)
        XCTAssertGreaterThanOrEqual(size.width, 1_590)
        XCTAssertEqual(Double(size.width) / Double(size.height), 2, accuracy: 0.01)

        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("absente-\(UUID().uuidString).jpg")
        do {
            _ = try await ImagePreparer().prepare(fileAt: missing)
            XCTFail("fichier absent accepté")
        } catch {
            XCTAssertEqual(error as? ImagePreparationError, .unreadable)
        }
    }
}
