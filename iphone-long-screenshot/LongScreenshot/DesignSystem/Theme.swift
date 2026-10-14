import SwiftUI

/// Shared visual language: indigo → violet gradient accents on system grouped backgrounds,
/// rounded typography for headings, large rounded cards.
enum Theme {
    static let indigo = Color(red: 0.369, green: 0.361, blue: 0.902)   // #5E5CE6
    static let violet = Color(red: 0.749, green: 0.353, blue: 0.949)   // #BF5AF2
    static let gradient = LinearGradient(
        colors: [indigo, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let success = Color.green
    static let warning = Color.orange
    static let cornerRadius: CGFloat = 20
    static let smallCornerRadius: CGFloat = 12
}

/// Full-width gradient capsule. Use for the one main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontDesign(.rounded)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.gradient.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .shadow(color: Theme.indigo.opacity(isEnabled ? 0.35 : 0), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Full-width tinted capsule for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontDesign(.rounded)
            .foregroundStyle(Theme.indigo)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.indigo.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    /// Rounded card on the grouped background.
    func cardStyle() -> some View { modifier(CardModifier()) }
}

/// SF Symbol inside a gradient circle.
struct IconBadge: View {
    let systemName: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Small coloured capsule with an icon and text ("Uniones verificadas", "Revisa 2 uniones").
struct StatusChip: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }
}
