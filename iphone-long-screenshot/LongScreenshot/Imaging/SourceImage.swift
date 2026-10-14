import CoreGraphics
import Foundation

/// A decoded image ready to be stitched: upright pixels plus what we know about its encoding.
struct SourceImage: Identifiable, @unchecked Sendable {
    let id: UUID
    let cgImage: CGImage
    /// True when the file used lossy compression (JPEG, HEIC). Lossless PNG screenshots match
    /// pixel-exactly; lossy ones need the tolerant matcher.
    let isLossy: Bool

    init(id: UUID = UUID(), cgImage: CGImage, isLossy: Bool) {
        self.id = id
        self.cgImage = cgImage
        self.isLossy = isLossy
    }

    var width: Int { cgImage.width }
    var height: Int { cgImage.height }
}
