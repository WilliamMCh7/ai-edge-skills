import Foundation

/// How two consecutive images are joined.
struct Seam: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The overlap was found: content is aligned pixel-exactly (or within JPEG noise).
        case matched
        /// No measurable overlap (blank or too small). Fixed bars are removed and shared blank
        /// space is merged, but the user should check this seam.
        case estimated
        /// The lower image seems to show content ABOVE the upper one (wrong order).
        case reversed
    }

    var kind: Kind
    /// Row `y` of the lower image shows the same content as row `y + offset` of the upper image.
    /// Only set for `.matched` seams.
    var offset: Int?
    /// Exclusive end row of the upper image's slice (upper-image coordinates).
    var upperEnd: Int
    /// First row of the lower image's slice (lower-image coordinates), before `adjustment`.
    var lowerStart: Int
    /// Rows of the lower image that matched the upper image (lower-image coordinates).
    var overlap: Range<Int>?
    /// Key rows supporting the match (0 when not matched). Higher is more certain.
    var support: Int
    /// Manual correction in rows added to `lowerStart`: positive skips more of the lower image
    /// (removes duplicated content), negative brings back rows that were cut.
    var adjustment: Int = 0

    var effectiveLowerStart: Int { lowerStart + adjustment }
}

/// The complete recipe for a stitched image. Pure value type: rendering is done by
/// `StitchRenderer`, so edits (seam adjustments, bar toggles) are cheap to re-apply.
struct StitchPlan: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        /// Index into the `sources` array the plan was made for.
        let sourceIndex: Int
        /// Rows of that source to copy, top to bottom.
        let rows: Range<Int>
    }

    /// Indices into the sources array that are used, top to bottom. Duplicates are left out and
    /// the order may be reversed (see `autoReversed`).
    var imageIndices: [Int]
    /// `seams[k]` joins `imageIndices[k]` (upper) and `imageIndices[k + 1]` (lower).
    var seams: [Seam]
    /// Height of the fixed top bars (status bar + navigation bar) of the first image.
    var headerHeight: Int
    /// Height of the fixed bottom bars (tab bar, home indicator) of the last image.
    var footerHeight: Int
    var includeHeader: Bool = true
    var includeFooter: Bool = true
    /// Source indices dropped because they were identical to the previous image.
    var droppedDuplicates: [Int] = []
    /// True when the input order was reversed because every seam looked reversed.
    var autoReversed: Bool = false
    /// Width in pixels shared by every source (sources are width-normalised before planning).
    var width: Int

    var needsReview: Bool { seams.contains { $0.kind != .matched } }
    var reviewCount: Int { seams.filter { $0.kind != .matched }.count }

    /// Vertical slices to stack top to bottom. `sourceHeights[i]` is the pixel height of source `i`.
    func segments(sourceHeights: [Int]) -> [Segment] {
        guard !imageIndices.isEmpty else { return [] }
        var starts = [Int](repeating: 0, count: imageIndices.count)
        var ends = imageIndices.map { sourceHeights[$0] }

        starts[0] = includeHeader ? 0 : headerHeight
        for (k, seam) in seams.enumerated() where k + 1 < imageIndices.count {
            ends[k] = seam.upperEnd
            starts[k + 1] = seam.effectiveLowerStart
        }
        let lastHeight = sourceHeights[imageIndices[imageIndices.count - 1]]
        ends[imageIndices.count - 1] = includeFooter ? lastHeight : lastHeight - footerHeight

        return imageIndices.indices.map { k in
            let height = sourceHeights[imageIndices[k]]
            let start = min(max(starts[k], 0), height)
            let end = min(max(ends[k], start), height)
            return Segment(sourceIndex: imageIndices[k], rows: start..<end)
        }
    }

    func outputHeight(sourceHeights: [Int]) -> Int {
        segments(sourceHeights: sourceHeights).reduce(0) { $0 + $1.rows.count }
    }

    /// Y positions (output pixels, before any downscaling) where each seam falls, in seam order.
    func seamPositions(sourceHeights: [Int]) -> [Int] {
        var y = 0
        var positions: [Int] = []
        let segments = segments(sourceHeights: sourceHeights)
        for segment in segments.dropLast() {
            y += segment.rows.count
            positions.append(y)
        }
        return positions
    }

    /// Valid range for `seams[index].adjustment` so the lower slice stays inside its image.
    func adjustmentRange(forSeam index: Int, sourceHeights: [Int]) -> ClosedRange<Int> {
        let seam = seams[index]
        let lowerHeight = sourceHeights[imageIndices[index + 1]]
        let lower = -seam.lowerStart
        let upper = max(lower, lowerHeight - 1 - seam.lowerStart)
        return lower...upper
    }
}
