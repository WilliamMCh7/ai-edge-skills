import CoreGraphics
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Encodes results as PNG (lossless, keeps text crisp) and writes temporary files for sharing.
enum ImageExporter {
    enum ExportError: LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "No se pudo crear el archivo PNG."
            }
        }
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.encodingFailed
        }
        return data as Data
    }

    /// Writes into FileManager.default.temporaryDirectory/<fileName> (overwrites) and returns the URL.
    static func writeTemporaryFile(_ data: Data, fileName: String) throws -> URL {
        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "Captura" : safeName, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Errors while reading from or saving to the photo library.
enum PhotoLibraryError: LocalizedError {
    case accessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Captura Larga no tiene permiso para acceder a tus fotos. Puedes permitirlo en Ajustes."
        case .saveFailed:
            return "No se pudo guardar la imagen en Fotos. Inténtalo de nuevo."
        }
    }
}

/// Saves finished images to the photo library.
enum PhotoLibrarySaver {
    /// Requests .addOnly authorization if needed, then saves via PHAssetCreationRequest (.photo resource).
    static func savePNG(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.accessDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw PhotoLibraryError.saveFailed
        }
    }
}
