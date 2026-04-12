import SwiftUI
import PhotosUI

struct StitchableImage: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: StitchableImage, rhs: StitchableImage) -> Bool {
        lhs.id == rhs.id
    }
}

struct ImageStitchView: View {
    @StateObject private var stitcher = ImageStitcherService()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [StitchableImage] = []
    @State private var showResult = false
    @State private var draggingItem: StitchableImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Instructions
                if images.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue.opacity(0.6))
                        Text("Selecciona varias capturas de pantalla\npara unirlas en una imagen larga")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    // Reorderable images
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                                VStack(spacing: 4) {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .shadow(radius: 2)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(draggingItem?.id == item.id ? Color.blue : Color.clear, lineWidth: 2))
                                        .opacity(draggingItem?.id == item.id ? 0.5 : 1.0)
                                        .draggable(item.id.uuidString) {
                                            Image(uiImage: item.image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .shadow(radius: 4)
                                                .onAppear { draggingItem = item }
                                        }
                                        .dropDestination(for: String.self) { droppedIDs, _ in
                                            guard let droppedID = droppedIDs.first,
                                                  let fromIndex = images.firstIndex(where: { $0.id.uuidString == droppedID }),
                                                  let toIndex = images.firstIndex(where: { $0.id == item.id }),
                                                  fromIndex != toIndex else {
                                                return false
                                            }
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                let moved = images.remove(at: fromIndex)
                                                images.insert(moved, at: toIndex)
                                            }
                                            draggingItem = nil
                                            return true
                                        }

                                    // Number badge + move buttons
                                    HStack(spacing: 8) {
                                        Button {
                                            guard index > 0 else { return }
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                images.swapAt(index, index - 1)
                                            }
                                        } label: {
                                            Image(systemName: "chevron.left")
                                                .font(.caption2)
                                        }
                                        .disabled(index == 0)

                                        Text("\(index + 1)")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .monospacedDigit()
                                            .frame(minWidth: 16)

                                        Button {
                                            guard index < images.count - 1 else { return }
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                images.swapAt(index, index + 1)
                                            }
                                        } label: {
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                        }
                                        .disabled(index == images.count - 1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 240)

                    Text("\(images.count) imagenes · Arrastra o usa las flechas para reordenar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // Action buttons
                VStack(spacing: 12) {
                    if stitcher.isProcessing {
                        ProgressView(stitcher.progress)
                    }

                    if let error = stitcher.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 20,
                        matching: .any(of: [.screenshots, .images]),
                        photoLibrary: .shared()
                    ) {
                        Label(
                            images.isEmpty ? "Seleccionar Capturas" : "Cambiar Seleccion",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if !images.isEmpty {
                        Button {
                            Task {
                                await stitcher.stitchImages(images.map(\.image))
                                if stitcher.resultImage != nil {
                                    showResult = true
                                }
                            }
                        } label: {
                            Label("Unir Imagenes", systemImage: "arrow.up.and.down.and.sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(images.count < 2 || stitcher.isProcessing)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Unir Capturas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !images.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Limpiar") {
                            images.removeAll()
                            selectedItems.removeAll()
                        }
                    }
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await loadImages(from: newItems)
                }
            }
            .navigationDestination(isPresented: $showResult) {
                if let image = stitcher.resultImage {
                    ResultView(image: image)
                }
            }
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [StitchableImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(StitchableImage(image: image))
            }
        }
        await MainActor.run {
            images = loaded
        }
    }
}
