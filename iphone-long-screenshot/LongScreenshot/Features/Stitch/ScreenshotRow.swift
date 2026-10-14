import SwiftUI

/// One screenshot in the "Unir" list: thumbnail, position and pixel size/format.
struct ScreenshotRow: View {
    let item: ScreenshotItem
    /// Position in the list (0 = top of the result).
    let index: Int

    @Environment(\.displayScale) private var displayScale

    private var formatName: String { item.source.isLossy ? "JPEG" : "PNG" }

    private var details: String {
        "\(item.source.width) × \(item.source.height) px · \(formatName)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(decorative: item.thumbnail, scale: 1)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: 56, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1 / max(displayScale, 1))
                }
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Captura \(index + 1)")
                    .font(.system(.headline, design: .rounded))
                Text(details)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Captura \(index + 1)")
        .accessibilityValue("\(item.source.width) por \(item.source.height) píxeles, \(formatName)")
    }
}
