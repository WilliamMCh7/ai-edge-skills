import SwiftUI

struct ResultView: View {
    let image: UIImage
    @State private var saved = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable image preview
            ScrollView([.vertical, .horizontal]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }

            // Image info
            HStack {
                Label(
                    "\(Int(image.size.width)) x \(Int(image.size.height)) px",
                    systemImage: "ruler"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                let sizeKB = estimateFileSize(image)
                Text(sizeKB)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            // Action buttons
            VStack(spacing: 10) {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    // Save to Photos
                    Button {
                        saveToPhotos()
                    } label: {
                        Label(
                            saved ? "Guardada" : "Guardar en Fotos",
                            systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(saved ? .green : .blue)
                    .controlSize(.large)
                    .disabled(saving || saved)

                    // Share
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Resultado")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [image])
        }
    }

    private func saveToPhotos() {
        saving = true
        errorMessage = nil
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        // Small delay to give visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            saving = false
            saved = true
        }
    }

    private func estimateFileSize(_ image: UIImage) -> String {
        let pixels = Int(image.size.width * image.size.height * image.scale * image.scale)
        // Rough JPEG estimate: ~0.3 bytes per pixel at default quality
        let estimatedBytes = Double(pixels) * 0.3
        if estimatedBytes > 1_000_000 {
            return String(format: "~%.1f MB", estimatedBytes / 1_000_000)
        } else {
            return String(format: "~%.0f KB", estimatedBytes / 1_000)
        }
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
