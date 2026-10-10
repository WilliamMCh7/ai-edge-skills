import Foundation

/// Best overlap found for a pair of consecutive screenshots: row `y` of the lower image shows the
/// same content as row `y + offset` of the upper image for the lower-image rows
/// `runStart..<runEnd`, supported by `inliers` matching key rows.
struct PairMatch: Equatable, Sendable {
    let offset: Int
    let runStart: Int
    let runEnd: Int
    let inliers: Int
}

/// A seam plus the fixed-bar heights measured for that pair (used for the plan's header/footer).
struct SeamDetection: Equatable, Sendable {
    let seam: Seam
    /// Fixed top rows: first overlap row when matched, static header otherwise.
    let header: Int
    /// Fixed bottom rows of the upper image: rows below the overlap when matched, static footer
    /// otherwise.
    let footer: Int
}

/// Finds how two consecutive screenshots overlap. Port of `reference/stitch.py` (same constants and
/// decisions): strict inlier matching for lossless sources, a cost-based matcher for lossy ones,
/// static-bar and blank-space fallbacks when nothing can be measured.
enum SeamDetector {
    /// Key rows of the lower image sampled for the coarse offset search.
    static let sampleRows = 400
    /// Offsets re-scored with the full overlap-run analysis.
    static let topCandidates = 24
    /// Key-row inliers needed inside the overlap run.
    static let minInliers = 5
    /// Mismatching rows tolerated inside an overlap run.
    static let runGap = 6
    /// ± rows searched around the winning offset.
    static let refine = 6
    /// Fraction of key rows equal at the same position to call two images duplicates.
    static let duplicateRatio = 0.97
    /// Lossy matcher: the winning median cost must be at most this.
    static let looseMaxCost: Float = 3.0
    /// Lossy matcher: winner cost must be < margin × best rival cost (rivals: |d − d1| > 8).
    static let looseMargin: Float = 0.6
    static let looseRivalDistance = 8
    /// Lossy matcher: key rows needed to evaluate an offset.
    static let looseMinSupport = 12
    /// Per-row cost saturation for the lossy matcher (speed only). Only medians up to
    /// looseMaxCost / looseMargin (= 5) can change a decision; any median involving a saturated row
    /// is >= cap / 2 = 6, so every decision is identical to the unsaturated computation.
    static let looseCostCap: Float = 12
    /// Static bars: searched within this fraction of the height from the top and from the bottom.
    static let staticBarFraction = 0.4
    /// Static bars: running fraction of equal rows required.
    static let staticBarRatio = 0.75

    // MARK: - Seam

    /// Builds the seam joining `upper` (A) and `lower` (B).
    static func detectSeam(upper a: RowSignatures, lower b: RowSignatures, lossy: Bool) -> SeamDetection {
        guard a.bins == b.bins else {
            // Different widths: nothing can be compared (callers normalise widths first).
            let seam = Seam(kind: .estimated, offset: nil, upperEnd: a.rows, lowerStart: 0,
                            overlap: nil, support: 0)
            return SeamDetection(seam: seam, header: 0, footer: 0)
        }

        let best = match(upper: a, lower: b, lossy: lossy)
        if let found = best, found.offset > 0 {
            let d = found.offset
            let lowerStart = (found.runStart + found.runEnd) / 2
            let seam = Seam(kind: .matched,
                            offset: d,
                            upperEnd: lowerStart + d,
                            lowerStart: lowerStart,
                            overlap: found.runStart..<found.runEnd,
                            support: found.inliers)
            return SeamDetection(seam: seam, header: found.runStart, footer: a.rows - (found.runEnd + d))
        }

        // Not measurable: drop the fixed bars and merge blank space shared by both images.
        let bars = staticBars(upper: a, lower: b)
        let endA = a.rows - bars.bottom
        var startB = bars.top
        let tail = a.withView { (view: SignatureView) -> (count: Int, colour: Float) in
            view.flatRun(start: endA - 1, step: -1, limit: endA - bars.top)
        }
        let head = b.withView { (view: SignatureView) -> (count: Int, colour: Float) in
            view.flatRun(start: startB, step: 1, limit: b.rows - bars.bottom - startB)
        }
        if tail.count > 0 && head.count > 0 && abs(tail.colour - head.colour) <= RowTolerance.strict.max {
            startB += min(tail.count, head.count)
        }

        var kind = Seam.Kind.estimated
        if let found = best, found.offset < 0 {
            kind = .reversed
        }
        let seam = Seam(kind: kind, offset: nil, upperEnd: endA, lowerStart: startB, overlap: nil, support: 0)
        return SeamDetection(seam: seam, header: bars.top, footer: bars.bottom)
    }

    // MARK: - Pair matching

    /// Best offset for the pair, or nil. Lossless sources use strict inlier matching, lossy ones
    /// (when either image is lossy) the cost-based matcher. The offset may be negative (B above A).
    static func match(upper a: RowSignatures, lower b: RowSignatures, lossy: Bool) -> PairMatch? {
        guard a.bins == b.bins, a.rows > 0, b.rows > 0 else { return nil }
        let changeB = b.changeRows
        return a.withView { (av: SignatureView) -> PairMatch? in
            b.withView { (bv: SignatureView) -> PairMatch? in
                if lossy {
                    return matchLossy(av, bv, changeB: changeB)
                }
                return matchStrict(av, bv, changeB: changeB)
            }
        }
    }

    private static func matchStrict(_ a: SignatureView, _ b: SignatureView, changeB: [Bool]) -> PairMatch? {
        let tolerance = RowTolerance.strict
        let stat = SignatureView.staticRows(a, b, tolerance: tolerance)
        let staticA = staticRowsOfUpper(stat, upperRows: a.rows)
        let keys = keyRows(changeB, excluding: stat)

        var best: PairMatch?
        for d in coarseOffsets(a, b, keys: keys, staticA: staticA, tolerance: tolerance) {
            guard let run = overlapRun(a, b, keys: keys, offset: d, tolerance: tolerance),
                  run.inliers >= minInliers else { continue }
            if let current = best {
                if run.inliers > current.inliers
                    || (run.inliers == current.inliers && abs(d) < abs(current.offset)) {
                    best = run
                }
            } else {
                best = run
            }
        }
        guard let found = best else { return nil }

        // Refinement: the offset with the lowest mean difference over the run, within ±refine.
        let d = found.offset
        var bestOffset = d - refine
        var bestCost = refinementCost(a, b, run: found, offset: d - refine)
        var bestDistance = refine
        var candidate = d - refine + 1
        while candidate <= d + refine {
            let cost = refinementCost(a, b, run: found, offset: candidate)
            let distance = abs(candidate - d)
            if cost < bestCost || (cost == bestCost && distance < bestDistance) {
                bestOffset = candidate
                bestCost = cost
                bestDistance = distance
            }
            candidate += 1
        }
        if bestOffset != d,
           let run = overlapRun(a, b, keys: keys, offset: bestOffset, tolerance: tolerance),
           run.inliers >= minInliers {
            return run
        }
        return found
    }

    private static func matchLossy(_ a: SignatureView, _ b: SignatureView, changeB: [Bool]) -> PairMatch? {
        // Static rows with the loose tolerance, structural rows detected strictly.
        let stat = SignatureView.staticRows(a, b, tolerance: .loose)
        let staticA = staticRowsOfUpper(stat, upperRows: a.rows)
        let keys = keyRows(changeB, excluding: stat)
        let sampled = sampledKeyRows(keys)
        guard !sampled.isEmpty else { return nil }

        let heightA = a.rows
        let bins = b.bins
        let cap = looseCostCap
        let minSupport = looseMinSupport
        var offsets: [Int] = []
        var costs: [Float] = []
        var scratch = [Float](repeating: 0, count: sampled.count)

        sampled.withUnsafeBufferPointer { ys in
            staticA.withUnsafeBufferPointer { staticRows in
                scratch.withUnsafeMutableBufferPointer { buffer in
                    guard let rowCosts = buffer.baseAddress else { return }
                    var d = -(heightA - 1)
                    while d <= heightA - 1 {
                        if d != 0 {
                            var n = 0
                            for y in ys {
                                let ya = y + d
                                if ya < 0 || ya >= heightA || staticRows[ya] { continue }
                                rowCosts[n] = SignatureView.cappedMeanDifference(a.row(ya), b.row(y),
                                                                                 bins: bins, cap: cap)
                                n += 1
                            }
                            if n >= minSupport {
                                offsets.append(d)
                                costs.append(SeamDetector.median(rowCosts, count: n))
                            }
                        }
                        d += 1
                    }
                }
            }
        }
        guard !offsets.isEmpty else { return nil }

        // Winner: lowest cost, then smallest |d|, first in ascending order.
        var bestIndex = 0
        for i in 1..<offsets.count {
            if costs[i] < costs[bestIndex]
                || (costs[i] == costs[bestIndex] && abs(offsets[i]) < abs(offsets[bestIndex])) {
                bestIndex = i
            }
        }
        let d1 = offsets[bestIndex]
        let c1 = costs[bestIndex]
        var c2 = Float.infinity
        for i in 0..<offsets.count where abs(offsets[i] - d1) > looseRivalDistance {
            c2 = min(c2, costs[i])
        }
        if c1 > looseMaxCost || c1 >= looseMargin * c2 { return nil }

        guard let run = overlapRun(a, b, keys: keys, offset: d1, tolerance: .loose),
              run.inliers >= minInliers else { return nil }
        return run
    }

    /// Ranks offsets by inliers − 2·outliers over sampled key rows of B, ignoring rows that land on
    /// static rows of A. Returns the `topCandidates` best offsets.
    private static func coarseOffsets(_ a: SignatureView, _ b: SignatureView, keys: [Bool], staticA: [Bool],
                                      tolerance: RowTolerance) -> [Int] {
        let sampled = sampledKeyRows(keys)
        guard !sampled.isEmpty else { return [] }

        struct Candidate {
            let score: Int
            let inliers: Int
            let offset: Int
        }

        let heightA = a.rows
        let bins = b.bins
        var candidates: [Candidate] = []
        sampled.withUnsafeBufferPointer { ys in
            staticA.withUnsafeBufferPointer { staticRows in
                var d = -(heightA - 1)
                while d <= heightA - 1 {
                    if d != 0 {
                        var total = 0
                        var inliers = 0
                        for y in ys {
                            let ya = y + d
                            if ya < 0 || ya >= heightA || staticRows[ya] { continue }
                            total += 1
                            if SignatureView.rowsMatch(a.row(ya), b.row(y), bins: bins, tolerance: tolerance) {
                                inliers += 1
                            }
                        }
                        if total > 0 && inliers > 0 {
                            candidates.append(Candidate(score: inliers - 2 * (total - inliers),
                                                        inliers: inliers, offset: d))
                        }
                    }
                    d += 1
                }
            }
        }

        // Descending by (score, inliers, −|d|, d).
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.inliers != rhs.inliers { return lhs.inliers > rhs.inliers }
            let lhsDistance = abs(lhs.offset)
            let rhsDistance = abs(rhs.offset)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.offset > rhs.offset
        }
        return candidates.prefix(topCandidates).map { $0.offset }
    }

    /// Best gap-tolerant run of B rows `y` with A[y + d] ≈ B[y], scored by (key-row inliers, length).
    static func overlapRun(_ a: SignatureView, _ b: SignatureView, keys: [Bool], offset d: Int,
                           tolerance: RowTolerance) -> PairMatch? {
        let yLo = max(0, -d)
        let yHi = min(b.rows, a.rows - d)
        guard yHi > yLo else { return nil }

        let bins = b.bins
        let maxGap = runGap
        var best: PairMatch?
        var start = -1
        var lastOK = -1
        var gap = 0
        var runInliers = 0
        keys.withUnsafeBufferPointer { isKey in
            var y = yLo
            while y < yHi {
                if SignatureView.rowsMatch(a.row(y + d), b.row(y), bins: bins, tolerance: tolerance) {
                    if start < 0 {
                        start = y
                        runInliers = 0
                    }
                    lastOK = y
                    gap = 0
                    if isKey[y] { runInliers += 1 }
                } else if start >= 0 {
                    gap += 1
                    if gap > maxGap {
                        let run = PairMatch(offset: d, runStart: start, runEnd: lastOK + 1, inliers: runInliers)
                        best = SeamDetector.better(best, run)
                        start = -1
                        gap = 0
                    }
                }
                y += 1
            }
        }
        if start >= 0 {
            best = better(best, PairMatch(offset: d, runStart: start, runEnd: lastOK + 1, inliers: runInliers))
        }
        return best
    }

    /// The candidate replaces the current run only when (inliers, length) is strictly greater.
    private static func better(_ current: PairMatch?, _ candidate: PairMatch) -> PairMatch {
        guard let current = current else { return candidate }
        if candidate.inliers != current.inliers {
            return candidate.inliers > current.inliers ? candidate : current
        }
        let candidateLength = candidate.runEnd - candidate.runStart
        let currentLength = current.runEnd - current.runStart
        return candidateLength > currentLength ? candidate : current
    }

    /// Mean |A[y + offset] − B[y]| over the run rows that stay inside A; infinite when less than half
    /// of the run remains.
    private static func refinementCost(_ a: SignatureView, _ b: SignatureView, run: PairMatch, offset dd: Int) -> Double {
        let y0 = run.runStart
        let y1 = run.runEnd
        let lo = max(y0, -dd)
        let hi = min(y1, a.rows - dd)
        if hi <= lo || hi - lo < (y1 - y0) / 2 { return .infinity }
        let bins = b.bins
        var sum = 0.0
        var y = lo
        while y < hi {
            sum += SignatureView.absoluteDifferenceSum(a.row(y + dd), b.row(y), bins: bins)
            y += 1
        }
        return sum / Double((hi - lo) * bins)
    }

    // MARK: - Duplicates and fixed bars

    /// True when both images show the same content at the same position (>= 97 % of B's key rows
    /// equal, tried with the strict and then the loose tolerance). Different heights never match.
    static func isDuplicate(_ a: RowSignatures, _ b: RowSignatures) -> Bool {
        guard a.rows == b.rows, a.bins == b.bins else { return false }
        let tolerances: [RowTolerance] = [.strict, .loose]
        return a.withView { (av: SignatureView) -> Bool in
            b.withView { (bv: SignatureView) -> Bool in
                for tolerance in tolerances {
                    let keys = b.changeRowsUsing(tolerance)
                    var keyCount = 0
                    var equal = 0
                    for y in 0..<bv.rows where keys[y] {
                        keyCount += 1
                        if SignatureView.rowsMatch(av.row(y), bv.row(y), bins: bv.bins, tolerance: tolerance) {
                            equal += 1
                        }
                    }
                    if keyCount == 0 || Double(equal) / Double(keyCount) >= SeamDetector.duplicateRatio {
                        return true
                    }
                }
                return false
            }
        }
    }

    /// Heights of the fixed top and bottom bars: the longest prefix (from the top, and from the
    /// bottom) within the first 40 % where at least 75 % of the rows so far are equal in both images.
    static func staticBars(upper a: RowSignatures, lower b: RowSignatures) -> (top: Int, bottom: Int) {
        let limit = Int(Double(min(a.rows, b.rows)) * staticBarFraction)
        guard limit > 0, a.bins == b.bins else { return (0, 0) }
        let ratio = staticBarRatio
        return a.withView { (av: SignatureView) -> (top: Int, bottom: Int) in
            b.withView { (bv: SignatureView) -> (top: Int, bottom: Int) in
                let bins = bv.bins
                let tolerance = RowTolerance.strict
                var top = 0
                var equal = 0
                for i in 0..<limit where SignatureView.rowsMatch(av.row(i), bv.row(i), bins: bins,
                                                                 tolerance: tolerance) {
                    equal += 1
                    if Double(equal) / Double(i + 1) >= ratio { top = i + 1 }
                }
                var bottom = 0
                equal = 0
                for i in 0..<limit where SignatureView.rowsMatch(av.row(av.rows - 1 - i), bv.row(bv.rows - 1 - i),
                                                                 bins: bins, tolerance: tolerance) {
                    equal += 1
                    if Double(equal) / Double(i + 1) >= ratio { bottom = i + 1 }
                }
                return (top, bottom)
            }
        }
    }

    // MARK: - Helpers

    /// Static rows indexed by upper-image row (rows beyond the lower image's height are not static).
    private static func staticRowsOfUpper(_ stat: [Bool], upperRows: Int) -> [Bool] {
        var result = [Bool](repeating: false, count: upperRows)
        let n = min(upperRows, stat.count)
        for y in 0..<n where stat[y] {
            result[y] = true
        }
        return result
    }

    /// Key rows of B: change rows that are not static.
    private static func keyRows(_ changeRows: [Bool], excluding stat: [Bool]) -> [Bool] {
        var result = [Bool](repeating: false, count: changeRows.count)
        for y in 0..<changeRows.count where changeRows[y] && !(y < stat.count && stat[y]) {
            result[y] = true
        }
        return result
    }

    /// Indices of key rows, evenly subsampled to `sampleRows` like `numpy.linspace(...).astype(int)`.
    static func sampledKeyRows(_ keys: [Bool]) -> [Int] {
        var rows: [Int] = []
        for y in 0..<keys.count where keys[y] {
            rows.append(y)
        }
        guard rows.count > sampleRows else { return rows }
        let step = Double(rows.count - 1) / Double(sampleRows - 1)
        var sampled: [Int] = []
        sampled.reserveCapacity(sampleRows)
        for i in 0..<(sampleRows - 1) {
            sampled.append(rows[Int(Double(i) * step)])
        }
        sampled.append(rows[rows.count - 1])
        return sampled
    }

    /// Median of `values[0..<count]` (mean of the two middle values for an even count).
    /// Reorders the buffer. `count` must be > 0.
    static func median(_ values: UnsafeMutablePointer<Float>, count: Int) -> Float {
        let k = count / 2
        let upper = select(values, count: count, k: k)
        if count % 2 == 1 { return upper }
        // After selection every element left of k is <= values[k]: the lower middle is their max.
        var lowerMiddle = values[0]
        var i = 1
        while i < k {
            if values[i] > lowerMiddle { lowerMiddle = values[i] }
            i += 1
        }
        return (lowerMiddle + upper) / 2
    }

    /// Wirth's selection: places the k-th smallest element at index k with smaller-or-equal elements
    /// before it and greater-or-equal ones after it, and returns it.
    static func select(_ values: UnsafeMutablePointer<Float>, count: Int, k: Int) -> Float {
        var lo = 0
        var hi = count - 1
        while lo < hi {
            let pivot = values[k]
            var i = lo
            var j = hi
            repeat {
                while values[i] < pivot { i += 1 }
                while pivot < values[j] { j -= 1 }
                if i <= j {
                    let swap = values[i]
                    values[i] = values[j]
                    values[j] = swap
                    i += 1
                    j -= 1
                }
            } while i <= j
            if j < k { lo = i }
            if k < i { hi = j }
        }
        return values[k]
    }
}
