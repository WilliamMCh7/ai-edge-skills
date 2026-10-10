import XCTest
@testable import LongScreenshot

/// Pure math of `StitchPlan`: segments, heights, seam positions, bar toggles and adjustments.
final class StitchPlanTests: XCTestCase {
    private let heights = [1000, 1000, 1000]

    // MARK: - Fixtures

    private func matchedSeam(offset: Int, lowerStart: Int) -> Seam {
        Seam(kind: .matched, offset: offset, upperEnd: lowerStart + offset, lowerStart: lowerStart,
             overlap: (lowerStart - 50)..<(lowerStart + 50), support: 20)
    }

    /// Image 0 rows 0..<700, image 1 rows 300..<800, image 2 rows 250..<1000.
    private func samplePlan() -> StitchPlan {
        StitchPlan(imageIndices: [0, 1, 2],
                   seams: [matchedSeam(offset: 400, lowerStart: 300), matchedSeam(offset: 550, lowerStart: 250)],
                   headerHeight: 100,
                   footerHeight: 80,
                   width: 390)
    }

    private func rows(_ plan: StitchPlan, _ sourceHeights: [Int]? = nil) -> [Range<Int>] {
        plan.segments(sourceHeights: sourceHeights ?? heights).map(\.rows)
    }

    // MARK: - Segments

    func testSegmentsFollowSeams() {
        let plan = samplePlan()
        let segments = plan.segments(sourceHeights: heights)
        XCTAssertEqual(segments.map(\.sourceIndex), [0, 1, 2])
        XCTAssertEqual(segments.map(\.rows), [0..<700, 300..<800, 250..<1000])
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 700 + 500 + 750)
        XCTAssertEqual(plan.seamPositions(sourceHeights: heights), [700, 1200])
        XCTAssertFalse(plan.needsReview)
        XCTAssertEqual(plan.reviewCount, 0)
    }

    func testHeaderAndFooterToggles() {
        var plan = samplePlan()
        plan.includeHeader = false
        XCTAssertEqual(rows(plan), [100..<700, 300..<800, 250..<1000])
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 1850)
        XCTAssertEqual(plan.seamPositions(sourceHeights: heights), [600, 1100])

        plan.includeHeader = true
        plan.includeFooter = false
        XCTAssertEqual(rows(plan), [0..<700, 300..<800, 250..<920])
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 1870)
        XCTAssertEqual(plan.seamPositions(sourceHeights: heights), [700, 1200])

        plan.includeHeader = false
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 1770)
    }

    func testAdjustmentMovesTheLowerSlice() {
        var plan = samplePlan()
        plan.seams[0].adjustment = 20
        XCTAssertEqual(plan.seams[0].effectiveLowerStart, 320)
        XCTAssertEqual(rows(plan), [0..<700, 320..<800, 250..<1000])
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 1930)
        XCTAssertEqual(plan.seamPositions(sourceHeights: heights), [700, 1180])

        plan.seams[0].adjustment = -100
        XCTAssertEqual(rows(plan)[1], 200..<800)
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 2050)
    }

    func testAdjustmentIsClampedToTheImage() {
        var plan = samplePlan()
        plan.seams[0].adjustment = 900          // start 1200 > height: empty slice at the end
        XCTAssertEqual(rows(plan)[1], 1000..<1000)
        XCTAssertEqual(plan.outputHeight(sourceHeights: heights), 700 + 0 + 750)

        plan.seams[0].adjustment = -500         // start −200: clamped to row 0
        XCTAssertEqual(rows(plan)[1], 0..<800)

        plan.seams[0].adjustment = 0
        plan.seams[1] = Seam(kind: .matched, offset: 10, upperEnd: 1200, lowerStart: 990, overlap: nil, support: 5)
        // upperEnd beyond the image is clamped to its height.
        XCTAssertEqual(rows(plan)[1], 300..<1000)
        XCTAssertEqual(rows(plan)[2], 990..<1000)
    }

    func testAdjustmentRange() {
        let plan = samplePlan()
        XCTAssertEqual(plan.adjustmentRange(forSeam: 0, sourceHeights: heights), -300...699)
        XCTAssertEqual(plan.adjustmentRange(forSeam: 1, sourceHeights: heights), -250...749)

        var outside = samplePlan()
        outside.seams[1].lowerStart = 1200
        // Whatever the seam says, the effective start stays inside the lower image (rows 0...999).
        XCTAssertEqual(outside.adjustmentRange(forSeam: 1, sourceHeights: heights), -1200...(-201))
    }

    // MARK: - Other shapes

    func testEstimatedSeamNeedsReview() {
        var plan = samplePlan()
        plan.seams[1] = Seam(kind: .estimated, offset: nil, upperEnd: 917, lowerStart: 91, overlap: nil, support: 0)
        XCTAssertTrue(plan.needsReview)
        XCTAssertEqual(plan.reviewCount, 1)
        XCTAssertEqual(rows(plan), [0..<700, 300..<917, 91..<1000])

        plan.seams[0].kind = .reversed
        XCTAssertEqual(plan.reviewCount, 2)
    }

    func testDroppedDuplicateIndicesAreSkipped() {
        let plan = StitchPlan(imageIndices: [0, 2],
                              seams: [matchedSeam(offset: 400, lowerStart: 300)],
                              headerHeight: 0,
                              footerHeight: 0,
                              droppedDuplicates: [1],
                              width: 390)
        let segments = plan.segments(sourceHeights: [1000, 1000, 800])
        XCTAssertEqual(segments.map(\.sourceIndex), [0, 2])
        XCTAssertEqual(segments.map(\.rows), [0..<700, 300..<800])
        XCTAssertEqual(plan.adjustmentRange(forSeam: 0, sourceHeights: [1000, 1000, 800]), -300...499)
    }

    func testSingleAndEmptyPlans() {
        let single = StitchPlan(imageIndices: [0], seams: [], headerHeight: 0, footerHeight: 0, width: 390)
        XCTAssertEqual(rows(single, [1000]), [0..<1000])
        XCTAssertEqual(single.outputHeight(sourceHeights: [1000]), 1000)
        XCTAssertEqual(single.seamPositions(sourceHeights: [1000]), [])
        XCTAssertFalse(single.needsReview)

        let empty = StitchPlan(imageIndices: [], seams: [], headerHeight: 0, footerHeight: 0, width: 0)
        XCTAssertTrue(empty.segments(sourceHeights: []).isEmpty)
        XCTAssertEqual(empty.outputHeight(sourceHeights: []), 0)
        XCTAssertEqual(empty.seamPositions(sourceHeights: []), [])
    }
}
