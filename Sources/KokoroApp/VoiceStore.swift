import Foundation
import KokoroTTS

/// Curated welcome-screen voices — the ones we compared and liked.
/// The gallery still exposes all voices in the pack; this only pins the
/// featured section.
let featuredVoiceNames: [String] = [
    "af_heart", "af_bella", "am_michael", "am_onyx", "bf_emma",
]

extension Voice {
    /// "af_heart" -> locale code "a", gender code "f", stage name "Heart".
    private var nameParts: (locale: String, gender: String, stage: String) {
        let parts = name.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        let locale = parts.count > 0 ? String(parts[0].prefix(1)) : ""
        let gender = parts.count > 0 ? String(parts[0].dropFirst().prefix(1)) : ""
        let stage = parts.count > 1 ? parts[1...].joined(separator: " ") : name
        return (locale, gender, stage.capitalized)
    }

    var localeLabel: String {
        switch nameParts.locale {
        case "a": "American English"
        case "b": "British English"
        case "e": "Spanish"
        case "f": "French"
        case "h": "Hindi"
        case "i": "Italian"
        case "j": "Japanese"
        case "p": "Portuguese"
        case "z": "Chinese (Mandarin)"
        default: "Other"
        }
    }

    var genderLabel: String {
        switch nameParts.gender {
        case "f": "Female"
        case "m": "Male"
        default: ""
        }
    }

    var stageName: String { nameParts.stage }

    /// Gallery groups in display order.
    static let localeOrder: [String] = [
        "American English", "British English", "French", "Spanish", "Portuguese",
        "Italian", "Hindi", "Japanese", "Chinese (Mandarin)", "Other",
    ]
}

/// Voice catalog + engine lifecycle. Deliberately NOT @MainActor: SwiftUI
/// bindings (TextEditor, List selection) are most reliable against a plain
/// @Observable model; all mutations here happen on the main thread anyway
/// (load() is launched from `.task`, everything else from view actions).
@Observable
final class VoiceStore: @unchecked Sendable {
    private(set) var engine: KokoroEngine?
    private(set) var voices: [Voice] = []
    private(set) var featured: [Voice] = []
    var selected: Voice?
    private(set) var status = "Loading engine…"

    var isReady: Bool { engine != nil }

    func load() async {
        // The demo resolves the model relative to the package. A shipped app
        // would look in Application Support and offer a download manager.
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("vendor/kokoro-multi-lang-v1_0"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Sources/KokoroApp
                .deletingLastPathComponent()  // Sources
                .deletingLastPathComponent()  // package root
                .appendingPathComponent("vendor/kokoro-multi-lang-v1_0"),
        ]
        guard let modelDir = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("model.onnx").path)
        }) else {
            status = "Model not found. Run from the package root."
            return
        }
        do {
            let engine = try KokoroEngine(modelDirectory: modelDir)
            self.engine = engine
            self.voices = engine.voices
            self.featured = featuredVoiceNames.compactMap { engine.voice(named: $0) }
            if selected == nil { selected = featured.first ?? engine.voices.first }
            status = "Ready — \(engine.voices.count) voices, \(engine.sampleRate) Hz, 100% offline"
        } catch {
            status = "Failed to load engine: \(error.localizedDescription)"
        }
    }

    /// Grouped gallery: (locale label, voices), ordered for display.
    var gallery: [(locale: String, voices: [Voice])] {
        let grouped = Dictionary(grouping: voices, by: \.localeLabel)
        return Voice.localeOrder.compactMap { key in
            grouped[key].map { (key, $0) }
        }
    }
}
