import SwiftUI
import WebKit

struct WebCaptureView: View {
    @StateObject private var captureService = WebCaptureService()
    @State private var urlString = "https://apple.com"
    @State private var navigationID = UUID()
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // URL bar
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        TextField("Ingresa una URL", text: $urlString)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit { navigateToURL() }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("Ir") { navigateToURL() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Web view
                WebViewRepresentable(
                    urlString: urlString,
                    navigationID: navigationID,
                    captureService: captureService
                )
                .overlay {
                    if captureService.isLoading {
                        ProgressView("Cargando...")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Bottom bar
                VStack(spacing: 8) {
                    if captureService.isCapturing {
                        ProgressView(captureService.progress)
                    }

                    if let error = captureService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            await captureService.captureFullPage()
                            if captureService.capturedImage != nil {
                                showResult = true
                            }
                        }
                    } label: {
                        Label("Capturar Pagina Completa", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(captureService.isCapturing || captureService.isLoading)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Captura Web")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showResult) {
                if let image = captureService.capturedImage {
                    ResultView(image: image)
                }
            }
        }
    }

    private func navigateToURL() {
        var text = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://" + text
        }
        urlString = text
        navigationID = UUID()
    }
}

// MARK: - WKWebView UIViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    let urlString: String
    let navigationID: UUID
    let captureService: WebCaptureService

    func makeCoordinator() -> Coordinator {
        Coordinator(captureService: captureService)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        captureService.setWebView(webView)

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
            context.coordinator.lastNavigationID = navigationID
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastNavigationID != navigationID {
            context.coordinator.lastNavigationID = navigationID
            if let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let captureService: WebCaptureService
        var lastNavigationID: UUID?

        init(captureService: WebCaptureService) {
            self.captureService = captureService
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                captureService.isLoading = true
                captureService.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                captureService.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                captureService.isLoading = false
                captureService.errorMessage = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                captureService.isLoading = false
                captureService.errorMessage = error.localizedDescription
            }
        }
    }
}
