import SwiftUI

@main
struct KokoroApp: App {
    @State private var store = VoiceStore()
    @State private var docs = DocumentStore()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                DocumentListView()
                    .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
            } detail: {
                ReaderView()
            }
            .environment(store)
            .environment(docs)
            .task { await store.load() }
            .frame(minWidth: 760, minHeight: 480)
        }
    }
}
