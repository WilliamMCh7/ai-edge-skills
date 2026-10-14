import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LongScreenshot

/// Decoding, exporting and the demo screenshots (including an end-to-end stitch of the demo set).
final class ImageLoaderTests: XCTestCase {

    // MARK: - ImageLoader

    func testPNGDataIsLossless() throws {
        let data = try encode(makeImage(width: 40, height: 30), as: .png)
        let source = try ImageLoader.sourceImage(from: data)
        XCTAssertFalse(source.isLossy)
        XCTAssertEqual(source.width, 40)
        XCTAssertEqual(source.height, 30)
    }

    func testJPEGDataIsLossy() throws {
        let data = try encode(makeImage(width: 40, height: 30), as: .jpeg)
        let source = try ImageLoader.sourceImage(from: data)
        XCTAssertTrue(source.isLossy)
        XCTAssertEqual(source.width, 40)
        XCTAssertEqual(source.height, 30)
    }

    func testEXIFOrientationIsAppliedToPixels() throws {
        // Stored 60 × 24 with the red third on the left; orientation 6 means "rotate 90° clockwise".
        let data = try encode(makeImage(width: 60, height: 24), as: .jpeg, orientation: 6)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
        XCTAssertEqual((properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue, 6)

        let source = try ImageLoader.sourceImage(from: data)
        XCTAssertTrue(source.isLossy)
        XCTAssertEqual(source.width, 24)
        XCTAssertEqual(source.height, 60)

        let top = pixel(of: source.cgImage, x: 12, y: 6)
        let bottom = pixel(of: source.cgImage, x: 12, y: 54)
        XCTAssertGreaterThan(top.red, 180)
        XCTAssertLessThan(top.blue, 80)
        XCTAssertGreaterThan(bottom.blue, 180)
        XCTAssertLessThan(bottom.red, 80)
    }

    func testUnreadableDataThrows() {
        XCTAssertThrowsError(try ImageLoader.sourceImage(from: Data([0x00, 0x01, 0x02, 0x03]))) { error in
            XCTAssertEqual(error as? ImageLoadError, .unreadable)
        }
        XCTAssertFalse((ImageLoadError.unreadable.errorDescription ?? "").isEmpty)
        XCTAssertFalse((PhotoLibraryError.accessDenied.errorDescription ?? "").isEmpty)
        XCTAssertFalse((PhotoLibraryError.saveFailed.errorDescription ?? "").isEmpty)
    }

    func testThumbnailLimitsLongestSideAndKeepsAspect() {
        let image = makeImage(width: 300, height: 1000)
        let thumbnail = ImageLoader.thumbnail(of: image, maxPixelSize: 100)
        XCTAssertEqual(thumbnail.height, 100)
        XCTAssertEqual(thumbnail.width, 30)

        let wide = ImageLoader.thumbnail(of: makeImage(width: 1000, height: 250), maxPixelSize: 200)
        XCTAssertEqual(wide.width, 200)
        XCTAssertEqual(wide.height, 50)
    }

    func testThumbnailKeepsSmallImages() {
        let image = makeImage(width: 80, height: 60)
        let thumbnail = ImageLoader.thumbnail(of: image, maxPixelSize: 500)
        XCTAssertEqual(thumbnail.width, 80)
        XCTAssertEqual(thumbnail.height, 60)
    }

    // MARK: - ImageExporter

    func testPNGRoundTripKeepsSizeAndPixels() throws {
        let image = makeImage(width: 64, height: 48)
        let data = try ImageExporter.pngData(from: image)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])

        let decoded = try ImageLoader.sourceImage(from: data)
        XCTAssertFalse(decoded.isLossy)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        let red = pixel(of: decoded.cgImage, x: 5, y: 5)
        XCTAssertGreaterThan(red.red, 250)
        XCTAssertLessThan(red.blue, 5)
        let blue = pixel(of: decoded.cgImage, x: 60, y: 40)
        XCTAssertGreaterThan(blue.blue, 250)
        XCTAssertLessThan(blue.red, 5)
    }

    func testWriteTemporaryFileWritesAndOverwrites() throws {
        let name = "prueba-\(UUID().uuidString).bin"
        let first = Data([1, 2, 3])
        let url = try ImageExporter.writeTemporaryFile(first, fileName: name)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.lastPathComponent, name)
        XCTAssertEqual(
            url.deletingLastPathComponent().standardizedFileURL.path,
            FileManager.default.temporaryDirectory.standardizedFileURL.path
        )
        XCTAssertEqual(try Data(contentsOf: url), first)

        let second = Data([9, 8])
        let again = try ImageExporter.writeTemporaryFile(second, fileName: name)
        XCTAssertEqual(again.path, url.path)
        XCTAssertEqual(try Data(contentsOf: again), second)
    }

    // MARK: - Demo screenshots

    func testDemoScreenshotsAreFourLosslessPhoneScreenshots() {
        let shots = DemoScreenshots.make()
        XCTAssertEqual(shots.count, 4)
        for shot in shots {
            XCTAssertEqual(shot.width, 1179)
            XCTAssertEqual(shot.height, 2556)
            XCTAssertFalse(shot.isLossy)
        }
        XCTAssertEqual(Set(shots.map(\.id)).count, shots.count)
    }

    func testDemoScreenshotsStitchPerfectly() throws {
        let shots = DemoScreenshots.make()
        XCTAssertEqual(shots.count, 4)

        let output = try Stitcher.stitch(shots)
        let plan = output.plan
        XCTAssertEqual(plan.seams.count, 3)
        XCTAssertTrue(plan.seams.allSatisfy { $0.kind == .matched }, "Seams: \(plan.seams)")
        XCTAssertEqual(plan.seams.map { $0.offset ?? 0 }, DemoScreenshots.scrollSteps)
        XCTAssertEqual(plan.imageIndices, [0, 1, 2, 3])
        XCTAssertFalse(plan.autoReversed)
        XCTAssertTrue(plan.droppedDuplicates.isEmpty)

        XCTAssertEqual(output.image.width, 1179)
        XCTAssertLessThan(output.image.height, 4 * 2556)
        XCTAssertEqual(output.image.height, 2556 + DemoScreenshots.scrollSteps.reduce(0, +))

        // Every output row is an exact copy of the source row the plan says it comes from.
        let outputBytes = rgbaBytes(of: output.image)
        let rowLength = output.image.width * 4
        var outputRow = 0
        for segment in plan.segments(sourceHeights: output.sources.map(\.height)) {
            let sourceBytes = rgbaBytes(of: output.sources[segment.sourceIndex].cgImage)
            for row in segment.rows {
                let outputStart = outputRow * rowLength
                let sourceStart = row * rowLength
                if outputBytes[outputStart..<(outputStart + rowLength)] != sourceBytes[sourceStart..<(sourceStart + rowLength)] {
                    XCTFail("Output row \(outputRow) differs from row \(row) of source \(segment.sourceIndex)")
                    return
                }
                outputRow += 1
            }
        }
        XCTAssertEqual(outputRow, output.image.height)
    }

    // MARK: - Helpers

    /// Opaque test image: the left third red, the rest blue.
    private func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            fatalError("Could not create a bitmap context")
        }
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 3, height: height))
        guard let image = context.makeImage() else { fatalError("Could not create the test image") }
        return image
    }

    private func encode(_ image: CGImage, as type: UTType, orientation: Int? = nil) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// RGBA8 sRGB bytes of an image, top row first.
    private func rgbaBytes(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private func pixel(of image: CGImage, x: Int, y: Int) -> (red: Int, green: Int, blue: Int) {
        let bytes = rgbaBytes(of: image)
        let index = (y * image.width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }
}
