import SwiftUI
import UIKit

/// Entry point of Captura Larga. UI tests launch the app with `-UITests` to turn off animations,
/// which makes their waits and screenshots deterministic.
@main
@MainActor
struct LongScreenshotApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("-UITests") {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
