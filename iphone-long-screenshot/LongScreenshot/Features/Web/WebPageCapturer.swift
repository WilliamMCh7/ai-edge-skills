import CoreGraphics
import Foundation
import WebKit

/// Errors of the whole-page web capture.
enum WebCaptureError: LocalizedError {
    case emptyPage
    case pdfFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .emptyPage:
            return "La página está vacía. Espera a que termine de cargar e inténtalo de nuevo."
        case .pdfFailed:
            return "No se pudo generar el PDF de la página. Inténtalo de nuevo."
        case .renderFailed:
            return "No se pudo crear la imagen de la página. Puede que sea demasiado larga."
        }
    }
}

/// Captures a complete web page (not only the visible part) as one tall image plus its vector PDF.
///
/// WebKit renders the entire document into a PDF, so nothing is stitched and fixed headers are not
/// repeated. The PDF pages are then rasterised top to bottom into a single sRGB bitmap.
@MainActor
enum WebPageCapturer {
    struct Output {
        let image: CGImage
        let pdfData: Data
        let title: String?
    }

    /// Stages of a capture, reported so the UI can say what is happening.
    enum Step {
        case loadingContent
        case creatingPDF
        case renderingImage
    }

    /// Scrolls through the page to trigger lazy loading (callAsyncJavaScript, capped ~4 s), scrolls back to
    /// top, creates a whole-page PDF (`webView.pdf(configuration: WKPDFConfiguration())`, rect nil = entire
    /// content) and rasterises every PDF page stacked vertically at `scale`, reduced if the result would
    /// exceed `maxPixels`. White background.
    static func capture(_ webView: WKWebView, scale: CGFloat, maxPixels: Int = 60_000_000) async throws -> Output {
        try await capture(webView, scale: scale, maxPixels: maxPixels, onStep: { _ in })
    }

    /// Same as `capture(_:scale:maxPixels:)`, calling `onStep` (on the main actor) as each stage starts.
    static func capture(_ webView: WKWebView,
                        scale: CGFloat,
                        maxPixels: Int = 60_000_000,
                        onStep: (Step) -> Void) async throws -> Output {
        onStep(.loadingContent)
        await loadLazyContent(in: webView)

        onStep(.creatingPDF)
        let pdfData: Data
        do {
            pdfData = try await webView.pdf(configuration: WKPDFConfiguration())
        } catch {
            throw WebCaptureError.pdfFailed
        }
        guard !pdfData.isEmpty else { throw WebCaptureError.pdfFailed }

        onStep(.renderingImage)
        let title = webView.title
        let image = try await Task.detached(priority: .userInitiated) {
            try WebPageCapturer.rasterize(pdfData: pdfData, scale: scale, maxPixels: maxPixels)
        }.value
        return Output(image: image, pdfData: pdfData, title: title)
    }

    // MARK: - Lazy loading

    /// Scrolls down one viewport at a time (short pauses so lazy images and infinite lists load),
    /// then back to the top so fixed headers sit where they belong. Script errors are ignored: a
    /// page that blocks scripting is still captured as it is.
    private static func loadLazyContent(in webView: WKWebView) async {
        _ = try? await webView.callAsyncJavaScript(lazyLoadScript,
                                                   arguments: [:],
                                                   in: nil,
                                                   contentWorld: .page)
        // Give layout a moment to settle after jumping back to the top.
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    /// Body of an async JavaScript function (callAsyncJavaScript wraps it, so `await` is allowed).
    /// At most 50 viewport-sized steps with 80 ms pauses, and never longer than ~4 s.
    private static let lazyLoadScript = """
    const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
    const viewport = Math.max(window.innerHeight || 0, 300);
    const started = Date.now();
    let y = 0;
    let steps = 0;
    while (steps < 50 && Date.now() - started < 4000) {
        const root = document.scrollingElement || document.documentElement;
        const rootHeight = root ? root.scrollHeight : 0;
        const bodyHeight = document.body ? document.body.scrollHeight : 0;
        const height = Math.max(rootHeight, bodyHeight);
        if (y + viewport >= height) {
            break;
        }
        y += viewport;
        window.scrollTo(0, y);
        steps += 1;
        await pause(80);
    }
    window.scrollTo(0, 0);
    await pause(80);
    return steps;
    """

    // MARK: - Rasterising

    /// Draws every page of `pdfData` stacked vertically (page 1 on top) into one RGBA8 sRGB image on
    /// white. `scale` is pixels per PDF point; it is reduced uniformly so the image has at most
    /// `maxPixels` pixels. Pure CoreGraphics: safe to call off the main thread.
    nonisolated static func rasterize(pdfData: Data, scale: CGFloat, maxPixels: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider) else {
            throw WebCaptureError.pdfFailed
        }

        var slices: [WebPDFPageSlice] = []
        let pageCount = document.numberOfPages
        if pageCount > 0 {
            for index in 1...pageCount {
                guard let page = document.page(at: index) else { continue }
                let box = page.getBoxRect(.mediaBox).standardized
                if box.width >= 1 && box.height >= 1 {
                    slices.append(WebPDFPageSlice(page: page, box: box))
                }
            }
        }
        guard !slices.isEmpty else { throw WebCaptureError.emptyPage }

        // Total size in points: widest page × sum of page heights.
        var widthPoints: CGFloat = 0
        var heightPoints: CGFloat = 0
        for slice in slices {
            widthPoints = max(widthPoints, slice.box.width)
            heightPoints += slice.box.height
        }

        // Pixels per point, reduced so width × height stays within the pixel budget.
        let budget = max(maxPixels, 1)
        let area = Double(widthPoints) * Double(heightPoints)
        var effectiveScale = (scale.isFinite && scale > 0) ? Double(scale) : 1
        if area * effectiveScale * effectiveScale > Double(budget) {
            effectiveScale = (Double(budget) / area).squareRoot()
        }
        var pixelWidth = Int((Double(widthPoints) * effectiveScale).rounded())
        var pixelHeight = Int((Double(heightPoints) * effectiveScale).rounded())
        if pixelWidth * pixelHeight > budget {
            pixelWidth = Int((Double(widthPoints) * effectiveScale).rounded(.down))
            pixelHeight = Int((Double(heightPoints) * effectiveScale).rounded(.down))
        }
        pixelWidth = max(pixelWidth, 1)
        pixelHeight = max(pixelHeight, 1)
        while pixelWidth * pixelHeight > budget && pixelHeight > 1 {
            pixelHeight -= 1
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: pixelWidth,
                                      height: pixelHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw WebCaptureError.renderFailed
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high

        // From here on the context works in PDF points.
        context.scaleBy(x: CGFloat(pixelWidth) / widthPoints, y: CGFloat(pixelHeight) / heightPoints)

        var top: CGFloat = 0
        for slice in slices {
            let box = slice.box
            context.saveGState()
            // CoreGraphics' origin is bottom-left, so page 1 goes at the highest y. Narrower pages
            // are centred horizontally.
            context.translateBy(x: (widthPoints - box.width) / 2, y: heightPoints - top - box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.clip(to: box)
            context.drawPDFPage(slice.page)
            context.restoreGState()
            top += box.height
        }

        guard let image = context.makeImage() else { throw WebCaptureError.renderFailed }
        return image
    }
}

/// One PDF page and its media box (PDF points).
private struct WebPDFPageSlice {
    let page: CGPDFPage
    let box: CGRect
}
