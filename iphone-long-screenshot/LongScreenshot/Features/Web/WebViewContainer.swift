import SwiftUI
import WebKit

/// Shows the model's existing `WKWebView` in SwiftUI. It never creates a web view of its own, so
/// the page, its history and its scroll position survive view updates.
@MainActor
struct WebViewContainer: UIViewRepresentable {
    let model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
