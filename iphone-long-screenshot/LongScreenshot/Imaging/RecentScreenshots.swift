import Foundation
import Photos

/// Finds the screenshots the person just took (the "burst" made while scrolling another app).
enum RecentScreenshots {
    /// Asks for .readWrite photo access; fetches the newest screenshots (smart album
    /// .smartAlbumScreenshots, creationDate desc) and returns the most recent "burst": the newest one plus
    /// older ones while each gap between consecutive creation dates is <= maxGap seconds and pixel size
    /// matches, up to maxCount. Returned oldest → newest (top → bottom). Throws PhotoLibraryError.accessDenied.
    static func latestBurst(maxCount: Int = 20, maxGap: TimeInterval = 180) async throws -> [SourceImage] {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.accessDenied
        }

        let limit = max(1, maxCount)
        let burst = newestBurst(limit: limit, maxGap: maxGap)

        var images: [SourceImage] = []
        images.reserveCapacity(burst.count)
        for asset in burst {
            let data = try await imageData(for: asset)
            images.append(try ImageLoader.sourceImage(from: data))
        }
        return images
    }

    /// Newest screenshots grouped into the latest burst, oldest first.
    private static func newestBurst(limit: Int, maxGap: TimeInterval) -> [PHAsset] {
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        guard let album = albums.firstObject else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit * 2
        let result = PHAsset.fetchAssets(in: album, options: options)
        guard result.count > 0 else { return [] }

        let newest = result.object(at: 0)
        var burst: [PHAsset] = [newest]
        var previous = newest
        var index = 1
        while index < result.count, burst.count < limit {
            let asset = result.object(at: index)
            guard let previousDate = previous.creationDate,
                  let date = asset.creationDate,
                  previousDate.timeIntervalSince(date) <= maxGap,
                  asset.pixelWidth == newest.pixelWidth,
                  asset.pixelHeight == newest.pixelHeight else {
                break
            }
            burst.append(asset)
            previous = asset
            index += 1
        }
        return Array(burst.reversed())
    }

    /// Original file data of one asset (downloads it from iCloud if needed).
    private static func imageData(for asset: PHAsset) async throws -> Data {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce()
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                // Photos calls this once with the final data (or nil on failure); the guard makes
                // sure an unexpected second call can never resume the continuation again.
                guard once.claim() else { return }
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ImageLoadError.unreadable)
                }
            }
        }
    }
}

/// Thread-safe flag guaranteeing a continuation is resumed exactly once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True the first time it is called, false afterwards.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
