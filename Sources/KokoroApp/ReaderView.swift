import KokoroTTS
import SwiftUI

struct ReaderView: View {
    @Environment(VoiceStore.self) private var store
    @Environment(DocumentStore.self) private var docs
    @State private var reader = ReaderViewModel()

    private var documentBinding: Binding<String> {
        Binding(
            get: { docs.selectedDocument?.text ?? "" },
            set: { newValue in
                if let id = docs.selected { docs.updateText(id, to: newValue) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            transport
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar { voicePicker }
        .navigationTitle(docs.selectedDocument?.name ?? "Kokoro")
    }

    // MARK: - Voice picker (window toolbar, top right)

    @ToolbarContentBuilder
    private var voicePicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Voice", selection: Bindable(store).selected) {
                if !store.featured.isEmpty {
                    Section("Featured") {
                        ForEach(store.featured) { voice in
                            Text(voice.name).tag(Optional(voice))
                        }
                    }
                }
                ForEach(store.gallery, id: \.locale) { group in
                    Section(group.locale) {
                        ForEach(group.voices) { voice in
                            Text(voice.name).tag(Optional(voice))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 190)
            .disabled(!store.isReady)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selected?.name ?? "No voice selected")
                    .font(.headline)
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Text editor

    private var editor: some View {
        TextEditorView(text: documentBinding)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .disabled(docs.selectedDocument == nil)
    }

    // MARK: - Transport

    private var transport: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(reader.playedText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressView(value: reader.progress)
                    .progressViewStyle(.linear)
                Text(reader.totalText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $reader.speed, in: 0.6...1.6, step: 0.05)
                        .frame(maxWidth: 160)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.2f×", reader.speed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                Spacer()

                Button {
                    if reader.isSpeaking {
                        reader.stop()
                    } else if let engine = store.engine, let voice = store.selected {
                        reader.speak(engine: engine, voice: voice,
                                     text: docs.selectedDocument?.text ?? "")
                    }
                } label: {
                    Label(
                        reader.isSpeaking ? "Stop" : "Speak",
                        systemImage: reader.isSpeaking ? "stop.fill" : "play.fill"
                    )
                    .frame(minWidth: 96)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isReady || store.selected == nil
                          || (docs.selectedDocument?.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
