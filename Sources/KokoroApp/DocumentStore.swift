import Foundation

struct Document: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var text: String
    var modified: Date = Date()
}

/// Document library for the sidebar: an in-memory list backed by one JSON
/// file in Application Support. Text edits are debounce-autosaved; structural
/// changes (create/rename/delete) save immediately.
@Observable
final class DocumentStore: @unchecked Sendable {
    var documents: [Document] = []
    var selected: Document.ID?

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KokoroApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("documents.json")
        load()
    }

    var selectedDocument: Document? {
        documents.first { $0.id == selected }
    }

    // MARK: - Load / save

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let docs = try? JSONDecoder().decode([Document].self, from: data)
        else {
            // First run: a welcoming starter document.
            let welcome = Document(
                name: "Welcome",
                text: """
                Reading should feel effortless. This is Kokoro — a small neural voice running entirely on your device.

                No cloud. No subscription. No tracking. Just text, turning into speech. Pick a voice in the menu on the right, press Speak, and the first sentence starts almost immediately while the rest synthesizes in the background.
                """
            )
            documents = [welcome]
            selected = welcome.id
            saveNow()
            return
        }
        documents = docs.sorted { $0.modified > $1.modified }
        selected = documents.first?.id
    }

    private func saveNow() {
        saveTask?.cancel()
        do {
            let data = try JSONEncoder().encode(documents)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Storage failures are non-fatal for the demo; documents still
            // live in memory for the session.
        }
    }

    /// Debounced autosave for text edits (fires 0.4 s after typing stops).
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.saveNow() }
        }
    }

    // MARK: - Mutations

    @discardableResult
    func createDocument() -> Document {
        var n = documents.count + 1
        while documents.contains(where: { $0.name == "Untitled \(n)" }) { n += 1 }
        let doc = Document(name: "Untitled \(n)", text: "")
        documents.insert(doc, at: 0)
        selected = doc.id
        saveNow()
        return doc
    }

    func delete(_ id: Document.ID) {
        documents.removeAll { $0.id == id }
        if selected == id { selected = documents.first?.id }
        saveNow()
    }

    func rename(_ id: Document.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[i].name = trimmed
        documents[i].modified = Date()
        saveNow()
    }

    func updateText(_ id: Document.ID, to text: String) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[i].text = text
        documents[i].modified = Date()
        scheduleSave()
    }
}
