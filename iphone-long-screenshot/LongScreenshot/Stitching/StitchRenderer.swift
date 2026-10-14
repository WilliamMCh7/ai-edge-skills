import CoreGraphics
import Foundation

/// Draws a `StitchPlan` into a single bitmap. Pure function of the plan and its sources, so seam
/// edits and bar toggles are re-rendered without re-planning.
enum StitchRenderer {
    /// Max pixels of a rendered result; taller results are uniformly downscaled to fit.
    static let maxOutputPixels: Int = 60_000_000

    /// Renders every segment of the plan top to bottom on a white background.
    static func render(plan: StitchPlan, sources: [SourceImage]) throws -> CGImage {
        guard !plan.imageIndices.isEmpty,
              plan.imageIndices.allSatisfy({ $0 >= 0 && $0 < sources.count }) else {
            throw StitchError.renderFailed
        }
        let segments = plan.segments(sourceHeights: sources.map(\.height))
        let totalHeight = segments.reduce(0) { $0 + $1.rows.count }
        let width = plan.width > 0 ? plan.width : sources[plan.imageIndices[0]].width
        guard width > 0, totalHeight > 0 else { throw StitchError.renderFailed }

        let size = outputSize(width: width, height: totalHeight, maxPixels: maxOutputPixels)
        guard let context = makeBitmapContext(width: size.width, height: size.height,
                                              matching: sources[plan.imageIndices[0]].cgImage) else {
            throw StitchError.renderFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        // Segment edges are rounded to whole output rows so downscaled slices never leave gaps.
        let scaleY = Double(size.height) / Double(totalHeight)
        var top = 0
        for segment in segments {
            let rowCount = segment.rows.count
            guard rowCount > 0 else { continue }
            let image = sources[segment.sourceIndex].cgImage
            let crop = CGRect(x: 0, y: segment.rows.lowerBound, width: image.width, height: rowCount)
            guard let slice = image.cropping(to: crop) else { throw StitchError.renderFailed }

            let outputTop = Int((Double(top) * scaleY).rounded())
            let outputBottom = Int((Double(top + rowCount) * scaleY).rounded())
            top += rowCount
            guard outputBottom > outputTop else { continue }
            // CoreGraphics' origin is bottom-left.
            let rect = CGRect(x: 0, y: size.height - outputBottom,
                              width: size.width, height: outputBottom - outputTop)
            context.draw(slice, in: rect)
        }

        guard let result = context.makeImage() else { throw StitchError.renderFailed }
        return result
    }

    /// Close-up of one seam: `context` rows of the upper slice above the seam and `context` rows of the
    /// lower slice below it (honours `adjustment`), full width. nil if the seam index is invalid.
    /// The image is always `2 × context` rows tall with the seam exactly at row `context` (from the
    /// top). Only rows of the two slices are drawn (never rows the stitched image leaves out, such
    /// as an excluded bar); when a slice is shorter than `context` the rest stays white.
    static func renderSeamPreview(plan: StitchPlan, seamIndex: Int, sources: [SourceImage], context: Int) -> CGImage? {
        guard context > 0,
              seamIndex >= 0, seamIndex < plan.seams.count,
              seamIndex + 1 < plan.imageIndices.count,
              plan.imageIndices.allSatisfy({ $0 >= 0 && $0 < sources.count }) else {
            return nil
        }
        let segments = plan.segments(sourceHeights: sources.map(\.height))
        let upperSegment = segments[seamIndex]
        let lowerSegment = segments[seamIndex + 1]
        let upper = sources[upperSegment.sourceIndex].cgImage
        let lower = sources[lowerSegment.sourceIndex].cgImage

        let upperEnd = upperSegment.rows.upperBound
        let upperStart = max(upperSegment.rows.lowerBound, upperEnd - context)
        let lowerStart = lowerSegment.rows.lowerBound
        let lowerEnd = min(lowerSegment.rows.upperBound, lowerStart + context)
        let width = plan.width > 0 ? plan.width : upper.width
        let height = 2 * context
        guard width > 0,
              let bitmap = makeBitmapContext(width: width, height: height, matching: upper) else {
            return nil
        }
        bitmap.interpolationQuality = .high
        bitmap.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Upper rows end at row `context` from the top: in bottom-left coordinates they start at y = context.
        if upperEnd > upperStart,
           let slice = upper.cropping(to: CGRect(x: 0, y: upperStart, width: upper.width, height: upperEnd - upperStart)) {
            bitmap.draw(slice, in: CGRect(x: 0, y: context, width: width, height: upperEnd - upperStart))
        }
        // Lower rows start at row `context` from the top.
        if lowerEnd > lowerStart,
           let slice = lower.cropping(to: CGRect(x: 0, y: lowerStart, width: lower.width, height: lowerEnd - lowerStart)) {
            let rowCount = lowerEnd - lowerStart
            bitmap.draw(slice, in: CGRect(x: 0, y: context - rowCount, width: width, height: rowCount))
        }
        return bitmap.makeImage()
    }

    // MARK: - Helpers

    /// Pixel size of a rendered `width × height` result: unchanged when it fits in `maxPixels`,
    /// otherwise both sides scaled by `sqrt(maxPixels / (width · height))` (rounded down, >= 1;
    /// for extreme aspect ratios the height is also capped so the product never exceeds `maxPixels`).
    static func outputSize(width: Int, height: Int, maxPixels: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxPixels > 0 else { return (width, height) }
        let pixels = Double(width) * Double(height)
        guard pixels > Double(maxPixels) else { return (width, height) }
        let scale = (Double(maxPixels) / pixels).squareRoot()
        let scaledWidth = max(1, Int(Double(width) * scale))
        let scaledHeight = max(1, min(Int(Double(height) * scale), maxPixels / scaledWidth))
        return (scaledWidth, scaledHeight)
    }

    /// RGBA8 premultiplied-last bitmap. Uses the colour space of `image` when it is an RGB space
    /// usable for output (keeps Display P3 screenshots untouched), sRGB otherwise.
    static func makeBitmapContext(width: Int, height: Int, matching image: CGImage?) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        if let space = image?.colorSpace, space.model == .rgb, space.supportsOutput,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) {
            return context
        }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                         bytesPerRow: 0, space: sRGB, bitmapInfo: bitmapInfo)
    }
}
