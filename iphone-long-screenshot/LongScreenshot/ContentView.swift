import SwiftUI

enum CaptureMode: String, CaseIterable {
    case web = "Captura Web"
    case stitch = "Unir Capturas"
}

struct ContentView: View {
    @State private var selectedMode: CaptureMode = .web

    var body: some View {
        TabView(selection: $selectedMode) {
            WebCaptureView()
                .tabItem {
                    Label("Captura Web", systemImage: "globe")
                }
                .tag(CaptureMode.web)

            ImageStitchView()
                .tabItem {
                    Label("Unir Capturas", systemImage: "rectangle.portrait.on.rectangle.portrait")
                }
                .tag(CaptureMode.stitch)
        }
        .tint(.blue)
    }
}
