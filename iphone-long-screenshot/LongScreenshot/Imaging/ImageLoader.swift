import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors thrown while decoding image files.
enum ImageLoadError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "No se pudo leer la imagen. Prueba con otra captura en formato PNG, JPEG o HEIC."
        }
    }
}

/// Decodes image files into upright `SourceImage`s and makes list thumbnails.
/// Everything here works in pixels and is safe to call from any thread.
enum ImageLoader {
    /// Decodes PNG/JPEG/HEIC data, applies EXIF orientation (upright pixels), sets isLossy
    /// (true unless the UTType conforms to public.png; also true for HEIC/JPEG).
    static func sourceImage(from data: Data) throws -> SourceImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageLoadError.unreadable
        }

        let isLossy: Bool
        if let typeIdentifier = CGImageSourceGetType(source),
           let type = UTType(typeIdentifier as String) {
            isLossy = !type.conforms(to: .png)
        } else {
            isLossy = true
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let orientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0

        // Rotated/mirrored files (photos, some exports): let ImageIO apply the EXIF transform by
        // creating a full-size "thumbnail" with the transform applied.
        if orientation != 1, max(pixelWidth, pixelHeight) > 0 {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                return SourceImage(cgImage: upright, isLossy: isLossy)
            }
        }

        let decodeOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions) else {
            throw ImageLoadError.unreadable
        }
        return SourceImage(cgImage: image, isLossy: isLossy)
    }

    /// Downsampled copy for list thumbnails (longest side <= maxPixelSize).
    static func thumbnail(of image: CGImage, maxPixelSize: Int) -> CGImage {
        let longestSide = max(image.width, image.height)
        guard maxPixelSize > 0, longestSide > maxPixelSize else { return image }

        let scale = Double(maxPixelSize) / Double(longestSide)
        let width = min(maxPixelSize, max(1, Int((Double(image.width) * scale).rounded())))
        let height = min(maxPixelSize, max(1, Int((Double(image.height) * scale).rounded())))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
