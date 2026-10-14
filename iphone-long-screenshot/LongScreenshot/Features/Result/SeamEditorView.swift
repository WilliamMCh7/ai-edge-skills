import CoreGraphics
import SwiftUI
import UIKit

/// Sheet to review and fine-tune every seam of a stitched result. Works on a local copy of the
/// plan: "Listo" applies it to the model (which re-renders off the main thread), "Cancelar"
/// discards it.
@MainActor
struct SeamEditorView: View {
    let model: ResultModel

    /// Local, editable copy of `model.plan`.
    @State private var plan: StitchPlan?
    @Environment(\.dismiss) private var dismiss

    init(model: ResultModel) {
        self.model = model
        _plan = State(initialValue: model.plan)
    }

    var body: some View {
        NavigationStack {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("seamEditorView")
                .navigationTitle("Uniones")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") {
                            applyAndDismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    @ViewBuilder
    private var content: some View {
        if let current = plan, !current.seams.isEmpty {
            editor(current)
        } else {
            ContentUnavailableView(
                "No hay uniones",
                systemImage: "rectangle.split.1x2",
                description: Text("Esta imagen no tiene uniones que ajustar.")
            )
        }
    }

    private func editor(_ current: StitchPlan) -> some View {
        let heights = model.sourceHeights
        let sources = model.sources
        return ScrollView {
            LazyVStack(spacing: 16) {
                introCard(current)
                ForEach(current.seams.indices, id: \.self) { index in
                    SeamCard(
                        index: index,
                        kind: current.seams[index].kind,
                        range: current.adjustmentRange(forSeam: index, sourceHeights: heights),
                        adjustment: adjustmentBinding(for: index),
                        plan: current,
                        sources: sources
                    )
                }
                barsCard(current)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }

    // MARK: - Cards

    private func introCard(_ current: StitchPlan) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: "slider.horizontal.3", size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(introTitle(current))
                    .font(.system(.headline, design: .rounded))
                Text("Si ves contenido repetido en una unión, sube el ajuste. Si falta contenido, bájalo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private func introTitle(_ current: StitchPlan) -> String {
        let count = current.reviewCount
        if count == 0 { return "Todas las uniones coinciden" }
        return count == 1 ? "Revisa 1 unión" : "Revisa \(count) uniones"
    }

    private func barsCard(_ current: StitchPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Barras fijas")
                .font(.system(.headline, design: .rounded))

            Toggle(isOn: includeHeaderBinding) {
                barLabel(
                    title: "Incluir barra superior",
                    detail: current.headerHeight > 0
                        ? "Barra de estado y de navegación · \(current.headerHeight) px"
                        : "No se detectó ninguna barra fija"
                )
            }
            .disabled(current.headerHeight == 0)
            .accessibilityIdentifier("includeHeaderToggle")

            Divider()

            Toggle(isOn: includeFooterBinding) {
                barLabel(
                    title: "Incluir barra inferior",
                    detail: current.footerHeight > 0
                        ? "Barra de pestañas e indicador de inicio · \(current.footerHeight) px"
                        : "No se detectó ninguna barra fija"
                )
            }
            .disabled(current.footerHeight == 0)
            .accessibilityIdentifier("includeFooterToggle")
        }
        .tint(Theme.indigo)
        .cardStyle()
    }

    private func barLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings and actions

    private var hasChanges: Bool {
        plan != model.plan
    }

    private func adjustmentBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { plan?.seams[index].adjustment ?? 0 },
            set: { newValue in plan?.seams[index].adjustment = newValue }
        )
    }

    private var includeHeaderBinding: Binding<Bool> {
        Binding(
            get: { plan?.includeHeader ?? true },
            set: { newValue in plan?.includeHeader = newValue }
        )
    }

    private var includeFooterBinding: Binding<Bool> {
        Binding(
            get: { plan?.includeFooter ?? true },
            set: { newValue in plan?.includeFooter = newValue }
        )
    }

    private func applyAndDismiss() {
        if let plan {
            model.apply(plan)
        }
        dismiss()
    }
}

/// One seam: title, status, close-up preview with the seam line, and the adjustment controls.
private struct SeamCard: View {
    let index: Int
    let kind: Seam.Kind
    let range: ClosedRange<Int>
    @Binding var adjustment: Int
    /// The edited plan, used to render the preview.
    let plan: StitchPlan
    let sources: [SourceImage]

    @State private var preview: CGImage? = nil

    init(index: Int,
         kind: Seam.Kind,
         range: ClosedRange<Int>,
         adjustment: Binding<Int>,
         plan: StitchPlan,
         sources: [SourceImage]) {
        self.index = index
        self.kind = kind
        self.range = range
        self._adjustment = adjustment
        self.plan = plan
        self.sources = sources
    }

    /// Rows of each image shown above and below the seam in the preview.
    private static let previewContext = 220

    /// The preview depends on this seam's adjustment and on where its two slices start and end
    /// (the previous seam's adjustment, the header and footer toggles), so the whole edited plan
    /// is part of the key. Re-renders are cheap (2 × `previewContext` rows).
    private struct PreviewKey: Equatable {
        let seamIndex: Int
        let plan: StitchPlan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("Unión \(index + 1) → \(index + 2)")
                    .font(.system(.headline, design: .rounded))
                Spacer(minLength: 8)
                statusChip
            }

            previewView

            Stepper(value: $adjustment, in: range) {
                Text("Ajuste: \(signedAdjustment) px")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("seamStepper\(index)")

            HStack(spacing: 8) {
                Button("−10") {
                    nudge(by: -10)
                }
                .disabled(adjustment <= range.lowerBound)
                .accessibilityLabel("Restar 10 píxeles")

                Button("+10") {
                    nudge(by: 10)
                }
                .disabled(adjustment >= range.upperBound)
                .accessibilityLabel("Sumar 10 píxeles")

                Spacer(minLength: 8)

                Button("Restablecer") {
                    adjustment = clamped(0)
                }
                .disabled(adjustment == 0)
            }
            .buttonStyle(.bordered)
            .tint(Theme.indigo)
        }
        .cardStyle()
        .task(id: PreviewKey(seamIndex: index, plan: plan)) {
            await renderPreview()
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch kind {
        case .matched:
            StatusChip(text: "Coincidencia exacta", systemImage: "checkmark.seal.fill", color: Theme.success)
        case .estimated:
            StatusChip(text: "Estimada", systemImage: "questionmark.circle.fill", color: Theme.warning)
        case .reversed:
            StatusChip(text: "Orden dudoso", systemImage: "arrow.up.arrow.down", color: Theme.warning)
        }
    }

    /// Close-up fitted to the card width (at most 240 pt tall) with an indigo line at the seam,
    /// which is always the vertical middle of the rendered preview.
    private var previewView: some View {
        ZStack {
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        Rectangle()
                            .fill(Theme.indigo)
                            .frame(height: 2)
                            .shadow(color: Color.white.opacity(0.8), radius: 1)
                    }
            } else {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(placeholderAspectRatio, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vista previa de la unión \(index + 1)")
        .accessibilityAddTraits(.isImage)
    }

    private var placeholderAspectRatio: CGFloat {
        CGFloat(max(plan.width, 1)) / CGFloat(2 * Self.previewContext)
    }

    private var signedAdjustment: String {
        if adjustment > 0 { return "+\(adjustment)" }
        if adjustment < 0 { return "−\(-adjustment)" }
        return "0"
    }

    private func nudge(by delta: Int) {
        adjustment = clamped(adjustment + delta)
    }

    private func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Renders the close-up off the main thread; a newer key cancels this one.
    private func renderPreview() async {
        let plan = self.plan
        let sources = self.sources
        let seamIndex = self.index
        let context = Self.previewContext
        let image = await Task.detached(priority: .userInitiated) {
            StitchRenderer.renderSeamPreview(plan: plan, seamIndex: seamIndex, sources: sources, context: context)
        }.value
        guard !Task.isCancelled else { return }
        preview = image
    }
}
