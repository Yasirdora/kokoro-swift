import CSherpaOnnx
import Foundation

/// A Kokoro voice. `id` is the speaker index in the model's voices pack.
public struct Voice: Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
}

/// Mono PCM audio, samples normalized to [-1, 1].
public struct SynthesizedAudio: Sendable {
    public let samples: [Float]
    public let sampleRate: Int

    public init(samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: TimeInterval {
        Double(samples.count) / Double(sampleRate)
    }

    /// Write as 16-bit PCM WAV.
    public func writeWAV(to url: URL) throws {
        let pcm = samples.map { Int16(clamping: Int($0 * 32767)) }
        var data = Data()
        func append<T>(_ value: T) {
            withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(pcm.count * MemoryLayout<Int16>.size)
        let blockAlign = UInt16(MemoryLayout<Int16>.size)
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36) + byteCount)
        data.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16))              // PCM chunk size
        append(UInt16(1))               // PCM format
        append(UInt16(1))               // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * Int(blockAlign)))
        append(blockAlign)
        append(UInt16(16))              // bits per sample
        // data chunk
        data.append(contentsOf: "data".utf8)
        append(byteCount)
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }
}

public enum KokoroError: LocalizedError {
    case modelFileMissing(String)
    case engineCreationFailed
    case synthesisFailed
    case unknownVoice(String)

    public var errorDescription: String? {
        switch self {
        case .modelFileMissing(let name):
            "Required model file is missing: \(name)"
        case .engineCreationFailed:
            "sherpa-onnx failed to create the TTS engine (check model files)"
        case .synthesisFailed:
            "Synthesis produced no audio"
        case .unknownVoice(let name):
            "Unknown voice \"\(name)\""
        }
    }
}

/// Offline Kokoro TTS engine backed by sherpa-onnx (ONNX Runtime).
///
/// Thread-safe: synthesis calls are serialized with a lock; the underlying
/// sherpa-onnx session is used from one thread at a time.
public final class KokoroEngine: @unchecked Sendable {
    // SherpaOnnxOfflineTts is an incomplete (opaque) C type — Swift imports
    // it as OpaquePointer.
    private let tts: OpaquePointer
    private let lock = NSLock()

    public let voices: [Voice]
    public let sampleRate: Int

    /// - Parameters:
    ///   - modelDirectory: directory containing a model file (model.onnx for
    ///     fp32, or model.int8.onnx quantized), voices.bin, tokens.txt,
    ///     espeak-ng-data/, lexicon files (sherpa-onnx layout).
    ///   - modelFile: explicit model filename override; when nil, prefers the
    ///     full-precision `model.onnx` and falls back to `model.int8.onnx`.
    ///   - numThreads: ONNX Runtime intra-op threads. 4 is a good balance on
    ///     Apple Silicon; use 2 for older iPhones.
    public init(modelDirectory: URL, modelFile: String? = nil, numThreads: Int = 4) throws {
        // Model kind detection: Kokoro packs ship model.onnx/model.int8.onnx
        // plus voices.bin; Piper/vits packs ship a single named .onnx with
        // tokens.txt and espeak-ng-data only.
        let kokoroCandidates = ["model.onnx", "model.int8.onnx"]
        let resolvedModel: String
        let isVits: Bool
        if let modelFile {
            resolvedModel = modelFile
            isVits = !kokoroCandidates.contains(modelFile)
        } else if let kokoroModel = kokoroCandidates.first(where: {
            FileManager.default.fileExists(
                atPath: modelDirectory.appendingPathComponent($0).path)
        }) {
            resolvedModel = kokoroModel
            isVits = false
        } else {
            // Any other .onnx in the directory is treated as a vits/piper model.
            let files = (try? FileManager.default.contentsOfDirectory(
                atPath: modelDirectory.path)) ?? []
            guard let onnx = files.first(where: { $0.hasSuffix(".onnx") }) else {
                throw KokoroError.modelFileMissing("*.onnx")
            }
            resolvedModel = onnx
            isVits = true
        }

        func requireFile(_ name: String) throws -> String {
            let path = modelDirectory.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path) else {
                throw KokoroError.modelFileMissing(name)
            }
            return path
        }

        // C string fields (`const char *`) do not bridge from Swift String when
        // assigned to struct fields — allocate explicit C strings and free them
        // once the engine has consumed the config.
        var allocated: [UnsafeMutablePointer<CChar>] = []
        func cStr(_ s: String) -> UnsafePointer<CChar> {
            let p = strdup(s)!
            allocated.append(p)
            return UnsafePointer(p)
        }
        defer { allocated.forEach { free($0) } }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = SherpaOnnxOfflineTtsModelConfig()
        config.model.num_threads = Int32(numThreads)
        config.model.debug = 0
        config.model.provider = cStr("cpu")
        if isVits {
            config.model.vits = SherpaOnnxOfflineTtsVitsModelConfig(
                model: cStr(try requireFile(resolvedModel)),
                lexicon: cStr(""),
                tokens: cStr(try requireFile("tokens.txt")),
                data_dir: cStr(modelDirectory.appendingPathComponent("espeak-ng-data").path),
                noise_scale: 0.667,   // piper defaults
                noise_scale_w: 0.8,
                length_scale: 1.0,
                dict_dir: cStr("")
            )
        } else {
            config.model.kokoro = SherpaOnnxOfflineTtsKokoroModelConfig(
                model: cStr(try requireFile(resolvedModel)),
                voices: cStr(try requireFile("voices.bin")),
                tokens: cStr(try requireFile("tokens.txt")),
                data_dir: cStr(modelDirectory.appendingPathComponent("espeak-ng-data").path),
                length_scale: 1.0,
                dict_dir: cStr(""),
                lexicon: cStr(modelDirectory.appendingPathComponent("lexicon-us-en.txt").path),
                lang: cStr("")  // empty = lexicon-driven; espeak only for OOV fallback
            )
        }
        config.rule_fsts = nil
        config.max_num_sentences = 1
        config.rule_fars = nil
        config.silence_scale = 1.0

        guard let engine = SherpaOnnxCreateOfflineTts(&config) else {
            throw KokoroError.engineCreationFailed
        }
        tts = engine
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(engine))

        let namesFile = modelDirectory.appendingPathComponent("voices.txt")
        let names = (try? String(contentsOf: namesFile, encoding: .utf8))?
            .split(separator: "\n")
            .map(String.init) ?? []
        let count = Int(SherpaOnnxOfflineTtsNumSpeakers(engine))
        voices = (0..<count).map { i in
            Voice(id: i, name: i < names.count ? names[i] : "voice_\(i)")
        }
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    public func voice(named name: String) -> Voice? {
        voices.first { $0.name == name }
    }

    /// Synthesize `text` with audio chunks delivered as they are generated —
    /// roughly one sentence per chunk, since the engine config sets
    /// `max_num_sentences = 1`. Chunks arrive in order on the calling thread;
    /// the callback runs synchronously, so keep it fast (copy + hand off).
    ///
    /// Return `false` from `onChunk` to stop generation early.
    /// Blocks the calling thread until generation finishes or is cancelled.
    public func synthesizeStreaming(
        text: String,
        voice: Voice,
        speed: Float = 1.0,
        session: SynthesisSession,
        onChunk: @escaping @Sendable (SynthesizedAudio) -> Bool
    ) {
        lock.lock()
        defer { lock.unlock() }

        let bridge = StreamBridge(sampleRate: sampleRate, session: session, onChunk: onChunk)
        let arg = Unmanaged.passRetained(bridge).toOpaque()
        defer { Unmanaged<StreamBridge>.fromOpaque(arg).release() }

        text.withCString { cText in
            _ = SherpaOnnxOfflineTtsGenerateWithCallbackWithArg(
                tts, cText, Int32(voice.id), speed, streamCallback, arg
            )
        }
    }

    /// Synthesize `text` fully in memory. For long-form reading, synthesize
    /// per-sentence and stream — see `synthesizeStreaming`.
    @discardableResult
    public func synthesize(
        text: String,
        voice: Voice,
        speed: Float = 1.0
    ) throws -> SynthesizedAudio {
        lock.lock()
        defer { lock.unlock() }

        guard let generated = SherpaOnnxOfflineTtsGenerate(tts, text, Int32(voice.id), speed)
        else {
            throw KokoroError.synthesisFailed
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(generated) }

        let n = Int(generated.pointee.n)
        guard n > 0 else {
            throw KokoroError.synthesisFailed
        }
        let samples = Array(
            UnsafeBufferPointer(start: generated.pointee.samples, count: n)
        )
        return SynthesizedAudio(samples: samples, sampleRate: sampleRate)
    }
}

// MARK: - Streaming support

/// Cancellation token for a streaming synthesis. Set `isCancelled` from any
/// thread; the next chunk callback returns 0 to sherpa-onnx, which stops
/// generation at a sentence boundary.
public final class SynthesisSession: @unchecked Sendable {
    public private(set) var isCancelled = false
    public func cancel() { isCancelled = true }
    public init() {}
}

/// Bridges the C chunk callback into Swift. Retained for the duration of one
/// `synthesizeStreaming` call via Unmanaged.
private final class StreamBridge {
    let sampleRate: Int
    let onChunk: (SynthesizedAudio) -> Bool
    let session: SynthesisSession
    init(sampleRate: Int, session: SynthesisSession, onChunk: @escaping (SynthesizedAudio) -> Bool) {
        self.sampleRate = sampleRate
        self.session = session
        self.onChunk = onChunk
    }
}

private let streamCallback: @convention(c) (UnsafePointer<Float>?, Int32, UnsafeMutableRawPointer?) -> Int32 = {
    samples, n, arg in
    guard let arg, let samples, n > 0 else { return 0 }
    let bridge = Unmanaged<StreamBridge>.fromOpaque(arg).takeUnretainedValue()
    guard !bridge.session.isCancelled else { return 0 }
    let chunk = SynthesizedAudio(
        samples: Array(UnsafeBufferPointer(start: samples, count: Int(n))),
        sampleRate: bridge.sampleRate
    )
    return bridge.onChunk(chunk) ? 1 : 0
}
