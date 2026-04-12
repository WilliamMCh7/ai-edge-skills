import SwiftUI
import PhotosUI

struct ImageStitchView: View {
    @StateObject private var stitcher = ImageStitcherService()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Instructions
                if selectedImages.isEmpty {
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
                    // Selected images preview
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                VStack(spacing: 4) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .shadow(radius: 2)

                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 230)

                    Text("\(selectedImages.count) imagenes seleccionadas")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Reorder hint
                    Text("Las imagenes se uniran en el orden mostrado (izquierda a derecha)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

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
                        matching: .screenshots,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            selectedImages.isEmpty ? "Seleccionar Capturas" : "Cambiar Seleccion",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if !selectedImages.isEmpty {
                        Button {
                            Task {
                                await stitcher.stitchImages(selectedImages)
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
                        .disabled(selectedImages.count < 2 || stitcher.isProcessing)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Unir Capturas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !selectedImages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Limpiar") {
                            selectedImages.removeAll()
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
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        await MainActor.run {
            selectedImages = images
        }
    }
}
