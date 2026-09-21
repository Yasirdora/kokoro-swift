import SwiftUI

@main
struct KokoroDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 560, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 600)
    }
}
