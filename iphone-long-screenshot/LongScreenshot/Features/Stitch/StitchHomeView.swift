import PhotosUI
import SwiftUI
import UIKit

/// "Unir" tab: choose overlapping screenshots, put them in order and stitch them into one long
/// image. Owns its `NavigationStack`; the result is pushed as `ResultView`.
@MainActor
struct StitchHomeView: View {
    @State private var viewModel = StitchViewModel()
    /// Selection shared by both photo pickers. It is consumed (and reset) as soon as it changes,
    /// so every pick appends to the list.
    @State private var pickerSelection: [PhotosPickerItem] = []
    /// Presents the picker from the toolbar menu ("Añadir capturas").
    @State private var isAddPickerPresented = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Captura Larga")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) {
                    if !viewModel.items.isEmpty {
                        stitchBar
                    }
                }
                .photosPicker(isPresented: $isAddPickerPresented,
                              selection: $pickerSelection,
                              maxSelectionCount: StitchViewModel.maxSelectionCount,
                              selectionBehavior: .ordered,
                              matching: .images,
                              preferredItemEncoding: .current,
                              photoLibrary: .shared())
                .onChange(of: pickerSelection) { _, newSelection in
                    guard !newSelection.isEmpty else { return }
                    Task { await viewModel.add(newSelection) }
                    pickerSelection = []
                }
                .alert("No se pudo continuar", isPresented: $viewModel.isShowingError) {
                    if viewModel.errorIsPhotoAccess {
                        Button("Abrir Ajustes") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        Button("Cancelar", role: .cancel) {}
                    } else {
                        Button("Aceptar", role: .cancel) {}
                    }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .navigationDestination(item: $viewModel.result) { model in
                    ResultView(model: model)
                }
        }
        .overlay {
            ZStack {
                if viewModel.isStitching {
                    StitchProgressOverlay(progress: viewModel.progress)
                        .transition(.opacity)
                } else if viewModel.isLoading {
                    StitchLoadingToast()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.isStitching)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
        }
        .sensoryFeedback(.success, trigger: viewModel.result?.id) { _, newValue in
            newValue != nil
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        if viewModel.items.isEmpty {
            emptyState
        } else {
            screenshotList
        }
    }

    /// First run / nothing selected: the three ways to start come right after the hero so they stay
    /// above the floating tab bar; the explanation follows.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                StitchHeroCard()
                startActions
                StitchHowToCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
        }
    }

    private var startActions: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerSelection,
                         maxSelectionCount: StitchViewModel.maxSelectionCount,
                         selectionBehavior: .ordered,
                         matching: .images,
                         preferredItemEncoding: .current,
                         photoLibrary: .shared()) {
                Label("Elegir capturas", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("pickButton")
            .accessibilityHint("Abre tu fototeca para elegir las capturas en orden.")

            Button {
                Task { await viewModel.addRecent() }
            } label: {
                Label("Usar capturas recientes", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("recentButton")
            .accessibilityHint("Añade las últimas capturas que hiciste seguidas.")

            Button {
                viewModel.loadDemo()
            } label: {
                Label("Probar con un ejemplo", systemImage: "sparkles")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(Theme.indigo)
            .accessibilityIdentifier("demoButton")
            .accessibilityHint("Carga cuatro capturas de muestra para ver cómo funciona.")
        }
        .disabled(viewModel.isLoading)
    }

    /// Screenshots chosen: reorderable list, top to bottom.
    private var screenshotList: some View {
        List {
            Section {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    ScreenshotRow(item: item, index: index)
                        .contextMenu {
                            Button {
                                viewModel.moveUp(item.id)
                            } label: {
                                Label("Subir", systemImage: "arrow.up")
                            }
                            .disabled(index == 0)

                            Button {
                                viewModel.moveDown(item.id)
                            } label: {
                                Label("Bajar", systemImage: "arrow.down")
                            }
                            .disabled(index >= viewModel.items.count - 1)

                            Button(role: .destructive) {
                                viewModel.remove(item.id)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: "Subir") {
                            viewModel.moveUp(item.id)
                        }
                        .accessibilityAction(named: "Bajar") {
                            viewModel.moveDown(item.id)
                        }
                }
                .onMove { source, destination in
                    viewModel.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    viewModel.remove(atOffsets: offsets)
                }
            } header: {
                Text(sectionTitle)
                    .textCase(nil)
            } footer: {
                Text("La primera va arriba. Las partes repetidas se eliminan solas.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    private var sectionTitle: String {
        let count = viewModel.items.count
        let noun = count == 1 ? "1 captura" : "\(count) capturas"
        return "\(noun) · arrastra para reordenar"
    }

    // MARK: - Toolbar and bottom bar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !viewModel.items.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Button("Vaciar", role: .destructive) {
                    viewModel.clear()
                }
                .disabled(viewModel.isStitching)
                .accessibilityIdentifier("clearButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.reverse()
                    } label: {
                        Label("Invertir orden", systemImage: "arrow.up.arrow.down")
                    }
                    Button {
                        isAddPickerPresented = true
                    } label: {
                        Label("Añadir capturas", systemImage: "plus")
                    }
                } label: {
                    Label("Más opciones", systemImage: "ellipsis.circle")
                }
                .disabled(viewModel.isStitching)
                .accessibilityIdentifier("moreMenu")
            }
        }
    }

    private var stitchBar: some View {
        let count = viewModel.items.count
        let title = count >= 2 ? "Unir \(count) capturas" : "Unir capturas"
        return VStack(spacing: 8) {
            Button {
                Task { await viewModel.stitch() }
            } label: {
                Label(title, systemImage: "arrow.down.to.line.compact")
            }
            .buttonStyle(.primary)
            .disabled(!viewModel.canStitch)
            .accessibilityIdentifier("stitchButton")

            if count < 2 {
                Text("Añade al menos otra captura para poder unirlas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Empty state pieces

/// Gradient banner with the app's promise and a decorative stack of phone screens.
private struct StitchHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Une tus capturas en una sola imagen")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Funciona con cualquier app: chats, redes sociales, webs y más.")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.88))
            }
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if !dynamicTypeSize.isAccessibilitySize {
                StitchPhoneStack()
                    .frame(width: 104, height: 132)
                    .accessibilityHidden(true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .topTrailing) {
                Theme.gradient
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 190, height: 190)
                    .offset(x: 70, y: -80)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .shadow(color: Theme.indigo.opacity(0.30), radius: 16, x: 0, y: 8)
    }
}

/// Three tilted phone screens with placeholder text lines (purely decorative).
private struct StitchPhoneStack: View {
    var body: some View {
        ZStack {
            StitchPhoneSketch(lineCount: 4)
                .rotationEffect(.degrees(-16))
                .offset(x: -24, y: 12)
                .opacity(0.55)
            StitchPhoneSketch(lineCount: 5)
                .rotationEffect(.degrees(-3))
                .offset(x: 0, y: 2)
                .opacity(0.8)
            StitchPhoneSketch(lineCount: 6)
                .rotationEffect(.degrees(11))
                .offset(x: 24, y: -6)
        }
    }
}

/// One small phone screen drawn with rounded rectangles and capsules.
private struct StitchPhoneSketch: View {
    let lineCount: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white)
            .frame(width: 48, height: 96)
            .overlay(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(Theme.indigo.opacity(0.6))
                        .frame(width: 22, height: 5)
                    ForEach(0..<lineCount, id: \.self) { line in
                        Capsule()
                            .fill(Theme.violet.opacity(0.28))
                            .frame(width: line.isMultiple(of: 2) ? 32 : 22, height: 5)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
    }
}

/// "Cómo hacerlo": three numbered steps.
private struct StitchHowToCard: View {
    private struct Step: Identifiable {
        let id: Int
        let systemImage: String
        let title: String
        let detail: String
    }

    private let steps: [Step] = [
        Step(id: 1,
             systemImage: "camera.viewfinder",
             title: "Haz capturas mientras deslizas",
             detail: "Deja que cada captura repita un poco de la anterior."),
        Step(id: 2,
             systemImage: "photo.on.rectangle.angled",
             title: "Elígelas aquí",
             detail: "Detectamos el orden y las partes repetidas."),
        Step(id: 3,
             systemImage: "square.and.arrow.down",
             title: "Guarda o comparte",
             detail: "Revisa las uniones si hace falta.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cómo hacerlo")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 14) {
                    IconBadge(systemName: step.systemImage, size: 44)
                        .overlay(alignment: .bottomTrailing) {
                            Text(verbatim: "\(step.id)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.indigo)
                                .frame(width: 19, height: 19)
                                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                                .overlay {
                                    Circle().strokeBorder(Theme.indigo.opacity(0.3), lineWidth: 1)
                                }
                                .offset(x: 4, y: 4)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(.system(.headline, design: .rounded))
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Paso \(step.id): \(step.title). \(step.detail)")
            }
        }
        .cardStyle()
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Overlays

/// Dimmed full-screen card shown while stitching.
private struct StitchProgressOverlay: View {
    let progress: Double

    private var percentText: String {
        let clamped = min(max(progress, 0), 1)
        return "\(Int((clamped * 100).rounded()))\u{00A0}%"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                IconBadge(systemName: "square.stack.3d.down.forward", size: 52)
                Text("Uniendo capturas…")
                    .font(.system(.headline, design: .rounded))
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(Theme.indigo)
                Text(percentText)
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 260)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// Small floating capsule shown while picked screenshots are being loaded.
private struct StitchLoadingToast: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Cargando capturas…")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}
