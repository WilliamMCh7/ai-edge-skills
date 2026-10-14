import SwiftUI

/// The two modes of the app as tabs. Each tab's view owns its own `NavigationStack`, so results
/// are pushed inside the tab and switching tabs keeps each one's state.
@MainActor
struct RootView: View {
    /// Tab identifiers (not named `Tab` to avoid clashing with SwiftUI's `Tab` on newer SDKs).
    private enum RootTab: Hashable {
        case stitch
        case web
    }

    @State private var selection: RootTab = .stitch
    /// The web tab's model (and its single `WKWebView`), created once here rather than in
    /// `WebCaptureView`, whose struct is re-created whenever this body runs.
    @State private var webModel = WebViewModel()

    var body: some View {
        TabView(selection: $selection) {
            StitchHomeView()
                .tabItem {
                    Label("Unir", systemImage: "square.stack.3d.down.forward")
                }
                .tag(RootTab.stitch)

            WebCaptureView(model: webModel)
                .tabItem {
                    Label("Web", systemImage: "globe")
                }
                .tag(RootTab.web)
        }
        .tint(Theme.indigo)
    }
}

#Preview {
    RootView()
}
