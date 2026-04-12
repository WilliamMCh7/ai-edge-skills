import UIKit
import CoreGraphics

/// Stitches multiple overlapping screenshots into a single long image.
///
/// Algorithm:
/// 1. Normalize all images to the same width
/// 2. For each consecutive pair, detect the vertical overlap by comparing
///    horizontal strips from the bottom of image A with the top of image B
/// 3. Combine all images, removing duplicate overlap regions
final class ImageStitcherService: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: String = ""
    @Published var resultImage: UIImage?
    @Published var errorMessage: String?

    /// Stitch an array of images (in order, top to bottom) into one long image.
    @MainActor
    func stitchImages(_ images: [UIImage]) async {
        guard images.count >= 2 else {
            errorMessage = "Se necesitan al menos 2 imagenes"
            return
        }

        isProcessing = true
        errorMessage = nil
        resultImage = nil
        progress = "Preparando imagenes..."

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try self.performStitch(images)
            }.value
            resultImage = result
            progress = "Union completada"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    private func performStitch(_ images: [UIImage]) throws -> UIImage {
        // Normalize all images to the same width (use the first image's width)
        let targetWidth = images[0].size.width
        let normalized = images.map { img -> UIImage in
            if abs(img.size.width - targetWidth) < 1 {
                return img
            }
            let scale = targetWidth / img.size.width
            let newHeight = img.size.height * scale
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: newHeight))
            return renderer.image { _ in
                img.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: newHeight))
            }
        }

        // Stitch pairs
        var result = normalized[0]
        for i in 1..<normalized.count {
            let overlap = findOverlap(bottom: result, top: normalized[i])
            result = combine(bottom: result, top: normalized[i], overlap: overlap)
        }

        return result
    }

    /// Find the number of pixels of vertical overlap between the bottom of imageA
    /// and the top of imageB using row-by-row pixel comparison.
    private func findOverlap(bottom: UIImage, top: UIImage) -> Int {
        guard let cgBottom = bottom.cgImage, let cgTop = top.cgImage else {
            return 0
        }

        let width = cgBottom.width
        let bottomHeight = cgBottom.height
        let topHeight = cgTop.height

        // We'll compare strips. Max overlap to search is 60% of the smaller image height.
        let maxOverlap = min(bottomHeight, topHeight) * 60 / 100
        let minOverlap = 20 // Minimum overlap in pixels

        guard maxOverlap > minOverlap else { return 0 }

        // Get pixel data for comparison regions
        let stripHeight = maxOverlap
        let bottomStrip = getPixelData(
            from: cgBottom,
            rect: CGRect(x: 0, y: CGFloat(bottomHeight - stripHeight), width: CGFloat(width), height: CGFloat(stripHeight))
        )
        let topStrip = getPixelData(
            from: cgTop,
            rect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(stripHeight))
        )

        guard let bottomPixels = bottomStrip, let topPixels = topStrip else { return 0 }

        let bytesPerRow = width * 4
        var bestOverlap = 0
        var bestScore = Double.infinity

        // Sample every 2 pixels for speed, compare rows
        let step = 2
        for overlap in stride(from: minOverlap, to: stripHeight, by: step) {
            var totalDiff: UInt64 = 0
            var sampleCount: UInt64 = 0

            // Compare the last `overlap` rows of bottom with first `overlap` rows of top
            let bottomStart = (stripHeight - overlap) * bytesPerRow
            let topStart = 0

            // Sample rows evenly
            let rowStep = max(1, overlap / 40)
            for row in stride(from: 0, to: overlap, by: rowStep) {
                let bRowStart = bottomStart + row * bytesPerRow
                let tRowStart = topStart + row * bytesPerRow

                // Sample pixels across the row
                let colStep = max(1, width / 80)
                for col in stride(from: 0, to: width, by: colStep) {
                    let bIdx = bRowStart + col * 4
                    let tIdx = tRowStart + col * 4

                    guard bIdx + 2 < bottomPixels.count, tIdx + 2 < topPixels.count else { continue }

                    let dr = Int(bottomPixels[bIdx]) - Int(topPixels[tIdx])
                    let dg = Int(bottomPixels[bIdx + 1]) - Int(topPixels[tIdx + 1])
                    let db = Int(bottomPixels[bIdx + 2]) - Int(topPixels[tIdx + 2])

                    totalDiff += UInt64(dr * dr + dg * dg + db * db)
                    sampleCount += 1
                }
            }

            guard sampleCount > 0 else { continue }
            let score = Double(totalDiff) / Double(sampleCount)

            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        // Only accept if the match is good enough (low MSE)
        // Threshold: average per-channel difference < 15 (out of 255)
        let threshold: Double = 15.0 * 15.0 * 3.0
        if bestScore > threshold {
            return 0 // No good overlap found; just stack them
        }

        return bestOverlap
    }

    /// Extract RGBA pixel data from a region of a CGImage.
    private func getPixelData(from image: CGImage, rect: CGRect) -> [UInt8]? {
        let x = Int(rect.origin.x)
        let y = Int(rect.origin.y)
        let w = Int(rect.width)
        let h = Int(rect.height)

        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    /// Combine two images vertically, removing the overlap region from the top image.
    private func combine(bottom: UIImage, top: UIImage, overlap: Int) -> UIImage {
        let totalHeight = bottom.size.height + top.size.height - CGFloat(overlap)
        let width = bottom.size.width

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: totalHeight))
        return renderer.image { _ in
            bottom.draw(at: .zero)

            let topY = bottom.size.height - CGFloat(overlap)
            top.draw(at: CGPoint(x: 0, y: topY))
        }
    }
}
