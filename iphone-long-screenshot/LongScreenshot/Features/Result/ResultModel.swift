import CoreGraphics
import Foundation
import Observation

/// One finished long screenshot, shown by `ResultView`. Holds the plan and sources of a stitched
/// result so seam edits and bar toggles can be re-rendered.
@Observable
@MainActor
final class ResultModel: Identifiable, Hashable {
    enum Kind {
        case stitched
        case webPage(title: String?, pdfData: Data)
    }

    struct SeamMarker: Identifiable, Equatable {
        /// Seam index in `plan.seams`.
        let id: Int
        /// Row in the rendered `image` where the seam falls.
        let y: Int
        let kind: Seam.Kind
    }

    let id = UUID()
    let kind: Kind
    let sources: [SourceImage]
    private(set) var image: CGImage
    private(set) var plan: StitchPlan?
    private(set) var isRendering = false

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    /// The plan that produced the current `image`; restored when re-rendering an edit fails.
    @ObservationIgnored private var renderedPlan: StitchPlan? = nil
    @ObservationIgnored private var cachedPNG: (image: CGImage, url: URL)?
    /// Bumped every time `image` is replaced, so each version is written to its own file.
    @ObservationIgnored private var imageVersion = 0
    @ObservationIgnored private let createdAt = Date()

    init(stitched image: CGImage, plan: StitchPlan, sources: [SourceImage]) {
        self.kind = .stitched
        self.image = image
        self.plan = plan
        self.renderedPlan = plan
        self.sources = sources
    }

    init(webPage image: CGImage, title: String?, pdfData: Data) {
        self.kind = .webPage(title: title, pdfData: pdfData)
        self.image = image
        self.plan = nil
        self.sources = []
    }

    var title: String {
        switch kind {
        case .stitched: return "Captura larga"
        case .webPage(let title, _): return title?.isEmpty == false ? title! : "Página web"
        }
    }

    var isWebPage: Bool {
        if case .webPage = kind { return true }
        return false
    }

    var sourceHeights: [Int] { sources.map(\.height) }

    /// Seam positions in rendered-image rows (the renderer may downscale very tall results).
    var seamMarkers: [SeamMarker] {
        guard let plan else { return [] }
        let fullHeight = plan.outputHeight(sourceHeights: sourceHeights)
        guard fullHeight > 0 else { return [] }
        let scale = Double(image.height) / Double(fullHeight)
        return plan.seamPositions(sourceHeights: sourceHeights).enumerated().map { index, y in
            SeamMarker(id: index, y: Int((Double(y) * scale).rounded()), kind: plan.seams[index].kind)
        }
    }

    /// Applies an edited plan (seam adjustments, header/footer toggles) and re-renders off the
    /// main thread. Rapid successive edits cancel the previous render.
    func apply(_ newPlan: StitchPlan) {
        guard case .stitched = kind, newPlan != plan else { return }
        plan = newPlan
        renderTask?.cancel()
        isRendering = true
        let sources = self.sources
        renderTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                try? StitchRenderer.render(plan: newPlan, sources: sources)
            }.value
            guard let self, !Task.isCancelled else { return }
            if let rendered {
                self.image = rendered
                self.renderedPlan = newPlan
                self.imageVersion += 1
                self.cachedPNG = nil
            } else {
                // Keep `plan` describing the pixels on screen (markers, toggles, seam editor) and
                // allow retrying the same edit.
                self.plan = self.renderedPlan
            }
            self.isRendering = false
        }
    }

    /// PNG of the current image written to a temporary file (cached until the image changes).
    /// Every image version gets its own file name: the detached encode is not cancelled with the
    /// caller, so an older encode that finishes late must not overwrite the newer file.
    func pngFileURL() async throws -> URL {
        if let cachedPNG, cachedPNG.image === image { return cachedPNG.url }
        try Task.checkCancellation()
        let image = self.image
        let version = imageVersion
        let name = version == 0 ? "\(fileBaseName).png" : "\(fileBaseName) (\(version + 1)).png"
        let url = try await Task.detached(priority: .userInitiated) {
            let data = try ImageExporter.pngData(from: image)
            return try ImageExporter.writeTemporaryFile(data, fileName: name)
        }.value
        // Never cache the file of an image that was replaced while it was being encoded.
        if image === self.image {
            cachedPNG = (image, url)
        }
        return url
    }

    /// The vector PDF of a captured web page, written to a temporary file.
    func pdfFileURL() throws -> URL? {
        guard case .webPage(_, let pdfData) = kind else { return nil }
        return try ImageExporter.writeTemporaryFile(pdfData, fileName: fileBaseName + ".pdf")
    }

    /// Saves the current image as a PNG to the photo library (asks for add-only permission).
    func saveToPhotos() async throws {
        let image = self.image
        let data = try await Task.detached(priority: .userInitiated) {
            try ImageExporter.pngData(from: image)
        }.value
        try await PhotoLibrarySaver.savePNG(data)
    }

    /// Unique per result (date + short id), so two results created in the same second never
    /// share a temporary file.
    private var fileBaseName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Captura larga \(formatter.string(from: createdAt)) \(id.uuidString.prefix(4))"
    }

    nonisolated static func == (lhs: ResultModel, rhs: ResultModel) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
