import CoreGraphics
import SwiftUI
import UIKit

/// A finished long screenshot: summary card, tiled preview (with optional seam markers), save and
/// share actions, bar toggles and, for stitched results, the seam editor.
@MainActor
struct ResultView: View {
    let model: ResultModel

    @State private var isSaving = false
    @State private var saved = false
    @State private var shareURL: URL? = nil
    /// The PNG for sharing could not be written: the share button turns into a retry button.
    @State private var shareFailed = false
    /// Bumped by the retry button to run the share-file task again for the same image.
    @State private var shareAttempt = 0
    @State private var pdfURL: URL? = nil
    @State private var showEditor = false
    @State private var showMarkers = false
    @State private var didConfigureMarkers = false
    @State private var alertInfo: ResultAlert? = nil
    @Environment(\.openURL) private var openURL

    init(model: ResultModel) {
        self.model = model
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                preview
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            ZStack {
                if model.isRendering {
                    RenderingBadge()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.isRendering)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("resultView")
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showEditor) {
            SeamEditorView(model: model)
        }
        .alert(alertInfo?.title ?? "", isPresented: isAlertPresented, presenting: alertInfo) { info in
            if info.opensSettings {
                Button("Abrir Ajustes") { openSettings() }
                Button("Cancelar", role: .cancel) {}
            } else {
                Button("Aceptar", role: .cancel) {}
            }
        } message: { info in
            Text(info.message)
        }
        .task(id: ShareFileKey(image: ObjectIdentifier(model.image), attempt: shareAttempt)) {
            // A new image (first appearance or a re-render) or a retry needs a new PNG.
            await prepareShareFile()
        }
        .onChange(of: ObjectIdentifier(model.image)) {
            // A re-rendered image has not been saved yet.
            saved = false
        }
        .task {
            guard model.isWebPage, pdfURL == nil else { return }
            pdfURL = try? model.pdfFileURL()
        }
        .onAppear {
            // Markers start visible only when some seam needs a look.
            guard !didConfigureMarkers else { return }
            didConfigureMarkers = true
            showMarkers = model.plan?.needsReview ?? false
        }
        .sensoryFeedback(.success, trigger: saved) { _, isSaved in
            isSaved
        }
        .sensoryFeedback(.error, trigger: alertInfo != nil) { _, isShown in
            isShown
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(systemName: model.isWebPage ? "globe" : "rectangle.stack.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dimensionsText)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .accessibilityLabel(dimensionsAccessibilityText)
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if hasChips {
                chips
            }
        }
        .cardStyle()
    }

    private var chips: some View {
        let layout = ChipFlowLayout(spacing: 8)
        return layout {
            chipContent
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        if let plan = model.plan {
            if plan.needsReview {
                Button {
                    showEditor = true
                } label: {
                    StatusChip(text: reviewText(count: plan.reviewCount),
                               systemImage: "exclamationmark.triangle.fill",
                               color: Theme.warning)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre el editor de uniones.")
                .accessibilityIdentifier("reviewChip")
            } else if !plan.seams.isEmpty {
                StatusChip(text: "Uniones verificadas",
                           systemImage: "checkmark.seal.fill",
                           color: Theme.success)
            }
            if plan.autoReversed {
                StatusChip(text: "Orden invertido automáticamente",
                           systemImage: "arrow.up.arrow.down",
                           color: Theme.indigo)
            }
            if !plan.droppedDuplicates.isEmpty {
                StatusChip(text: duplicatesText(count: plan.droppedDuplicates.count),
                           systemImage: "square.on.square",
                           color: Color.secondary)
            }
        } else if model.isWebPage {
            StatusChip(text: "Imagen y PDF", systemImage: "doc.richtext", color: Theme.indigo)
        }
    }

    private var hasChips: Bool {
        guard let plan = model.plan else { return model.isWebPage }
        return !plan.seams.isEmpty || plan.autoReversed || !plan.droppedDuplicates.isEmpty
    }

    private var dimensionsText: String {
        let width = model.image.width.formatted()
        let height = model.image.height.formatted()
        // Narrow no-break spaces keep "1179 × 25.560 px" on one line.
        return "\(width)\u{202F}×\u{202F}\(height)\u{202F}px"
    }

    private var dimensionsAccessibilityText: String {
        "\(model.image.width) por \(model.image.height) píxeles"
    }

    private var detailText: String {
        guard let plan = model.plan else { return "Página completa" }
        let sourceCount = model.sources.count
        let seamCount = plan.seams.count
        let captures = sourceCount == 1 ? "1 captura" : "\(sourceCount) capturas"
        let seams = seamCount == 1 ? "1 unión" : "\(seamCount) uniones"
        return "\(captures) · \(seams)"
    }

    private func reviewText(count: Int) -> String {
        count == 1 ? "Revisa 1 unión" : "Revisa \(count) uniones"
    }

    private func duplicatesText(count: Int) -> String {
        count == 1 ? "Se quitó 1 duplicada" : "Se quitaron \(count) duplicadas"
    }

    // MARK: - Preview

    private var preview: some View {
        TiledImageView(image: model.image,
                       markers: model.seamMarkers,
                       showMarkers: showMarkers && model.plan != nil)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 6)
            }
            .opacity(model.isRendering ? 0.55 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vista previa de la imagen")
            .accessibilityValue(dimensionsAccessibilityText)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("resultPreview")
    }

    // MARK: - Bottom bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            saveButton
            shareControl
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            ZStack {
                if isSaving {
                    ProgressView()
                        .tint(Color.white)
                } else if saved {
                    Label("Guardada", systemImage: "checkmark.circle.fill")
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Label("Guardar en Fotos", systemImage: "square.and.arrow.down")
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: saved)
        }
        .buttonStyle(.primary)
        .disabled(isSaving || model.isRendering)
        .accessibilityLabel(saveTitle)
        .accessibilityIdentifier("saveButton")
    }

    private var saveTitle: String {
        if isSaving { return "Guardando…" }
        return saved ? "Guardada" : "Guardar en Fotos"
    }

    /// Share button once the PNG file is ready; a spinner in its place meanwhile (no layout jump),
    /// or a retry button if the file could not be written.
    @ViewBuilder
    private var shareControl: some View {
        if let shareURL, !model.isRendering {
            ShareLink(item: shareURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.indigo)
                    .frame(width: 54, height: 54)
                    .background(Theme.indigo.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Compartir")
            .accessibilityIdentifier("shareButton")
        } else if shareFailed, !model.isRendering {
            Button {
                shareAttempt += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .frame(width: 54, height: 54)
                    .background(Theme.warning.opacity(0.14), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reintentar compartir")
            .accessibilityHint("No se pudo preparar la imagen para compartir.")
            .accessibilityIdentifier("shareRetryButton")
        } else {
            ProgressView()
                .frame(width: 54, height: 54)
                .background(Theme.indigo.opacity(0.08), in: Circle())
                .accessibilityLabel("Preparando para compartir")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let plan = model.plan {
                Button {
                    showEditor = true
                } label: {
                    Label("Ajustar", systemImage: "slider.horizontal.3")
                }
                .disabled(plan.seams.isEmpty)
                .accessibilityIdentifier("seamEditorButton")
            }
            if hasMenuItems {
                Menu {
                    menuContent
                } label: {
                    Label("Más opciones", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("resultMenu")
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let plan = model.plan {
            Toggle(isOn: $showMarkers) {
                Label("Mostrar uniones", systemImage: "rectangle.split.1x2")
            }
            .disabled(plan.seams.isEmpty)

            Toggle(isOn: includeHeaderBinding) {
                Label("Incluir barra superior", systemImage: "rectangle.topthird.inset.filled")
            }
            .disabled(plan.headerHeight == 0)

            Toggle(isOn: includeFooterBinding) {
                Label("Incluir barra inferior", systemImage: "rectangle.bottomthird.inset.filled")
            }
            .disabled(plan.footerHeight == 0)
        }
        if model.isWebPage, let pdfURL {
            ShareLink(item: pdfURL) {
                Label("Compartir PDF", systemImage: "doc.richtext")
            }
        }
    }

    private var hasMenuItems: Bool {
        model.plan != nil || (model.isWebPage && pdfURL != nil)
    }

    private var includeHeaderBinding: Binding<Bool> {
        Binding(
            get: { model.plan?.includeHeader ?? true },
            set: { newValue in
                guard var plan = model.plan else { return }
                plan.includeHeader = newValue
                model.apply(plan)
            }
        )
    }

    private var includeFooterBinding: Binding<Bool> {
        Binding(
            get: { model.plan?.includeFooter ?? true },
            set: { newValue in
                guard var plan = model.plan else { return }
                plan.includeFooter = newValue
                model.apply(plan)
            }
        )
    }

    // MARK: - Actions

    /// Writes the PNG used by the share button. A cancelled run (the image changed again) leaves
    /// the state to the newer run.
    private func prepareShareFile() async {
        shareURL = nil
        shareFailed = false
        do {
            let url = try await model.pngFileURL()
            guard !Task.isCancelled else { return }
            shareURL = url
        } catch {
            guard !Task.isCancelled else { return }
            shareFailed = true
        }
    }

    private func save() async {
        guard !isSaving, !saved else { return }
        isSaving = true
        do {
            try await model.saveToPhotos()
            saved = true
        } catch {
            present(error)
        }
        isSaving = false
    }

    private func present(_ error: Error) {
        if let photoError = error as? PhotoLibraryError, case .accessDenied = photoError {
            alertInfo = ResultAlert(
                title: "Permite el acceso a Fotos en Ajustes",
                message: "Captura Larga necesita permiso para guardar la imagen en tu fototeca.",
                opensSettings: true
            )
        } else {
            alertInfo = ResultAlert(
                title: "No se pudo guardar",
                message: error.localizedDescription,
                opensSettings: false
            )
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { alertInfo != nil },
            set: { isPresented in
                if !isPresented { alertInfo = nil }
            }
        )
    }
}

/// Identity of the share-file task: a new image or a retry starts it again.
private struct ShareFileKey: Equatable {
    let image: ObjectIdentifier
    let attempt: Int
}

/// Content of the error alert.
private struct ResultAlert {
    let title: String
    let message: String
    /// Photo access was denied: offer "Abrir Ajustes".
    let opensSettings: Bool
}

/// Floating capsule shown while an edited plan is being re-rendered.
private struct RenderingBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Actualizando…")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// Lays chips out left to right, wrapping to a new row when the width runs out.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = layoutFrames(for: subviews, maxWidth: proposal.width ?? .infinity)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for frame in frames {
            width = max(width, frame.maxX)
            height = max(height, frame.maxY)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = layoutFrames(for: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func layoutFrames(for subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
