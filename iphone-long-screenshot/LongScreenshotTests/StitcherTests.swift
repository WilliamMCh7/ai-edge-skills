import CoreGraphics
import Foundation
import XCTest
@testable import LongScreenshot

/// End-to-end tests of the stitching core on synthetic scrolling sessions (port of
/// `reference/test_stitch.py`). Lossless cases must reconstruct the page pixel-exactly.
final class StitcherTests: XCTestCase {

    // MARK: - Lossless reconstruction

    func testMixedContentReconstructsExactly() throws {
        for seed: UInt64 in [1, 2, 3] {
            var options = SyntheticOptions()
            options.pageHeight = 3000
            try assertExactReconstruction(SyntheticScreens.make(seed: seed, options: options), label: "mixed seed \(seed)")
        }
    }

    func testHugeOverlapsReconstructExactly() throws {
        var options = SyntheticOptions()
        options.pageHeight = 2500
        options.overlap = 0.85...0.95
        try assertExactReconstruction(SyntheticScreens.make(seed: 12, options: options), label: "huge overlaps")
    }

    func testRepetitiveListRowsReconstructExactly() throws {
        var options = SyntheticOptions()
        options.repetitive = true
        try assertExactReconstruction(SyntheticScreens.make(seed: 13, options: options), label: "list rows")
    }

    func testThreeTimesResolutionReconstructsExactly() throws {
        var options = SyntheticOptions()
        options.width = 1179
        options.height = 2556
        options.headerHeight = 273
        options.footerHeight = 249
        options.pageHeight = 9000
        options.maxShots = 4
        try assertExactReconstruction(SyntheticScreens.make(seed: 17, options: options), label: "3x")
    }

    func testFloatingButtonNeverProducesWrongOffsets() {
        var total = 0
        var matched = 0
        for seed: UInt64 in [16, 17, 18] {
            var options = SyntheticOptions()
            options.pageHeight = 3000
            options.blankBlocks = false
            options.overlap = 0.5...0.8
            options.floatingButton = true
            let synthetic = SyntheticScreens.make(seed: seed, options: options)
            let plan = Stitcher.makePlan(for: synthetic.shots)
            XCTAssertEqual(plan.imageIndices, Array(0..<synthetic.shots.count), "seed \(seed)")
            for (seam, expected) in zip(plan.seams, synthetic.expectedSeamOffsets) {
                total += 1
                if seam.kind == .matched {
                    matched += 1
                    XCTAssertEqual(seam.offset, expected, "seed \(seed): matched seam with a wrong offset")
                }
            }
        }
        XCTAssertGreaterThan(total, 0)
        // The button hides part of the overlap; most seams must still be found.
        XCTAssertGreaterThanOrEqual(matched * 5, total * 4, "matched \(matched) of \(total)")
    }

    // MARK: - Order and duplicates

    func testDuplicateScreenshotIsDropped() {
        let synthetic = duplicateAndReverseCase()
        var shots = synthetic.shots
        shots.insert(shots[1], at: 2)
        let plan = Stitcher.makePlan(for: shots)
        XCTAssertEqual(plan.imageIndices, [0, 1, 3, 4, 5])
        XCTAssertEqual(plan.droppedDuplicates, [2])
        XCTAssertFalse(plan.autoReversed)
    }

    func testReversedInputIsAutoReversedAndExact() throws {
        let synthetic = duplicateAndReverseCase()
        let reversedShots = Array(synthetic.shots.reversed())
        let output = try Stitcher.stitch(reversedShots)
        XCTAssertTrue(output.plan.autoReversed)
        XCTAssertEqual(output.plan.imageIndices, Array((0..<reversedShots.count).reversed()))
        XCTAssertFalse(output.plan.needsReview)
        assertPixelsEqual(output.image, synthetic.groundTruth, label: "reversed")
    }

    // MARK: - Unmeasurable and lossy overlaps

    func testBlankOverlapIsEstimatedWithoutLosingContent() throws {
        let synthetic = SyntheticScreens.makeBlankOverlapCase(seed: 31)
        let output = try Stitcher.stitch(synthetic.shots)
        XCTAssertEqual(output.plan.seams.map(\.kind), [Seam.Kind.matched, .estimated, .matched])
        XCTAssertEqual(output.plan.reviewCount, 1)
        XCTAssertTrue(output.plan.needsReview)
        // Blank space is unmeasurable, but every non-blank row must appear exactly once, in order.
        let stitchedRows = nonWhiteRows(of: output.image)
        let expectedRows = nonWhiteRows(of: synthetic.groundTruth)
        XCTAssertEqual(stitchedRows.count, expectedRows.count)
        XCTAssertTrue(stitchedRows == expectedRows, "non-blank rows differ from the ground truth")
    }

    func testJPEGSeamsAreWithinFourPixels() {
        for seed: UInt64 in [42, 45] {
            var options = SyntheticOptions()
            options.pageHeight = 3000
            options.blankBlocks = false
            options.jpeg = true
            let synthetic = SyntheticScreens.make(seed: seed, options: options)
            XCTAssertTrue(synthetic.shots.allSatisfy(\.isLossy))
            let plan = Stitcher.makePlan(for: synthetic.shots)
            XCTAssertEqual(plan.imageIndices, Array(0..<synthetic.shots.count), "seed \(seed)")
            var matched = 0
            for (seam, expected) in zip(plan.seams, synthetic.expectedSeamOffsets) where seam.kind == .matched {
                matched += 1
                let offset = seam.offset ?? Int.min / 2
                XCTAssertLessThanOrEqual(abs(offset - expected), 4, "seed \(seed): offset \(offset), expected \(expected)")
            }
            XCTAssertGreaterThanOrEqual(matched * 2, plan.seams.count, "seed \(seed): matched \(matched) of \(plan.seams.count)")
        }
    }

    // MARK: - Widths, rendering, API contract

    func testNormalizeWidthsScalesToFirstWidth() {
        let first = SourceImage(cgImage: solidImage(width: 390, height: 844, gray: 200), isLossy: false)
        let wider = SourceImage(cgImage: solidImage(width: 780, height: 1688, gray: 120), isLossy: false)
        let narrower = SourceImage(cgImage: solidImage(width: 195, height: 300, gray: 60), isLossy: false)
        let normalized = Stitcher.normalizeWidths([first, wider, narrower])

        XCTAssertEqual(normalized.map(\.width), [390, 390, 390])
        XCTAssertEqual(normalized.map(\.height), [844, 844, 600])
        XCTAssertEqual(normalized.map(\.id), [first.id, wider.id, narrower.id])
        XCTAssertTrue(normalized[0].cgImage === first.cgImage, "an image that already fits must be kept as is")
        XCTAssertFalse(normalized[0].isLossy)
        XCTAssertTrue(normalized[1].isLossy, "resampled images use the tolerant matcher")
        XCTAssertTrue(Stitcher.normalizeWidths([]).isEmpty)
    }

    func testRenderDownscaleMath() {
        XCTAssertEqual(StitchRenderer.maxOutputPixels, 60_000_000)

        let fits = StitchRenderer.outputSize(width: 1179, height: 50_000, maxPixels: 60_000_000)
        XCTAssertEqual(fits.width, 1179)
        XCTAssertEqual(fits.height, 50_000)

        let scaled = StitchRenderer.outputSize(width: 1000, height: 100_000, maxPixels: 60_000_000)
        XCTAssertEqual(scaled.width, 774)      // 1000 · sqrt(0.6)
        XCTAssertEqual(scaled.height, 77_459)  // 100 000 · sqrt(0.6)
        XCTAssertLessThanOrEqual(scaled.width * scaled.height, 60_000_000)

        let tiny = StitchRenderer.outputSize(width: 10, height: 1_000_000, maxPixels: 100)
        XCTAssertGreaterThanOrEqual(tiny.width, 1)
        XCTAssertLessThanOrEqual(tiny.width * tiny.height, 100)
    }

    func testRenderMatchesPlanSizeAndSeamPreview() throws {
        var options = SyntheticOptions()
        options.pageHeight = 3000
        let synthetic = SyntheticScreens.make(seed: 1, options: options)
        let output = try Stitcher.stitch(synthetic.shots)
        let heights = output.sources.map(\.height)
        XCTAssertEqual(output.image.width, output.plan.width)
        XCTAssertEqual(output.image.height, output.plan.outputHeight(sourceHeights: heights))

        let context = 100
        XCTAssertNil(StitchRenderer.renderSeamPreview(plan: output.plan, seamIndex: -1, sources: output.sources, context: context))
        XCTAssertNil(StitchRenderer.renderSeamPreview(plan: output.plan, seamIndex: output.plan.seams.count,
                                                      sources: output.sources, context: context))
        let preview = try XCTUnwrap(StitchRenderer.renderSeamPreview(plan: output.plan, seamIndex: 0,
                                                                     sources: output.sources, context: context))
        XCTAssertEqual(preview.width, output.plan.width)
        XCTAssertEqual(preview.height, 2 * context)

        // The preview shows exactly the stitched rows around the seam.
        let segments = output.plan.segments(sourceHeights: heights)
        let seamY = output.plan.seamPositions(sourceHeights: heights)[0]
        if segments[0].rows.count >= context && segments[1].rows.count >= context {
            let previewPixels = pixels(of: preview)
            let stitchedPixels = pixels(of: output.image)
            let rowBytes = preview.width * 4
            let expected = stitchedPixels[(seamY - context) * rowBytes ..< (seamY + context) * rowBytes]
            XCTAssertTrue(previewPixels[...] == expected, "seam preview differs from the stitched rows")
        }
    }

    func testStitchRequiresTwoImages() {
        let single = SourceImage(cgImage: solidImage(width: 100, height: 200, gray: 128), isLossy: false)
        XCTAssertThrowsError(try Stitcher.stitch([single])) { error in
            XCTAssertEqual(error as? StitchError, .notEnoughImages)
        }
        XCTAssertThrowsError(try Stitcher.stitch([]))
        XCTAssertNotNil(StitchError.notEnoughImages.errorDescription)
        XCTAssertNotNil(StitchError.renderFailed.errorDescription)

        let plan = Stitcher.makePlan(for: [single])
        XCTAssertEqual(plan.imageIndices, [0])
        XCTAssertTrue(plan.seams.isEmpty)
        XCTAssertEqual(plan.outputHeight(sourceHeights: [200]), 200)
    }

    func testProgressIsMonotonicAndEndsAtOne() throws {
        var options = SyntheticOptions()
        options.pageHeight = 2000
        let synthetic = SyntheticScreens.make(seed: 5, options: options)
        let lock = NSLock()
        var values: [Double] = []
        _ = try Stitcher.stitch(synthetic.shots) { value in
            lock.lock()
            values.append(value)
            lock.unlock()
        }
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last, 1)
        XCTAssertTrue(values.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(values, values.sorted(), "progress must never go backwards")
    }

    // MARK: - Building blocks

    func testRowSignatureBinsAndValues() {
        XCTAssertEqual(RowSignatures.binCount(forWidth: 390), 48)
        XCTAssertEqual(RowSignatures.binCount(forWidth: 1179), 98)
        XCTAssertEqual(RowSignatures.binCount(forWidth: 3000), 128)
        XCTAssertEqual(RowSignatures.binCount(forWidth: 100), 48)

        // Top half black, bottom half white: one change row, at the boundary.
        let image = SyntheticScreens.draw(width: 120, height: 40) { context in
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 40))
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 20))
        }
        let signatures = RowSignatures(image: image)
        XCTAssertEqual(signatures.rows, 40)
        XCTAssertEqual(signatures.bins, 48)
        XCTAssertEqual(signatures.values.count, 40 * 48)
        XCTAssertEqual(signatures.values[0], 0, accuracy: 0.5)
        XCTAssertEqual(signatures.values[39 * 48], 255, accuracy: 0.5)
        XCTAssertEqual(signatures.changeRows.enumerated().filter { $0.element }.map { $0.offset }, [20])
    }

    func testRowToleranceAndMedian() {
        let base: [Float] = [10, 10, 10, 10]
        let close: [Float] = [10.5, 9.5, 10.5, 9.5]     // mean 0.5, max 0.5
        let spike: [Float] = [10, 10, 10, 14]           // mean 1, max 4
        base.withUnsafeBufferPointer { a in
            close.withUnsafeBufferPointer { b in
                XCTAssertTrue(SignatureView.rowsMatch(a.baseAddress!, b.baseAddress!, bins: 4, tolerance: .strict))
            }
            spike.withUnsafeBufferPointer { b in
                XCTAssertFalse(SignatureView.rowsMatch(a.baseAddress!, b.baseAddress!, bins: 4, tolerance: .strict))
                XCTAssertTrue(SignatureView.rowsMatch(a.baseAddress!, b.baseAddress!, bins: 4, tolerance: .loose))
            }
        }

        var odd: [Float] = [5, 1, 4, 2, 3]
        var even: [Float] = [12, 12, 1, 3, 12, 2]
        let oddMedian = odd.withUnsafeMutableBufferPointer { SeamDetector.median($0.baseAddress!, count: $0.count) }
        let evenMedian = even.withUnsafeMutableBufferPointer { SeamDetector.median($0.baseAddress!, count: $0.count) }
        XCTAssertEqual(oddMedian, 3)
        XCTAssertEqual(evenMedian, 7.5)
    }

    // MARK: - Helpers

    /// Five screenshots (seed 21) shared by the duplicate and reversed-order tests.
    private func duplicateAndReverseCase() -> SyntheticCase {
        var options = SyntheticOptions()
        options.pageHeight = 3000
        options.maxShots = 5
        return SyntheticScreens.make(seed: 21, options: options)
    }

    private func assertExactReconstruction(_ synthetic: SyntheticCase, label: String,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let output = try Stitcher.stitch(synthetic.shots)
        let plan = output.plan
        let count = synthetic.shots.count
        XCTAssertGreaterThan(count, 2, label, file: file, line: line)
        XCTAssertEqual(plan.imageIndices, Array(0..<count), label, file: file, line: line)
        XCTAssertEqual(plan.seams.map(\.kind), [Seam.Kind](repeating: .matched, count: count - 1),
                       label, file: file, line: line)
        XCTAssertEqual(plan.seams.map(\.offset), synthetic.expectedSeamOffsets.map { Optional($0) },
                       label, file: file, line: line)
        XCTAssertFalse(plan.autoReversed, label, file: file, line: line)
        assertPixelsEqual(output.image, synthetic.groundTruth, label: label, file: file, line: line)
    }

    private func assertPixelsEqual(_ image: CGImage, _ expected: CGImage, label: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(image.width, expected.width, "\(label): width", file: file, line: line)
        XCTAssertEqual(image.height, expected.height, "\(label): height", file: file, line: line)
        guard image.width == expected.width, image.height == expected.height else { return }
        let actualPixels = pixels(of: image)
        let expectedPixels = pixels(of: expected)
        guard actualPixels != expectedPixels else { return }
        let rowBytes = image.width * 4
        var firstRow = -1
        for row in 0..<image.height {
            let range = row * rowBytes ..< (row + 1) * rowBytes
            if actualPixels[range] != expectedPixels[range] {
                firstRow = row
                break
            }
        }
        XCTFail("\(label): pixels differ from the ground truth (first differing row \(firstRow))",
                file: file, line: line)
    }

    /// RGBA8 sRGB pixels, top row first.
    private func pixels(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                XCTFail("Could not create a comparison context")
                return
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    /// Rows that are not entirely near-white (every RGB channel >= 250), top to bottom.
    private func nonWhiteRows(of image: CGImage) -> [[UInt8]] {
        let data = pixels(of: image)
        let rowBytes = image.width * 4
        var rows: [[UInt8]] = []
        for row in 0..<image.height {
            let start = row * rowBytes
            var isWhite = true
            var index = start
            while index < start + rowBytes {
                if data[index] < 250 || data[index + 1] < 250 || data[index + 2] < 250 {
                    isWhite = false
                    break
                }
                index += 4
            }
            if !isWhite {
                rows.append(Array(data[start ..< start + rowBytes]))
            }
        }
        return rows
    }

    private func solidImage(width: Int, height: Int, gray: Int) -> CGImage {
        SyntheticScreens.draw(width: width, height: height) { context in
            let value = CGFloat(gray) / 255
            context.setFillColor(red: value, green: value, blue: value, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
