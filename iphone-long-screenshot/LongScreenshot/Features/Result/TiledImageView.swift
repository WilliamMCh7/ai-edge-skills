import CoreGraphics
import SwiftUI
import UIKit

/// Shows a very tall `CGImage` as a vertical stack of horizontal tiles, each at most
/// `maxTileHeight` pixels tall, so no single texture exceeds GPU limits and only the visible tiles
/// are drawn. Optionally overlays a dashed line with a numbered capsule at every seam.
struct TiledImageView: View {
    let image: CGImage
    let markers: [ResultModel.SeamMarker]
    let showMarkers: Bool

    /// Tallest tile in pixels.
    static let maxTileHeight = 1024

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Self.tiles(of: image)) { tile in
                ImageTileView(tile: tile, markers: showMarkers ? markersInside(tile) : [])
            }
        }
    }

    /// Markers whose row falls inside `tile`.
    private func markersInside(_ tile: ImageTile) -> [ResultModel.SeamMarker] {
        markers.filter { $0.y >= tile.top && $0.y < tile.top + tile.height }
    }

    /// Splits the image into equal-height tiles (<= `maxTileHeight` rows each, so the last one is
    /// never a sliver). `cropping(to:)` only references the parent's pixels, so this is cheap.
    private static func tiles(of image: CGImage) -> [ImageTile] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }
        let count = (height + maxTileHeight - 1) / maxTileHeight
        let tileHeight = max(1, (height + count - 1) / count)

        var tiles: [ImageTile] = []
        tiles.reserveCapacity(count)
        var top = 0
        while top < height {
            let rows = min(tileHeight, height - top)
            let rect = CGRect(x: 0, y: top, width: width, height: rows)
            tiles.append(ImageTile(id: tiles.count, top: top, height: rows, width: width,
                                   image: image.cropping(to: rect)))
            top += rows
        }
        return tiles
    }
}

/// One horizontal slice of the full image, identified by its index.
private struct ImageTile: Identifiable {
    let id: Int
    /// First pixel row of the slice in the full image.
    let top: Int
    /// Pixel rows in the slice.
    let height: Int
    /// Pixel width of the full image.
    let width: Int
    let image: CGImage?
}

/// Draws one tile, fitted to the available width, plus the markers that fall inside it.
private struct ImageTileView: View {
    let tile: ImageTile
    let markers: [ResultModel.SeamMarker]

    var body: some View {
        tileImage
            .overlay {
                if !markers.isEmpty {
                    GeometryReader { proxy in
                        markerLayer(size: proxy.size)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private var tileImage: some View {
        if let image = tile.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(Color(.secondarySystemFill))
                .aspectRatio(CGSize(width: tile.width, height: tile.height), contentMode: .fit)
        }
    }

    private func markerLayer(size: CGSize) -> some View {
        let scale = tile.height > 0 ? size.height / CGFloat(tile.height) : 0
        return ZStack(alignment: .topLeading) {
            ForEach(markers) { marker in
                SeamMarkerLine(
                    number: marker.id + 1,
                    color: marker.kind == .matched ? Theme.indigo : Theme.warning,
                    y: CGFloat(marker.y - tile.top) * scale,
                    size: size
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Dashed full-width line at `y` with a small numbered capsule on the leading side. The capsule is
/// kept inside the tile so the next tile never covers it.
private struct SeamMarkerLine: View {
    let number: Int
    let color: Color
    let y: CGFloat
    let size: CGSize

    private var badgeHeight: CGFloat { 20 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            linePath
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            linePath
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5]))

            Text(verbatim: String(number))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .frame(minWidth: 24, minHeight: badgeHeight, maxHeight: badgeHeight)
                .background(color, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(x: 8, y: badgeTop)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var linePath: Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
    }

    private var badgeTop: CGFloat {
        let centered = y - badgeHeight / 2
        return max(0, min(centered, size.height - badgeHeight))
    }
}
