import AVFoundation
import KokoroTTS
import SwiftUI

@Observable
final class PlayerModel: @unchecked Sendable {
    var text = "Reading should feel effortless. This is Kokoro — a small neural voice running entirely on your device.\n\nNo cloud. No subscription. No tracking. Just text, turning into speech."
    var voices: [Voice] = []
    var selectedVoiceName = "af_heart"
    var speed: Double = 1.0
    var isSpeaking = false
    var status = "Loading engine…"
    var progress: Double = 0
    private(set) var currentTotalSamples = 0

    private var engine: KokoroEngine?
    private var synthesisTask: Task<Void, Never>?

    // A single audio engine lives for the whole session. Creating and tearing
    // down AVAudioEngine per utterance races with its render thread — a known
    // crash source — so we attach the player node once and only ever stop the
    // node, never the engine.
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var engineReady = false

    // Bumped on every stop/new utterance. Detached synthesis tasks capture the
    // generation they were started with; a stale result can never touch the
    // player once it has been superseded.
    private var generation = 0

    var selectedVoice: Voice? {
        voices.first { $0.name == selectedVoiceName }
    }

    func load() async {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("vendor/kokoro-multi-lang-v1_0"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Sources/KokoroDemo
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
            status = "Ready — \(engine.voices.count) voices, \(engine.sampleRate) Hz, 100% offline"
        } catch {
            status = "Failed to load engine: \(error.localizedDescription)"
        }
    }

    func speak() {
        guard let engine, let voice = selectedVoice, !text.isEmpty else { return }
        invalidateCurrentUtterance()

        let myGeneration = generation
        isSpeaking = true
        status = "Synthesizing…"
        progress = 0

        let text = text
        let speed = Float(speed)

        synthesisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result: SynthesizedAudio?
            do {
                result = try engine.synthesize(text: text, voice: voice, speed: speed)
            } catch {
                result = nil
            }
            await MainActor.run {
                guard let self, self.generation == myGeneration else { return }
                guard let result else {
                    self.isSpeaking = false
                    self.status = "Synthesis failed"
                    return
                }
                self.status = String(format: "Speaking — %.1fs of audio", result.duration)
                self.play(audio: result)
            }
        }
    }

    func stop() {
        invalidateCurrentUtterance()
        status = engine == nil ? status : "Ready — \(voices.count) voices"
    }

    /// Invalidate any in-flight synthesis and stop playback, leaving the
    /// audio engine itself running.
    private func invalidateCurrentUtterance() {
        generation &+= 1
        synthesisTask?.cancel()
        synthesisTask = nil
        playerNode.stop()
        isSpeaking = false
        progress = 0
    }

    private func play(audio: SynthesizedAudio) {
        currentTotalSamples = audio.samples.count

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audio.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            status = "Unsupported audio format"
            isSpeaking = false
            return
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audio.samples.count)
        ) else {
            status = "Could not allocate audio buffer"
            isSpeaking = false
            return
        }
        buffer.frameLength = buffer.frameCapacity
        audio.samples.withUnsafeBufferPointer { src in
            if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: audio.samples.count)
            }
        }

        if !engineReady {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            do {
                try audioEngine.start()
            } catch {
                status = "Audio engine failed: \(error.localizedDescription)"
                isSpeaking = false
                return
            }
            engineReady = true
        }

        let myGeneration = generation
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == myGeneration else { return }
                self.isSpeaking = false
                self.progress = 1
                self.status = "Finished."
            }
        }
        playerNode.play()
    }

    /// Called by the view's `Timer.publish` while speaking — rides the audio clock.
    func updateProgress(totalSamples: Int) {
        guard totalSamples > 0, playerNode.isPlaying else { return }
        if let last = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: last) {
            progress = min(1, max(0, Double(playerTime.sampleTime) / Double(totalSamples)))
        }
    }
}
