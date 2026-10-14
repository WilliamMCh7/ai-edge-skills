import SwiftUI
import UIKit

/// "Web" tab: open any web page and capture it whole, from top to bottom, as an image and a PDF.
/// Owns its `NavigationStack`; the result is pushed as `ResultView`.
@MainActor
struct WebCaptureView: View {
    /// Created by the caller and kept by SwiftUI's state: a `@State` default value would build (and
    /// throw away) a new `WKWebView` every time this struct is re-created.
    @State private var model: WebViewModel
    @FocusState private var isAddressFocused: Bool
    @Environment(\.openURL) private var openURL

    private let suggestions = ["es.wikipedia.org", "apple.com/es", "github.com", "news.ycombinator.com"]

    /// `RootView` passes the model it owns, so the web view is created once.
    init(model: WebViewModel) {
        _model = State(initialValue: model)
    }

    /// Standalone use (previews): makes its own model.
    init() {
        self.init(model: WebViewModel())
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Web")
                .toolbar { toolbarContent }
                .alert("No se pudo continuar", isPresented: $model.isShowingError) {
                    Button("Aceptar", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
                .navigationDestination(item: $model.result) { result in
                    ResultView(model: result)
                }
        }
        .overlay {
            ZStack {
                if model.isCapturing {
                    WebCaptureProgressOverlay(step: model.captureStep)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.isCapturing)
        }
        .sensoryFeedback(.success, trigger: model.result?.id) { _, newValue in
            newValue != nil
        }
        .onChange(of: isAddressFocused) { _, focused in
            model.setEditingAddress(focused)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasPage {
            pageState
        } else {
            startState
        }
    }

    // MARK: - Start state

    /// No page yet: what the tab does, the address field and a few suggestions.
    private var startState: some View {
        ScrollView {
            VStack(spacing: 20) {
                startCard
                WebFeaturesCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.large)
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemName: "globe", size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Captura una web entera")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Captura páginas completas de arriba abajo, en alta resolución, como imagen y PDF.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                addressField(prompt: "Dirección web o búsqueda")
                clearAddressButton
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))

            Button {
                submitAddress()
            } label: {
                Label("Abrir página", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(.primary)
            .disabled(trimmedAddress.isEmpty)
            .accessibilityIdentifier("openButton")

            VStack(alignment: .leading, spacing: 10) {
                Text("Prueba con")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                suggestionChips
            }
        }
        .cardStyle()
    }

    private var suggestionChips: some View {
        let layout = WebChipFlowLayout(spacing: 8)
        return layout {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    open(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.subheadline.weight(.medium))
                        .fontDesign(.rounded)
                        .lineLimit(1)
                        .foregroundStyle(Theme.indigo)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.indigo.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre esta página.")
            }
        }
    }

    // MARK: - Page state

    /// A page is open: address bar, loading bar, the page itself and the browser bar.
    private var pageState: some View {
        VStack(spacing: 0) {
            addressBar
            loadingBar
            WebViewContainer(model: model)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            browserBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var addressBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.isSecure ? "lock.fill" : "globe")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                addressField(prompt: "Busca o escribe una dirección")
                    .font(.subheadline)
                clearAddressButton
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Color(.tertiarySystemFill), in: Capsule())

            if isAddressFocused {
                Button("Cancelar") {
                    isAddressFocused = false
                }
                .font(.subheadline)
                .tint(Theme.indigo)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: isAddressFocused)
        .background(Color(.systemBackground))
    }

    /// 2 pt gradient progress line over a hairline separator.
    private var loadingBar: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Theme.gradient)
                .frame(width: proxy.size.width * CGFloat(min(max(model.progress, 0), 1)))
        }
        .frame(height: 2)
        .opacity(model.isLoading ? 1 : 0)
        .background(alignment: .bottom) {
            Divider()
        }
        .animation(.easeOut(duration: 0.25), value: model.progress)
        .animation(.easeOut(duration: 0.25), value: model.isLoading)
        .accessibilityHidden(true)
    }

    private var browserBar: some View {
        HStack(spacing: 2) {
            browserButton(systemImage: "chevron.backward",
                          label: "Atrás",
                          identifier: "webBackButton",
                          isEnabled: model.canGoBack) {
                model.goBack()
            }
            browserButton(systemImage: "chevron.forward",
                          label: "Adelante",
                          identifier: "webForwardButton",
                          isEnabled: model.canGoForward) {
                model.goForward()
            }
            browserButton(systemImage: model.isLoading ? "xmark" : "arrow.clockwise",
                          label: model.isLoading ? "Detener" : "Recargar",
                          identifier: "webReloadButton",
                          isEnabled: true) {
                model.reloadOrStop()
            }

            Button {
                isAddressFocused = false
                Task { await model.capture() }
            } label: {
                Label("Capturar página", systemImage: "camera.viewfinder")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.primary)
            .disabled(model.isLoading || model.isCapturing)
            .accessibilityIdentifier("captureButton")
            .accessibilityHint("Guarda la página entera como imagen y PDF.")
            .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func browserButton(systemImage: String,
                               label: String,
                               identifier: String,
                               isEnabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(Theme.indigo)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Shared pieces

    /// The address field of both states (same accessibility identifier).
    private func addressField(prompt: LocalizedStringKey) -> some View {
        TextField(prompt, text: $model.addressText)
            .focused($isAddressFocused)
            .keyboardType(.webSearch)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .onSubmit {
                submitAddress()
            }
            .accessibilityIdentifier("urlField")
    }

    @ViewBuilder
    private var clearAddressButton: some View {
        if isAddressFocused && !model.addressText.isEmpty {
            Button {
                model.addressText = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Borrar")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model.hasPage {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isAddressFocused = false
                    model.showStart()
                } label: {
                    Label("Inicio", systemImage: "house")
                }
                .disabled(model.isCapturing)
                .accessibilityIdentifier("webHomeButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let url = model.currentURL {
                        ShareLink(item: url) {
                            Label("Compartir enlace", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            openURL(url)
                        } label: {
                            Label("Abrir en Safari", systemImage: "safari")
                        }
                    }
                } label: {
                    Label("Más opciones", systemImage: "ellipsis.circle")
                }
                .disabled(model.currentURL == nil || model.isCapturing)
                .accessibilityIdentifier("webMoreMenu")
            }
        }
    }

    private var trimmedAddress: String {
        model.addressText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitAddress() {
        let text = model.addressText
        isAddressFocused = false
        model.load(text)
    }

    private func open(_ suggestion: String) {
        isAddressFocused = false
        model.load(suggestion)
    }
}

// MARK: - Pieces

/// "Qué obtienes": what a web capture produces.
private struct WebFeaturesCard: View {
    private struct Feature: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        Feature(id: 0,
                systemImage: "photo",
                title: "Imagen en alta resolución",
                detail: "Toda la página en un único PNG, sin cortes ni uniones."),
        Feature(id: 1,
                systemImage: "doc.richtext",
                title: "PDF con texto seleccionable",
                detail: "Ideal para guardar artículos, recibos o documentación."),
        Feature(id: 2,
                systemImage: "arrow.down.circle",
                title: "Contenido completo",
                detail: "Recorremos la página para que carguen todas las imágenes.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Qué obtienes")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            ForEach(features) { feature in
                HStack(alignment: .top, spacing: 14) {
                    IconBadge(systemName: feature.systemImage, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(.headline, design: .rounded))
                        Text(feature.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .cardStyle()
    }
}

/// Dimmed screen with a card saying which capture stage is running.
private struct WebCaptureProgressOverlay: View {
    let step: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.indigo)
                Text(step)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Recorremos la página de arriba abajo para que no falte nada.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("captureProgress")
    }
}

/// Lays chips out left to right, wrapping onto a new line when a row is full.
private struct WebChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = min(size.width, maxWidth)
            if rowWidth > 0 && rowWidth + spacing + itemWidth > maxWidth {
                widest = max(widest, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + itemWidth
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: widest, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = min(size.width, bounds.width)
            if x > bounds.minX && x + itemWidth > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: itemWidth, height: size.height))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
