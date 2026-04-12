import UIKit
import WebKit

/// Captures a full-page screenshot of a web page by resizing the WKWebView
/// to the full content size and taking a single snapshot.
final class WebCaptureService: NSObject, ObservableObject {
    @Published var isLoading = false
    @Published var isCapturing = false
    @Published var progress: String = ""
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?

    private var webView: WKWebView?

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    @MainActor
    func captureFullPage() async {
        guard let webView = webView else {
            errorMessage = "WebView no disponible"
            return
        }

        isCapturing = true
        progress = "Calculando tamaño de la página..."
        errorMessage = nil
        capturedImage = nil

        do {
            let image = try await performCapture(webView: webView)
            capturedImage = image
            progress = "Captura completada"
        } catch {
            errorMessage = "Error al capturar: \(error.localizedDescription)"
        }

        isCapturing = false
    }

    @MainActor
    private func performCapture(webView: WKWebView) async throws -> UIImage {
        // Get the full content size via JavaScript
        let widthJS = "Math.max(document.body.scrollWidth, document.documentElement.scrollWidth)"
        let heightJS = "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"

        let widthResult = try await webView.evaluateJavaScript(widthJS)
        let heightResult = try await webView.evaluateJavaScript(heightJS)

        guard let contentWidth = (widthResult as? NSNumber)?.doubleValue,
              let contentHeight = (heightResult as? NSNumber)?.doubleValue else {
            throw CaptureError.invalidContentSize
        }

        progress = "Capturando página (\(Int(contentWidth))x\(Int(contentHeight)))..."

        // Store original state
        let originalFrame = webView.frame
        let originalScrollEnabled = webView.scrollView.isScrollEnabled
        let originalBounces = webView.scrollView.bounces
        let originalOffset = webView.scrollView.contentOffset

        // Disable scrolling and set frame to full content size
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentOffset = .zero

        let scale = UIScreen.main.scale
        let captureWidth = contentWidth
        let captureHeight = min(contentHeight, 30000) // Cap to avoid memory issues

        webView.frame = CGRect(x: 0, y: 0, width: captureWidth, height: captureHeight)

        // Wait for layout to settle
        try await Task.sleep(nanoseconds: 500_000_000)

        // Take snapshot
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: captureWidth, height: captureHeight)

        let image = try await webView.takeSnapshot(configuration: config)

        // Restore original state
        webView.frame = originalFrame
        webView.scrollView.isScrollEnabled = originalScrollEnabled
        webView.scrollView.bounces = originalBounces
        webView.scrollView.contentOffset = originalOffset

        return image
    }
}

enum CaptureError: LocalizedError {
    case invalidContentSize
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .invalidContentSize:
            return "No se pudo determinar el tamaño de la página"
        case .snapshotFailed:
            return "No se pudo capturar la página"
        }
    }
}
