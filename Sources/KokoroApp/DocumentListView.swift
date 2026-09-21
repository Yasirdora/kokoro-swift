import SwiftUI

struct DocumentListView: View {
    @Environment(DocumentStore.self) private var docs
    @State private var renaming: Document.ID?
    @State private var renameText = ""

    var body: some View {
        @Bindable var docs = docs
        List(selection: $docs.selected) {
            ForEach(docs.documents) { doc in
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.name)
                        .font(.body)
                    Text(preview(of: doc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(doc.id)
                .contextMenu {
                    Button("Rename…") {
                        renameText = doc.name
                        renaming = doc.id
                    }
                    Button("Delete", role: .destructive) {
                        docs.delete(doc.id)
                    }
                }
            }
        }
        .overlay {
            if docs.documents.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc",
                    description: Text("Use the + button above to create one.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    docs.createDocument()
                } label: {
                    Label("New Document", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Documents")
        .alert("Rename Document", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renaming { docs.rename(id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func preview(of doc: Document) -> String {
        let trimmed = doc.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty" : trimmed.prefix(60).description
    }
}
