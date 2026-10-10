import CoreGraphics
import Foundation

/// Errors thrown while stitching screenshots.
enum StitchError: LocalizedError {
    case notEnoughImages
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .notEnoughImages:
            return "Elige al menos dos capturas para unirlas."
        case .renderFailed:
            return "No se pudo crear la imagen final. Prueba con menos capturas."
        }
    }
}

/// Joins overlapping screenshots (taken while scrolling) into one long image.
/// Planning (`makePlan`) finds every seam; rendering is done by `StitchRenderer`.
enum Stitcher {
    /// Result of `stitch`. `sources` are the width-normalised images the plan refers to.
    struct Output: @unchecked Sendable {
        let plan: StitchPlan
        let sources: [SourceImage]
        let image: CGImage
    }

    /// Share of the overall progress used by planning (signatures ≈ 30 %, seams ≈ 60 %); rendering
    /// takes the remaining ≈ 10 %.
    private static let planShare = 0.9
    /// Share of the planning progress used by the row signatures.
    private static let signatureShare = 1.0 / 3.0

    /// Normalises widths, plans and renders. `sources` must have >= 2 images. Runs synchronously:
    /// callers dispatch it off the main thread. `progress` is called with 0...1 (any thread).
    static func stitch(_ sources: [SourceImage], progress: ((Double) -> Void)? = nil) throws -> Output {
        guard sources.count >= 2 else { throw StitchError.notEnoughImages }
        progress?(0)
        let normalized = normalizeWidths(sources)
        let plan = makePlan(for: normalized, progress: { value in
            progress?(value * Stitcher.planShare)
        })
        let image = try StitchRenderer.render(plan: plan, sources: normalized)
        progress?(1)
        return Output(plan: plan, sources: normalized, image: image)
    }

    /// Scales every image whose width differs from the first one to that width (aspect kept).
    /// Rescaled images are resampled, so they are marked lossy (tolerant matching).
    static func normalizeWidths(_ sources: [SourceImage]) -> [SourceImage] {
        guard let width = sources.first?.width, width > 0 else { return sources }
        return sources.map { (source: SourceImage) -> SourceImage in
            guard source.width != width, source.width > 0 else { return source }
            let scaledHeight = Double(source.height) * Double(width) / Double(source.width)
            let height = max(1, Int(scaledHeight.rounded()))
            guard let scaled = scaledImage(source.cgImage, width: width, height: height) else { return source }
            return SourceImage(id: source.id, cgImage: scaled, isLossy: true)
        }
    }

    /// Plans equal-width sources (no rendering).
    static func makePlan(for sources: [SourceImage], progress: ((Double) -> Void)? = nil) -> StitchPlan {
        let reporter = StitchProgressReporter(progress)
        guard let first = sources.first else {
            reporter.report(1)
            return StitchPlan(imageIndices: [], seams: [], headerHeight: 0, footerHeight: 0, width: 0)
        }
        let width = first.width
        let count = sources.count

        reporter.beginPhase(from: 0, to: signatureShare, steps: count)
        let signatures = computeSignatures(sources, reporter: reporter)

        let forward = planPass(order: Array(0..<count), sources: sources, signatures: signatures,
                               width: width, reporter: reporter)
        // Every seam says the next image sits ABOVE the previous one: try the reversed order once.
        if !forward.seams.isEmpty && forward.seams.allSatisfy({ $0.kind == .reversed }) {
            var backward = planPass(order: Array((0..<count).reversed()), sources: sources,
                                    signatures: signatures, width: width, reporter: nil)
            if backward.seams.contains(where: { $0.kind == .matched }) {
                backward.autoReversed = true
                reporter.report(1)
                return backward
            }
        }
        reporter.report(1)
        return forward
    }

    // MARK: - Planning

    /// Row signatures of every source, computed concurrently.
    private static func computeSignatures(_ sources: [SourceImage], reporter: StitchProgressReporter) -> [RowSignatures] {
        var results = [RowSignatures?](repeating: nil, count: sources.count)
        results.withUnsafeMutableBufferPointer { buffer in
            let output = buffer
            DispatchQueue.concurrentPerform(iterations: output.count) { index in
                output[index] = RowSignatures(image: sources[index].cgImage)
                reporter.completeStep()
            }
        }
        return (0..<sources.count).map { (index: Int) -> RowSignatures in
            results[index] ?? RowSignatures(image: sources[index].cgImage)
        }
    }

    /// Plans the sources in `order`: drops duplicates of the previous kept image, then detects the
    /// seam of every consecutive pair (concurrently).
    private static func planPass(order: [Int], sources: [SourceImage], signatures: [RowSignatures],
                                 width: Int, reporter: StitchProgressReporter?) -> StitchPlan {
        var keep: [Int] = []
        var dropped: [Int] = []
        for index in order {
            if let previous = keep.last, SeamDetector.isDuplicate(signatures[previous], signatures[index]) {
                dropped.append(index)
            } else {
                keep.append(index)
            }
        }

        let kept = keep
        let pairCount = max(kept.count - 1, 0)
        reporter?.beginPhase(from: signatureShare, to: 1, steps: pairCount)
        var detections = [SeamDetection?](repeating: nil, count: pairCount)
        if pairCount > 0 {
            detections.withUnsafeMutableBufferPointer { buffer in
                let output = buffer
                DispatchQueue.concurrentPerform(iterations: pairCount) { k in
                    let upper = kept[k]
                    let lower = kept[k + 1]
                    output[k] = SeamDetector.detectSeam(upper: signatures[upper],
                                                        lower: signatures[lower],
                                                        lossy: sources[upper].isLossy || sources[lower].isLossy)
                    reporter?.completeStep()
                }
            }
        }

        var seams: [Seam] = []
        var header = 0
        var footer = 0
        for (k, detection) in detections.enumerated() {
            let resolved = detection ?? SeamDetector.detectSeam(
                upper: signatures[kept[k]], lower: signatures[kept[k + 1]],
                lossy: sources[kept[k]].isLossy || sources[kept[k + 1]].isLossy)
            if k == 0 { header = resolved.header }
            footer = resolved.footer
            seams.append(resolved.seam)
        }

        return StitchPlan(imageIndices: kept,
                          seams: seams,
                          headerHeight: header,
                          footerHeight: footer,
                          droppedDuplicates: dropped,
                          width: width)
    }

    /// Resamples `image` to `width × height` pixels (high-quality interpolation).
    private static func scaledImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = StitchRenderer.makeBitmapContext(width: width, height: height, matching: image) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

/// Thread-safe, monotonic progress reporting split into sequential phases.
private final class StitchProgressReporter {
    private let callback: ((Double) -> Void)?
    private let lock = NSLock()
    private var lastReported = -1.0
    private var phaseStart = 0.0
    private var phaseEnd = 0.0
    private var phaseSteps = 1
    private var completedSteps = 0

    init(_ callback: ((Double) -> Void)?) {
        self.callback = callback
    }

    /// Starts a phase mapping `steps` completed steps onto `start...end`.
    func beginPhase(from start: Double, to end: Double, steps: Int) {
        lock.lock()
        phaseStart = start
        phaseEnd = end
        phaseSteps = max(steps, 1)
        completedSteps = 0
        lock.unlock()
        report(start)
    }

    /// Marks one step of the current phase as done (callable from any thread).
    func completeStep() {
        lock.lock()
        completedSteps += 1
        let fraction = Double(min(completedSteps, phaseSteps)) / Double(phaseSteps)
        let value = phaseStart + (phaseEnd - phaseStart) * fraction
        lock.unlock()
        report(value)
    }

    /// Forwards `value` (clamped to 0...1) when it is greater than the last reported value.
    func report(_ value: Double) {
        guard let callback = callback else { return }
        lock.lock()
        defer { lock.unlock() }
        let clamped = min(max(value, 0), 1)
        guard clamped > lastReported else { return }
        lastReported = clamped
        callback(clamped)
    }
}
