import CoreGraphics
import Foundation

/// Per-row tolerance used to decide whether two signature rows show the same pixels.
/// Values are gray levels (0...255) averaged per column bin.
struct RowTolerance: Equatable, Sendable {
    /// Maximum mean absolute difference over all bins.
    let mean: Float
    /// Maximum absolute difference of any single bin.
    let max: Float

    /// Lossless (PNG) screenshots: equal content only differs by rounding.
    static let strict = RowTolerance(mean: 0.75, max: 3.0)
    /// Recompressed (JPEG/HEIC) screenshots.
    static let loose = RowTolerance(mean: 3.5, max: 14.0)
}

/// Compact fingerprint of every pixel row of an image: the mean gray level of `bins` equal column
/// ranges. Stored as one flat row-major array (`rows × bins`) so the matcher can walk it with raw
/// pointers.
struct RowSignatures: Sendable {
    let rows: Int
    let bins: Int
    /// Row-major signature values, `rows * bins` entries.
    let values: [Float]
    /// `changeRows[y]` is true when row `y` differs (strict tolerance) from row `y - 1`. Row 0 is
    /// never a change row. These are the structural "key rows" (edges, text) used for matching.
    let changeRows: [Bool]

    /// Number of column bins for an image `width` pixels wide.
    static func binCount(forWidth width: Int) -> Int {
        min(128, max(48, width / 12))
    }

    /// Builds signatures from raw values (used by tests).
    init(rows: Int, bins: Int, values: [Float]) {
        precondition(rows >= 0 && bins > 0 && values.count == rows * bins, "Invalid signature size")
        self.rows = rows
        self.bins = bins
        self.values = values
        self.changeRows = RowSignatures.computeChangeRows(values: values, rows: rows, bins: bins,
                                                          tolerance: .strict)
    }

    /// Draws `image` into an 8-bit DeviceGray bitmap of the same pixel size (white background) and
    /// averages each column bin of every row.
    init(image: CGImage) {
        let width = max(image.width, 1)
        let height = max(image.height, 1)
        let bins = RowSignatures.binCount(forWidth: width)
        var values = [Float](repeating: 0, count: height * bins)

        // Column ranges: [floor(i * width / bins), max(floor((i + 1) * width / bins), start + 1)).
        var starts = [Int](repeating: 0, count: bins)
        var ends = [Int](repeating: 0, count: bins)
        for i in 0..<bins {
            let start = i * width / bins
            starts[i] = start
            ends[i] = max((i + 1) * width / bins, start + 1)
        }

        if let context = CGContext(data: nil,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(rect)
            context.interpolationQuality = .none
            context.draw(image, in: rect)

            if let data = context.data {
                let stride = context.bytesPerRow
                let pixels = data.assumingMemoryBound(to: UInt8.self)
                values.withUnsafeMutableBufferPointer { out in
                    guard let outBase = out.baseAddress else { return }
                    var y = 0
                    while y < height {
                        // Bitmap memory starts with the top row of the image.
                        let row = pixels + y * stride
                        let target = outBase + y * bins
                        var i = 0
                        while i < bins {
                            let start = starts[i]
                            let end = ends[i]
                            var sum = 0
                            var x = start
                            while x < end {
                                sum += Int(row[x])
                                x += 1
                            }
                            target[i] = Float(sum) / Float(end - start)
                            i += 1
                        }
                        y += 1
                    }
                }
            }
        }

        self.rows = height
        self.bins = bins
        self.values = values
        self.changeRows = RowSignatures.computeChangeRows(values: values, rows: height, bins: bins,
                                                          tolerance: .strict)
    }

    /// Runs `body` with a borrowed pointer view of the values. The view must not escape `body`.
    func withView<R>(_ body: (SignatureView) throws -> R) rethrows -> R {
        try values.withUnsafeBufferPointer { buffer in
            try body(SignatureView(buffer: buffer, rows: rows, bins: bins))
        }
    }

    /// Change rows for an arbitrary tolerance (the strict ones are cached in `changeRows`).
    func changeRowsUsing(_ tolerance: RowTolerance) -> [Bool] {
        if tolerance == .strict { return changeRows }
        return RowSignatures.computeChangeRows(values: values, rows: rows, bins: bins, tolerance: tolerance)
    }

    private static func computeChangeRows(values: [Float], rows: Int, bins: Int,
                                          tolerance: RowTolerance) -> [Bool] {
        var result = [Bool](repeating: false, count: rows)
        guard rows > 1 else { return result }
        values.withUnsafeBufferPointer { buffer in
            let view = SignatureView(buffer: buffer, rows: rows, bins: bins)
            result.withUnsafeMutableBufferPointer { out in
                var y = 1
                while y < rows {
                    out[y] = !SignatureView.rowsMatch(view.row(y), view.row(y - 1), bins: bins,
                                                      tolerance: tolerance)
                    y += 1
                }
            }
        }
        return result
    }
}

/// Read-only pointer view of a `RowSignatures` value array. Only valid inside
/// `RowSignatures.withView`; never store it.
struct SignatureView {
    let buffer: UnsafeBufferPointer<Float>
    let rows: Int
    let bins: Int

    /// Pointer to the first bin of row `y`.
    @inline(__always)
    func row(_ y: Int) -> UnsafePointer<Float> {
        buffer.baseAddress! + y * bins
    }

    /// True when mean |a − b| <= tolerance.mean and max |a − b| <= tolerance.max.
    /// Exits as soon as one bin exceeds the max tolerance.
    @inline(__always)
    static func rowsMatch(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, bins: Int,
                          tolerance: RowTolerance) -> Bool {
        let maxTolerance = tolerance.max
        var sum: Float = 0
        var i = 0
        while i < bins {
            let diff = abs(a[i] - b[i])
            if diff > maxTolerance { return false }
            sum += diff
            i += 1
        }
        return sum / Float(bins) <= tolerance.mean
    }

    /// Mean |a − b| over all bins, saturating at `cap`: returns `cap` as soon as the result is known
    /// to exceed it (so the value is `min(true mean, cap)`).
    @inline(__always)
    static func cappedMeanDifference(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, bins: Int,
                                     cap: Float) -> Float {
        let limit = cap * Float(bins)
        var sum: Float = 0
        var i = 0
        while i < bins {
            sum += abs(a[i] - b[i])
            if sum > limit { return cap }
            i += 1
        }
        return sum / Float(bins)
    }

    /// Sum of |a − b| over all bins.
    @inline(__always)
    static func absoluteDifferenceSum(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, bins: Int) -> Double {
        var sum: Float = 0
        var i = 0
        while i < bins {
            sum += abs(a[i] - b[i])
            i += 1
        }
        return Double(sum)
    }

    /// Rows that are equal (same position) in `a` and `b`: fixed bars, unchanged areas.
    /// The result has `b.rows` entries; rows beyond `a.rows` are false.
    static func staticRows(_ a: SignatureView, _ b: SignatureView, tolerance: RowTolerance) -> [Bool] {
        var result = [Bool](repeating: false, count: b.rows)
        let n = min(a.rows, b.rows)
        let bins = b.bins
        result.withUnsafeMutableBufferPointer { out in
            var y = 0
            while y < n {
                out[y] = rowsMatch(a.row(y), b.row(y), bins: bins, tolerance: tolerance)
                y += 1
            }
        }
        return result
    }

    /// Uniform-colour rows starting at `start` and walking in `step` direction (+1 / −1), at most
    /// `limit` rows. A row is uniform when its bins span <= 6 gray levels; consecutive rows must stay
    /// within 3 levels of the first row's mean. Returns the count and the colour (mean gray).
    func flatRun(start: Int, step: Int, limit: Int) -> (count: Int, colour: Float) {
        var count = 0
        var colour: Float = 0
        var hasColour = false
        var y = start
        let flatSpread = RowTolerance.strict.max * 2
        while y >= 0 && y < rows && count < limit {
            let r = row(y)
            var lo = r[0]
            var hi = r[0]
            var sum: Float = 0
            var i = 0
            while i < bins {
                let v = r[i]
                if v < lo { lo = v }
                if v > hi { hi = v }
                sum += v
                i += 1
            }
            if hi - lo > flatSpread { break }
            let mean = sum / Float(bins)
            if !hasColour {
                colour = mean
                hasColour = true
            } else if abs(mean - colour) > RowTolerance.strict.max {
                break
            }
            count += 1
            y += step
        }
        return (count, colour)
    }
}
