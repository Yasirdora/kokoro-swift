import SwiftUI

struct ContentView: View {
    @State private var model = PlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            editor
            Divider()
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await model.load() }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard model.isSpeaking else { return }
            model.updateProgress(totalSamples: model.currentTotalSamples)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kokoro Demo")
                    .font(.headline)
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding()
    }

    private var editor: some View {
        TextEditor(text: $model.text)
            .font(.body)
            .lineSpacing(6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .scrollContentBackground(.hidden)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .opacity(model.isSpeaking ? 1 : 0)
            HStack(spacing: 16) {
                Picker("Voice", selection: $model.selectedVoiceName) {
                    ForEach(model.voices) { voice in
                        Text(voice.name).tag(voice.name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)

                HStack(spacing: 8) {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.speed, in: 0.6...1.6, step: 0.05)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 160)

                Spacer()

                Button {
                    model.isSpeaking ? model.stop() : model.speak()
                } label: {
                    Label(model.isSpeaking ? "Stop" : "Speak",
                          systemImage: model.isSpeaking ? "stop.fill" : "play.fill")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.voices.isEmpty || model.text.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
