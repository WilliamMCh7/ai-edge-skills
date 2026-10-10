import CoreGraphics
import UIKit
import WebKit
import XCTest
@testable import LongScreenshot

/// Whole-page web capture on a real `WKWebView`: a 3000 CSS px page made of three coloured
/// 1000 px blocks must come out as one tall image with every block in place.
@MainActor
final class WebPageCapturerTests: XCTestCase {
    private static let pageHTML = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    html, body { margin: 0; padding: 0; background: #ffffff; }
    .block { display: block; width: 100%; height: 1000px; margin: 0; }
    </style>
    </head>
    <body>
    <div class="block" style="background: #ff0000;"></div>
    <div class="block" style="background: #00ff00;"></div>
    <div class="block" style="background: #0000ff;"></div>
    </body>
    </html>
    """

    func testCapturesWholePageAtRequestedScale() async throws {
        let (window, webView) = try await makeLoadedWebView()
        defer { window.isHidden = true }

        let output = try await WebPageCapturer.capture(webView, scale: 2)
        let image = output.image

        XCTAssertEqual(Double(image.width), 780, accuracy: 4)
        XCTAssertEqual(Double(image.height), 6000, accuracy: 40)
        XCTAssertFalse(output.pdfData.isEmpty)

        let centerX = image.width / 2
        let top = try XCTUnwrap(averageColor(of: image, x: centerX, y: 1000 * image.height / 6000))
        let middle = try XCTUnwrap(averageColor(of: image, x: centerX, y: 3000 * image.height / 6000))
        let bottom = try XCTUnwrap(averageColor(of: image, x: centerX, y: 5000 * image.height / 6000))

        XCTAssertTrue(top.red > 180 && top.green < 90 && top.blue < 90, "Expected red, got \(top)")
        XCTAssertTrue(middle.green > 180 && middle.red < 90 && middle.blue < 90, "Expected green, got \(middle)")
        XCTAssertTrue(bottom.blue > 180 && bottom.red < 90 && bottom.green < 90, "Expected blue, got \(bottom)")
    }

    func testMaxPixelsDownscalesUniformly() async throws {
        let (window, webView) = try await makeLoadedWebView()
        defer { window.isHidden = true }

        let output = try await WebPageCapturer.capture(webView, scale: 2, maxPixels: 1_000_000)
        let image = output.image

        XCTAssertLessThanOrEqual(image.width * image.height, 1_000_000)
        XCTAssertGreaterThan(image.width * image.height, 900_000, "The budget should be used, not wasted")
        let ratio = Double(image.height) / Double(image.width)
        let expectedRatio = 6000.0 / 780.0
        XCTAssertEqual(ratio, expectedRatio, accuracy: expectedRatio * 0.02)
        XCTAssertFalse(output.pdfData.isEmpty)
    }

    func testErrorsHaveSpanishDescriptions() {
        let errors: [WebCaptureError] = [.emptyPage, .pdfFailed, .renderFailed]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    // MARK: - Helpers

    /// A 390 × 844 pt web view in a visible window with the test page fully loaded.
    private func makeLoadedWebView() async throws -> (UIWindow, WKWebView) {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        window.rootViewController = controller

        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        controller.view.addSubview(webView)
        window.makeKeyAndVisible()

        let finished = expectation(description: "Page finished loading")
        let waiter = NavigationWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.loadHTMLString(WebPageCapturerTests.pageHTML, baseURL: nil)
        await fulfillment(of: [finished], timeout: 20)

        XCTAssertNil(waiter.failure, "The test page failed to load")
        webView.navigationDelegate = nil
        return (window, webView)
    }

    private struct RGB: CustomStringConvertible {
        let red: Int
        let green: Int
        let blue: Int

        var description: String { "rgb(\(red), \(green), \(blue))" }
    }

    /// Mean colour of a 9 × 9 pixel patch centred on (x, y) (top-left origin).
    private func averageColor(of image: CGImage, x: Int, y: Int) -> RGB? {
        let size = 9
        let originX = min(max(x - size / 2, 0), max(image.width - size, 0))
        let originY = min(max(y - size / 2, 0), max(image.height - size, 0))
        guard let patch = image.cropping(to: CGRect(x: originX, y: originY, width: size, height: size)),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let width = patch.width
        let height = patch.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width * height > 0 else { return nil }

        var red = 0
        var green = 0
        var blue = 0
        for index in 0..<(width * height) {
            red += Int(pixels[index * 4])
            green += Int(pixels[index * 4 + 1])
            blue += Int(pixels[index * 4 + 2])
        }
        let count = width * height
        return RGB(red: red / count, green: green / count, blue: blue / count)
    }
}

/// Fulfils an expectation when the page finishes loading (or fails, recording the error).
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation
    var failure: Error?

    init(finished: XCTestExpectation) {
        self.finished = finished
        self.finished.assertForOverFulfill = false
        super.init()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = error
        finished.fulfill()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        failure = error
        finished.fulfill()
    }
}
