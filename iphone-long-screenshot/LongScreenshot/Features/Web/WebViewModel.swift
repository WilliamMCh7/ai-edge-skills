import Foundation
import Observation
import UIKit
import WebKit

/// State of the "Web" tab: one long-lived `WKWebView`, its navigation state (mirrored through KVO so
/// SwiftUI can observe it), the address field and the whole-page capture.
@Observable
@MainActor
final class WebViewModel {
    /// The only web view of the tab, shown by `WebViewContainer`. Never replaced.
    let webView: WKWebView

    /// Text of the address field. Follows the current URL unless the field is being edited.
    var addressText = ""
    /// Estimated loading progress, 0...1.
    private(set) var progress: Double = 0
    private(set) var pageTitle = ""
    /// The page being shown (or the last one requested while it starts loading).
    private(set) var currentURL: URL? = nil
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    /// False until a page is opened: the view then switches from the start card to the browser.
    private(set) var hasPage = false
    private(set) var isCapturing = false
    /// What the capture is doing right now ("Cargando contenido…", "Generando PDF…", "Creando imagen…").
    private(set) var captureStep = ""
    var errorMessage: String? = nil
    /// The captured page; non-nil pushes `ResultView`.
    var result: ResultModel? = nil

    /// True while the address field has focus, so navigation updates do not overwrite typing.
    private var isEditingAddress = false
    private let navigationDelegate: WebNavigationDelegate
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        let delegate = WebNavigationDelegate()
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        self.webView = webView
        self.navigationDelegate = delegate
        delegate.model = self
        observations = [
            makeObservation(\.estimatedProgress),
            makeObservation(\.title),
            makeObservation(\.url),
            makeObservation(\.canGoBack),
            makeObservation(\.canGoForward),
            makeObservation(\.isLoading)
        ]
    }

    /// Lock icon in the address bar.
    var isSecure: Bool { currentURL?.scheme?.lowercased() == "https" }

    /// Drives the error alert; setting it to false dismisses the error.
    var isShowingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue { errorMessage = nil }
        }
    }

    // MARK: - Navigation

    /// Opens what the person typed: a web address (https:// is added when missing) or, when the text
    /// has no dot or contains a space, a Google search. Empty input is ignored.
    func load(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = WebViewModel.url(fromUserInput: trimmed) else { return }
        errorMessage = nil
        currentURL = url
        addressText = url.absoluteString
        hasPage = true
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    /// Stops a load in progress, otherwise reloads (or retries a first load that failed).
    func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
        } else if webView.url != nil {
            webView.reload()
        } else if let currentURL {
            webView.load(URLRequest(url: currentURL))
        }
    }

    /// Back to the start card. The web view keeps its history.
    func showStart() {
        webView.stopLoading()
        hasPage = false
        addressText = ""
    }

    /// Called by the view when the address field gains or loses focus. Leaving the field without
    /// submitting restores the current address.
    func setEditingAddress(_ editing: Bool) {
        isEditingAddress = editing
        if !editing, hasPage, let currentURL {
            addressText = currentURL.absoluteString
        }
    }

    /// Turns address-field input into a URL (see `load(_:)`).
    nonisolated static func url(fromUserInput text: String) -> URL? {
        if !text.contains(".") || text.contains(" ") {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+=?#/")
            guard let query = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return URL(string: "https://www.google.com/search?q=" + query)
        }
        if text.contains("://") {
            return URL(string: text)
        }
        return URL(string: "https://" + text)
    }

    // MARK: - Capture

    /// Captures the whole page as an image + PDF and publishes it as `result`.
    func capture() async {
        guard hasPage, !isCapturing else { return }
        isCapturing = true
        errorMessage = nil
        captureStep = WebViewModel.stepText(.loadingContent)

        let traitScale = webView.traitCollection.displayScale
        let scale: CGFloat = traitScale > 0 ? traitScale : 3
        do {
            let output = try await WebPageCapturer.capture(webView, scale: scale, onStep: { step in
                self.captureStep = WebViewModel.stepText(step)
            })
            result = ResultModel(webPage: output.image, title: output.title, pdfData: output.pdfData)
        } catch {
            errorMessage = error.localizedDescription
        }
        isCapturing = false
    }

    nonisolated private static func stepText(_ step: WebPageCapturer.Step) -> String {
        switch step {
        case .loadingContent: return "Cargando contenido…"
        case .creatingPDF: return "Generando PDF…"
        case .renderingImage: return "Creando imagen…"
        }
    }

    // MARK: - Web view state

    private func makeObservation<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
            guard let model = self else { return }
            // WebKit posts KVO changes on the main thread.
            MainActor.assumeIsolated {
                model.syncFromWebView()
            }
        }
    }

    /// Copies the web view's state into tracked properties, only when a value changed so progress
    /// ticks do not invalidate unrelated views.
    private func syncFromWebView() {
        let newProgress = webView.estimatedProgress
        if progress != newProgress { progress = newProgress }
        let newTitle = webView.title ?? ""
        if pageTitle != newTitle { pageTitle = newTitle }
        let newCanGoBack = webView.canGoBack
        if canGoBack != newCanGoBack { canGoBack = newCanGoBack }
        let newCanGoForward = webView.canGoForward
        if canGoForward != newCanGoForward { canGoForward = newCanGoForward }
        let newIsLoading = webView.isLoading
        if isLoading != newIsLoading { isLoading = newIsLoading }
        if let url = webView.url, url != currentURL {
            currentURL = url
        }
        if hasPage, !isEditingAddress, let currentURL, addressText != currentURL.absoluteString {
            addressText = currentURL.absoluteString
        }
    }

    /// Shows a failed load. Cancelled navigations (a new load replaced the old one) and interrupted
    /// frame loads (downloads, App Store links) are not errors.
    fileprivate func navigationFailed(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        errorMessage = WebViewModel.message(for: nsError)
    }

    nonisolated private static func message(for error: NSError) -> String {
        guard error.domain == NSURLErrorDomain else {
            return "No se pudo cargar la página. Revisa la dirección e inténtalo de nuevo."
        }
        switch URLError.Code(rawValue: error.code) {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "No hay conexión a internet. Revisa tu conexión e inténtalo de nuevo."
        case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost:
            return "No se encontró el sitio. Revisa la dirección."
        case .timedOut:
            return "La página tardó demasiado en responder. Inténtalo de nuevo."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "No se pudo establecer una conexión segura con el sitio."
        case .appTransportSecurityRequiresSecureConnection:
            return "Este sitio no usa una conexión segura (https)."
        default:
            return "No se pudo cargar la página. Inténtalo de nuevo."
        }
    }
}

/// Receives WebKit callbacks for `WebViewModel` (WebKit delegates must be NSObjects). WebKit calls
/// them on the main thread.
private final class WebNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: WebViewModel?

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        report(error)
    }

    /// The web content process crashed (usually memory pressure): reload instead of staying blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            _ = webView.reload()
        }
    }

    /// Links that open a new window (target="_blank") load in the same web view.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        MainActor.assumeIsolated {
            if navigationAction.targetFrame == nil {
                _ = webView.load(navigationAction.request)
            }
        }
        return nil
    }

    private func report(_ error: Error) {
        let model = self.model
        MainActor.assumeIsolated {
            if let model {
                model.navigationFailed(error)
            }
        }
    }
}
