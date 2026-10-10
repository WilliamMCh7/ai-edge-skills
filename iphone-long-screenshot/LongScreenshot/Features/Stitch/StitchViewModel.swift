import CoreGraphics
import Foundation
import Observation
import PhotosUI
import SwiftUI

/// One screenshot in the "Unir" list: the full-resolution source plus a small list thumbnail.
struct ScreenshotItem: Identifiable, @unchecked Sendable {
    let id: UUID
    let source: SourceImage
    let thumbnail: CGImage
}

extension ScreenshotItem {
    /// Wraps `source` and makes its list thumbnail (longest side 300 px). Call off the main thread.
    init(source: SourceImage) {
        self.init(id: UUID(),
                  source: source,
                  thumbnail: ImageLoader.thumbnail(of: source.cgImage, maxPixelSize: 300))
    }
}

/// State of the "Unir" tab: the ordered screenshots to stitch, loading/stitching progress, errors
/// and the finished result (pushed by `StitchHomeView`).
@Observable
@MainActor
final class StitchViewModel {
    /// Screenshots top → bottom.
    var items: [ScreenshotItem] = []
    private(set) var isStitching = false
    /// Stitching progress, 0...1.
    private(set) var progress: Double = 0
    var errorMessage: String?
    /// The finished long screenshot; non-nil pushes `ResultView`.
    var result: ResultModel?

    /// Number of load operations in flight (picker, recent screenshots, demo).
    private var loadingCount = 0
    /// Whether the current `errorMessage` comes from missing photo library access.
    private var lastErrorWasPhotoAccess = false

    /// Most screenshots the picker lets the person choose at once.
    static let maxSelectionCount = 30

    /// True while screenshots are being loaded or decoded.
    var isLoading: Bool { loadingCount > 0 }

    /// True when the shown error is missing photo access, so the alert offers "Abrir Ajustes".
    var errorIsPhotoAccess: Bool { errorMessage != nil && lastErrorWasPhotoAccess }

    /// Drives the error alert; setting it to false dismisses the error.
    var isShowingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
                lastErrorWasPhotoAccess = false
            }
        }
    }

    var canStitch: Bool { items.count >= 2 && !isStitching }

    // MARK: - Adding screenshots

    /// Loads the picked images concurrently (keeping the picker order) and appends them.
    func add(_ pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty else { return }
        loadingCount += 1
        defer { loadingCount -= 1 }

        let batch = await Task.detached(priority: .userInitiated) { () async -> StitchItemBatch in
            await PickerItemDecoding.decode(pickerItems)
        }.value

        items.append(contentsOf: batch.items)
        if batch.failures > 0 {
            if batch.items.isEmpty {
                showMessage("No se pudieron cargar las imágenes elegidas. Prueba con capturas en formato PNG, JPEG o HEIC.")
            } else if batch.failures == 1 {
                showMessage("No se pudo cargar 1 de las imágenes elegidas. Las demás se añadieron.")
            } else {
                showMessage("No se pudieron cargar \(batch.failures) de las imágenes elegidas. Las demás se añadieron.")
            }
        }
    }

    /// Appends the latest burst of screenshots from the photo library (asks for access).
    func addRecent() async {
        loadingCount += 1
        defer { loadingCount -= 1 }

        do {
            let batch = try await Task.detached(priority: .userInitiated) { () async throws -> StitchItemBatch in
                let sources = try await RecentScreenshots.latestBurst()
                return StitchItemBatch(items: sources.map { ScreenshotItem(source: $0) }, failures: 0)
            }.value

            if batch.items.isEmpty {
                showMessage("No encontramos capturas de pantalla recientes. Haz varias capturas mientras deslizas y vuelve a intentarlo.")
            } else {
                items.append(contentsOf: batch.items)
            }
        } catch {
            show(error)
        }
    }

    /// Appends the built-in demo screenshots (generated off the main thread).
    func loadDemo() {
        loadingCount += 1
        Task {
            let batch = await Task.detached(priority: .userInitiated) { () -> StitchItemBatch in
                let sources = DemoScreenshots.make()
                return StitchItemBatch(items: sources.map { ScreenshotItem(source: $0) }, failures: 0)
            }.value
            self.items.append(contentsOf: batch.items)
            self.loadingCount -= 1
        }
    }

    // MARK: - Editing the order

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    /// Moves the item with `id` one position up (towards the top of the result).
    func moveUp(_ id: ScreenshotItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return }
        items.swapAt(index, index - 1)
    }

    /// Moves the item with `id` one position down (towards the bottom of the result).
    func moveDown(_ id: ScreenshotItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), index < items.count - 1 else { return }
        items.swapAt(index, index + 1)
    }

    /// Removes the item with `id`.
    func remove(_ id: ScreenshotItem.ID) {
        items.removeAll { $0.id == id }
    }

    func reverse() {
        items.reverse()
    }

    func clear() {
        items.removeAll()
        progress = 0
    }

    // MARK: - Stitching

    /// Stitches the current items off the main thread and publishes the result.
    func stitch() async {
        guard canStitch else { return }
        let sources = items.map(\.source)
        progress = 0
        isStitching = true
        defer { isStitching = false }

        do {
            let box = try await Task.detached(priority: .userInitiated) { () throws -> StitchOutputBox in
                let output = try Stitcher.stitch(sources, progress: { value in
                    Task { @MainActor in
                        self.applyProgress(value)
                    }
                })
                return StitchOutputBox(output: output)
            }.value

            progress = 1
            result = ResultModel(stitched: box.output.image,
                                 plan: box.output.plan,
                                 sources: box.output.sources)
        } catch {
            show(error)
        }
    }

    /// Progress callbacks hop here; late or out-of-order values never move the bar backwards.
    private func applyProgress(_ value: Double) {
        guard isStitching else { return }
        progress = max(progress, min(max(value, 0), 1))
    }

    // MARK: - Errors

    private func show(_ error: Error) {
        if let photoError = error as? PhotoLibraryError, case .accessDenied = photoError {
            lastErrorWasPhotoAccess = true
        } else {
            lastErrorWasPhotoAccess = false
        }
        errorMessage = error.localizedDescription
    }

    private func showMessage(_ message: String) {
        lastErrorWasPhotoAccess = false
        errorMessage = message
    }
}

// MARK: - Background helpers

/// Items produced by a background load plus how many inputs could not be decoded.
private struct StitchItemBatch: Sendable {
    var items: [ScreenshotItem]
    var failures: Int
}

/// Carries `Stitcher.Output` (CGImage-based) back to the main actor.
private struct StitchOutputBox: @unchecked Sendable {
    let output: Stitcher.Output
}

/// Turns photo picker items into list items. Not actor-isolated: runs on background executors.
private enum PickerItemDecoding {
    /// Loads and decodes every item concurrently; the result keeps the picker order.
    static func decode(_ pickerItems: [PhotosPickerItem]) async -> StitchItemBatch {
        await withTaskGroup(of: (Int, ScreenshotItem?).self, returning: StitchItemBatch.self) { group in
            for (index, pickerItem) in pickerItems.enumerated() {
                group.addTask {
                    let item = await PickerItemDecoding.load(pickerItem)
                    return (index, item)
                }
            }

            var slots = [ScreenshotItem?](repeating: nil, count: pickerItems.count)
            for await (index, item) in group {
                slots[index] = item
            }
            let items = slots.compactMap { $0 }
            return StitchItemBatch(items: items, failures: pickerItems.count - items.count)
        }
    }

    /// Original file data of one picked image, decoded with its thumbnail. nil if it fails.
    static func load(_ pickerItem: PhotosPickerItem) async -> ScreenshotItem? {
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else { return nil }
            let source = try ImageLoader.sourceImage(from: data)
            return ScreenshotItem(source: source)
        } catch {
            return nil
        }
    }
}
