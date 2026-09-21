import Foundation
import KokoroTTS
import SwiftUI

/// Long-form reading pipeline: streams sentence chunks from the engine and
/// feeds the audio pipeline, so playback starts with the first sentence
/// instead of waiting for the whole text.
///
/// Plain @Observable (not @MainActor): SwiftUI bindings behave most
/// predictably against nonisolated observable models; state is only ever
/// touched from the main actor (view actions) or via `MainActor.run`.
@Observable
final class ReaderViewModel: @unchecked Sendable {
    var speed: Double = 1.0
    var isSpeaking = false
    var status = "Pick a voice, then press Speak."
    var progress: Double = 0
    var playedText = "0:00"
    var totalText = "0:00"

    @ObservationIgnored private let pipeline = AudioPipeline()
    @ObservationIgnored private var synthesisTask: Task<Void, Never>?
    @ObservationIgnored private var session: SynthesisSession?
    @ObservationIgnored private var progressTimer: Timer?

    init() {
        pipeline.onPlaybackFinished = { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.progress = 1
            self.status = "Finished."
            self.stopTimer()
        }
    }

    func speak(engine: KokoroEngine, voice: Voice, text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        stop()

        pipeline.configure(sampleRate: engine.sampleRate)
        isSpeaking = true
        progress = 0
        status = "Synthesizing…"
        startTimer()

        let session = SynthesisSession()
        self.session = session
        let speed = Float(speed)

        synthesisTask = Task.detached(priority: .userInitiated) { [pipeline] in
            engine.synthesizeStreaming(text: body, voice: voice, speed: speed, session: session) { chunk in
                pipeline.enqueue(chunk.samples, isLast: false)
                return true
            }
            // Every sentence (including the last) arrives via the callback.
            // Queue a short silent marker so the completion handler fires
            // after all real audio has played.
            pipeline.enqueue([Float](repeating: 0, count: 2400), isLast: true)
        }
    }

    func stop() {
        session?.cancel()
        session = nil
        synthesisTask?.cancel()
        synthesisTask = nil
        pipeline.stop()
        isSpeaking = false
        progress = 0
        stopTimer()
    }

    // MARK: - Progress

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isSpeaking else { return }
                guard let p = self.pipeline.progress() else { return }
                self.progress = p.scheduled > 0 ? min(1, p.played / p.scheduled) : 0
                self.playedText = Self.format(p.played)
                self.totalText = Self.format(p.scheduled)
                if p.played > 0.2 {
                    self.status = "Speaking"
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        playedText = "0:00"
        totalText = "0:00"
    }

    private static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
