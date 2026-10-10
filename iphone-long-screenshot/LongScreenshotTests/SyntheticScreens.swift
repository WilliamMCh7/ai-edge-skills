import CoreGraphics
import UIKit
@testable import LongScreenshot

/// Deterministic pseudo-random numbers (SplitMix64), identical on every run and device.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in `lower..<upper` (like numpy's `integers(lower, upper)`).
    mutating func int(_ lower: Int, _ upper: Int) -> Int {
        precondition(upper > lower, "Empty range")
        return lower + Int(next() % UInt64(upper - lower))
    }

    /// Uniform double in `lower..<upper`.
    mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * (Double(next() >> 11) * 0x1p-53)
    }
}

/// Parameters of a synthetic scrolling session (defaults: iPhone at 1x, 390 × 844).
struct SyntheticOptions {
    var width = 390
    var height = 844
    var headerHeight = 91
    var footerHeight = 83
    var pageHeight = 4000
    var maxShots: Int?
    /// Fraction of the viewport shared by consecutive screenshots.
    var overlap: ClosedRange<Double> = 0.1...0.8
    /// Only list rows (avatar + text bars), like a chat or contacts list.
    var repetitive = false
    var blankBlocks = true
    /// The status-bar clock changes between screenshots.
    var clockChange = true
    var floatingButton = false
    /// JPEG round-trip (quality 0.8) of every screenshot; the sources are marked lossy.
    var jpeg = false
    /// Overlaps whose page rows contain fewer structural rows than this get up to three extra
    /// text lines, so every seam is measurable. 0 disables it.
    var minOverlapKeyRows = 24
}

/// Screenshots of a synthetic page plus the ground truth.
struct SyntheticCase {
    let shots: [SourceImage]
    /// Page row shown at the top of each screenshot's viewport.
    let offsets: [Int]
    let page: CGImage
    /// Header of the first screenshot + page rows `offsets.first ..< offsets.last + viewport` +
    /// footer of the last screenshot: what a perfect stitch produces.
    let groundTruth: CGImage
    let options: SyntheticOptions

    /// True seam offsets (`offsets[k + 1] − offsets[k]`).
    var expectedSeamOffsets: [Int] {
        (0..<max(offsets.count - 1, 0)).map { offsets[$0 + 1] - offsets[$0] }
    }
}

/// Swift port of `reference/synth.py`: draws an app-like page (real text, cards with identical
/// interiors, noise "photos", separators, blank space, repetitive list rows) with CoreGraphics and
/// cuts it into screenshots with a fixed status/navigation bar and tab bar.
enum SyntheticScreens {
    private enum Block {
        case text, card, image, separator, blank, listRow
    }

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    // MARK: - Public

    static func make(seed: UInt64, options: SyntheticOptions = SyntheticOptions()) -> SyntheticCase {
        var rng = SplitMix64(seed: seed)
        let width = options.width
        let pageHeight = options.pageHeight
        let scale = Double(width) / 390
        let kinds: [Block]
        if options.repetitive {
            kinds = [.listRow]
        } else if options.blankBlocks {
            kinds = [.text, .text, .text, .card, .image, .separator, .blank]
        } else {
            kinds = [.text, .text, .card, .image, .separator]
        }

        var page = draw(width: width, height: pageHeight) { context in
            fill(context, x: 0, y: 0, width: width, height: pageHeight, gray: 255)
            _ = drawBlocks(context, rng: &rng, kinds: kinds, from: 10, to: pageHeight - 40,
                           width: width, pageHeight: pageHeight, scale: scale)
        }

        let viewport = options.height - options.headerHeight - options.footerHeight
        var offsets = [0]
        while offsets[offsets.count - 1] + viewport < pageHeight - viewport
                && (options.maxShots == nil || offsets.count < options.maxShots!) {
            let overlap = rng.uniform(options.overlap.lowerBound, options.overlap.upperBound)
            offsets.append(offsets[offsets.count - 1] + max(1, Int(Double(viewport) * (1 - overlap))))
        }

        if options.minOverlapKeyRows > 0 {
            page = reinforceOverlaps(page: page, offsets: offsets, viewport: viewport,
                                     minKeyRows: options.minOverlapKeyRows, scale: scale, rng: &rng)
        }
        return makeCase(page: page, offsets: offsets, options: options)
    }

    /// Page with content, a 600-row blank gap (rows 1000..<1600) and more content. Screenshots 1
    /// and 2 overlap only inside the blank gap; the other overlaps contain content.
    static func makeBlankOverlapCase(seed: UInt64) -> SyntheticCase {
        var rng = SplitMix64(seed: seed)
        var options = SyntheticOptions()
        options.pageHeight = 2400
        options.minOverlapKeyRows = 0
        let width = options.width
        let pageHeight = options.pageHeight
        let kinds: [Block] = [.text, .text, .card, .image, .separator]

        let page = draw(width: width, height: pageHeight) { context in
            fill(context, x: 0, y: 0, width: width, height: pageHeight, gray: 255)
            _ = drawBlocks(context, rng: &rng, kinds: kinds, from: 10, to: 1000,
                           width: width, pageHeight: pageHeight, scale: 1)
            fill(context, x: 0, y: 1000, width: width, height: 600, gray: 255)
            _ = drawBlocks(context, rng: &rng, kinds: kinds, from: 1600, to: pageHeight - 40,
                           width: width, pageHeight: pageHeight, scale: 1)
        }
        return makeCase(page: page, offsets: [300, 700, 1200, 1500], options: options)
    }

    // MARK: - Page

    /// Draws random blocks from `startY` while y < `endY`; returns the final y.
    private static func drawBlocks(_ context: CGContext, rng: inout SplitMix64, kinds: [Block], from startY: Int,
                                   to endY: Int, width: Int, pageHeight: Int, scale: Double) -> Int {
        var y = startY
        while y < endY {
            let kind = kinds.count == 1 ? kinds[0] : kinds[rng.int(0, kinds.count)]
            switch kind {
            case .text:
                let lines = rng.int(1, 6)
                for _ in 0..<lines {
                    if y + 24 >= pageHeight { break }
                    let words = randomWords(&rng)
                    let gray = rng.int(20, 90)
                    drawText(context, words, x: 16, y: y, gray: gray, fontSize: Int(15 * scale),
                             clipHeight: Int(20 * scale), width: width)
                    y += Int(22 * scale)
                }
                y += 10
            case .card:
                let height = rng.int(60, 180)
                fill(context, x: 12, y: y, width: width - 24, height: height, gray: 242)
                fill(context, x: 24, y: y + 10, width: rng.int(60, width - 60), height: 12, gray: 40)
                fill(context, x: 24, y: y + 30, width: rng.int(40, width - 60), height: 10, gray: 120)
                y += height + 12
            case .image:
                let height = min(rng.int(80, 220), pageHeight - y - 2)
                let columns = (width - 24) / 8 + 1
                let rows = height / 8 + 1
                context.saveGState()
                context.clip(to: CGRect(x: 12, y: y, width: width - 24, height: height))
                for cellY in 0..<rows {
                    for cellX in 0..<columns {
                        let red = rng.int(0, 255)
                        let green = rng.int(0, 255)
                        let blue = rng.int(0, 255)
                        fill(context, x: 12 + cellX * 8, y: y + cellY * 8, width: 8, height: 8,
                             red: red, green: green, blue: blue)
                    }
                }
                context.restoreGState()
                y += height + 12
            case .separator:
                fill(context, x: 16, y: y, width: width - 16, height: 1, gray: 200)
                y += 12
            case .blank:
                y += rng.int(100, 320)
            case .listRow:
                fill(context, x: 16, y: y + 15, width: 40, height: 40, red: 0, green: 120, blue: 255)
                fill(context, x: 72, y: y + 69, width: width - 72, height: 1, gray: 210)
                fill(context, x: 72, y: y + 18, width: rng.int(60, width - 100), height: 12, gray: 30)
                fill(context, x: 72, y: y + 38, width: rng.int(40, width - 120), height: 10, gray: 140)
                y += 70
            }
        }
        return y
    }

    /// Adds up to three text lines at the top of every overlap whose page rows have fewer than
    /// `minKeyRows` change rows (measured with the stitcher's own row signatures).
    private static func reinforceOverlaps(page: CGImage, offsets: [Int], viewport: Int, minKeyRows: Int,
                                          scale: Double, rng: inout SplitMix64) -> CGImage {
        let changeRows = RowSignatures(image: page).changeRows
        var additions: [(text: String, y: Int, gray: Int)] = []
        for k in 0..<max(offsets.count - 1, 0) {
            let lower = offsets[k + 1]
            let upper = min(offsets[k] + viewport, changeRows.count)
            guard upper > lower else { continue }
            let keyRows = changeRows[lower..<upper].filter { $0 }.count
            if keyRows >= minKeyRows { continue }
            let lineHeight = Int(22 * scale)
            var y = lower + 4
            var lines = 0
            while lines < 3 && y + lineHeight <= upper - 2 {
                let words = randomWords(&rng)
                let gray = rng.int(20, 90)
                additions.append((text: words, y: y, gray: gray))
                y += lineHeight
                lines += 1
            }
        }
        guard !additions.isEmpty else { return page }
        let width = page.width
        return draw(width: width, height: page.height) { context in
            drawImage(page, in: CGRect(x: 0, y: 0, width: width, height: page.height))
            for addition in additions {
                drawText(context, addition.text, x: 16, y: addition.y, gray: addition.gray,
                         fontSize: Int(15 * scale), clipHeight: Int(20 * scale), width: width)
            }
        }
    }

    // MARK: - Screenshots

    private static func makeCase(page: CGImage, offsets: [Int], options: SyntheticOptions) -> SyntheticCase {
        let width = options.width
        let height = options.height
        let header = options.headerHeight
        let footer = options.footerHeight
        let viewport = height - header - footer
        let scale = Double(width) / 390

        var images: [CGImage] = []
        for (k, offset) in offsets.enumerated() {
            let shot = draw(width: width, height: height) { context in
                fill(context, x: 0, y: 0, width: width, height: height, gray: 255)
                if let content = page.cropping(to: CGRect(x: 0, y: offset, width: width, height: viewport)) {
                    drawImage(content, in: CGRect(x: 0, y: header, width: width, height: viewport))
                }
                // Status bar + navigation bar.
                fill(context, x: 0, y: 0, width: width, height: header, gray: 248)
                fill(context, x: 0, y: header - 1, width: width, height: 1, gray: 200)
                let minute = 41 + (options.clockChange ? k : 0)
                let minuteText = minute % 60 < 10 ? "0\(minute % 60)" : "\(minute % 60)"
                let clock = "\(9 + minute / 60):\(minuteText)"
                let statusTop = max(4, header / 4)
                drawText(context, clock, x: Int(20 * scale), y: statusTop - 2, gray: 10,
                         fontSize: max(8, header / 6), clipHeight: max(3, header / 7) + 6, width: width,
                         weight: .semibold)
                fill(context, x: width - 50, y: statusTop, width: 30, height: max(3, header / 7), gray: 10)
                fill(context, x: width / 2 - 40, y: header / 2 + 2, width: 80, height: max(3, header / 6), gray: 0)
                // Tab bar + home indicator.
                fill(context, x: 0, y: height - footer, width: width, height: footer, gray: 248)
                fill(context, x: 0, y: height - footer, width: width, height: 1, gray: 200)
                for i in 0..<4 {
                    let centerX = Int(Double(width) * (Double(i) + 0.5) / 4)
                    fill(context, x: centerX - 10, y: height - footer + 8, width: 20, height: footer / 3,
                         gray: i == 0 ? 0 : 100)
                }
                fill(context, x: width / 2 - 60, y: height - 8, width: 120, height: 3, gray: 0)
                if options.floatingButton {
                    fill(context, x: width - 72, y: height - footer - 70, width: 56, height: 56,
                         red: 255, green: 60, blue: 60)
                }
            }
            images.append(options.jpeg ? jpegRoundTrip(shot) : shot)
        }

        let first = offsets[0]
        let body = offsets[offsets.count - 1] + viewport - first
        let firstShot = images[0]
        let lastShot = images[images.count - 1]
        let truth = draw(width: width, height: header + body + footer) { _ in
            if let top = firstShot.cropping(to: CGRect(x: 0, y: 0, width: width, height: header)) {
                drawImage(top, in: CGRect(x: 0, y: 0, width: width, height: header))
            }
            if let middle = page.cropping(to: CGRect(x: 0, y: first, width: width, height: body)) {
                drawImage(middle, in: CGRect(x: 0, y: header, width: width, height: body))
            }
            if let bottom = lastShot.cropping(to: CGRect(x: 0, y: height - footer, width: width, height: footer)) {
                drawImage(bottom, in: CGRect(x: 0, y: header + body, width: width, height: footer))
            }
        }

        let shots = images.map { SourceImage(cgImage: $0, isLossy: options.jpeg) }
        return SyntheticCase(shots: shots, offsets: offsets, page: page, groundTruth: truth, options: options)
    }

    // MARK: - Drawing helpers (UIKit coordinates: origin top-left, 1 point = 1 pixel)

    /// Opaque sRGB bitmap of `width × height` pixels drawn by `body`.
    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { rendererContext in
            body(rendererContext.cgContext)
        }
        guard let cgImage = image.cgImage else {
            fatalError("UIGraphicsImageRenderer returned no CGImage")
        }
        return cgImage
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect) {
        UIImage(cgImage: image, scale: 1, orientation: .up).draw(in: rect)
    }

    private static func fill(_ context: CGContext, x: Int, y: Int, width: Int, height: Int, gray: Int) {
        fill(context, x: x, y: y, width: width, height: height, red: gray, green: gray, blue: gray)
    }

    private static func fill(_ context: CGContext, x: Int, y: Int, width: Int, height: Int,
                             red: Int, green: Int, blue: Int) {
        guard width > 0, height > 0 else { return }
        context.setFillColor(UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                                     blue: CGFloat(blue) / 255, alpha: 1).cgColor)
        context.fill(CGRect(x: x, y: y, width: width, height: height))
    }

    private static func drawText(_ context: CGContext, _ text: String, x: Int, y: Int, gray: Int, fontSize: Int,
                                 clipHeight: Int, width: Int, weight: UIFont.Weight = .regular) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(fontSize), weight: weight),
            .foregroundColor: UIColor(red: CGFloat(gray) / 255, green: CGFloat(gray) / 255,
                                      blue: CGFloat(gray) / 255, alpha: 1)
        ]
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: y, width: width, height: clipHeight))
        NSAttributedString(string: text, attributes: attributes).draw(at: CGPoint(x: x, y: y))
        context.restoreGState()
    }

    private static func randomWords(_ rng: inout SplitMix64) -> String {
        let count = rng.int(2, 9)
        var words: [String] = []
        for _ in 0..<count {
            let length = rng.int(2, 9)
            var word = ""
            for _ in 0..<length {
                word.append(alphabet[rng.int(0, alphabet.count)])
            }
            words.append(word)
        }
        return words.joined(separator: " ")
    }

    private static func jpegRoundTrip(_ image: CGImage) -> CGImage {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8),
              let decoded = UIImage(data: data)?.cgImage else {
            fatalError("JPEG round trip failed")
        }
        return decoded
    }
}
