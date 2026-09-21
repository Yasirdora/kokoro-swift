import Foundation
import KokoroTTS

// kokorocli — offline Kokoro TTS command line tool.
//
// Usage:
//   kokorocli --model <dir> [--voice af_heart] [--speed 1.0] --text "..." [--out out.wav]
//   kokorocli --model <dir> --list-voices
//   kokorocli --model <dir> --text "..." --stream   (stream chunks, same WAV out)

struct Options {
    var modelDir: String?
    var voice = "af_heart"
    var speed: Float = 1.0
    var text: String?
    var output = "output.wav"
    var listVoices = false
    var stream = false
    var stressPlay = false
}

func parseArgs() -> Options {
    var opts = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while let arg = args.first {
        args.removeFirst()
        switch arg {
        case "--model": opts.modelDir = args.first; args.removeFirst()
        case "--voice": opts.voice = args.first ?? opts.voice; args.removeFirst()
        case "--speed": opts.speed = Float(args.first ?? "1") ?? 1.0; args.removeFirst()
        case "--text": opts.text = args.first; args.removeFirst()
        case "--out": opts.output = args.first ?? opts.output; args.removeFirst()
        case "--list-voices": opts.listVoices = true
        case "--stream": opts.stream = true
        case "--stress-play": opts.stressPlay = true
        case "--help", "-h":
            print("Usage: kokorocli --model <dir> [--voice name] [--speed 1.0] --text \"...\" [--out file.wav] [--stream]")
            print("       kokorocli --model <dir> --list-voices")
            exit(0)
        default:
            FileHandle.standardError.write("Unknown argument: \(arg)\n".data(using: .utf8)!)
            exit(2)
        }
    }
    return opts
}

let opts = parseArgs()

guard let modelDir = opts.modelDir else {
    FileHandle.standardError.write("Error: --model is required\n".data(using: .utf8)!)
    exit(2)
}

let engine: KokoroEngine
do {
    let t0 = CFAbsoluteTimeGetCurrent()
    engine = try KokoroEngine(modelDirectory: URL(fileURLWithPath: modelDir))
    let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    FileHandle.standardError.write("Engine loaded in \(String(format: "%.0f", ms)) ms (\(engine.voices.count) voices, \(engine.sampleRate) Hz)\n".data(using: .utf8)!)
} catch {
    FileHandle.standardError.write("Error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}

if opts.listVoices {
    for v in engine.voices { print("\(v.id)\t\(v.name)") }
    exit(0)
}

guard let text = opts.text, !text.isEmpty else {
    FileHandle.standardError.write("Error: --text is required\n".data(using: .utf8)!)
    exit(2)
}

guard let voice = engine.voice(named: opts.voice) else {
    FileHandle.standardError.write("Error: unknown voice \"\(opts.voice)\". Use --list-voices.\n".data(using: .utf8)!)
    exit(2)
}

if opts.stream {
    // Exercises the same streaming path the app uses: chunks arrive on this
    // thread as sentences are generated.
    final class Collector: @unchecked Sendable {
        var chunks: [SynthesizedAudio] = []
    }
    let collector = Collector()
    let session = SynthesisSession()
    let t0 = CFAbsoluteTimeGetCurrent()
    engine.synthesizeStreaming(text: text, voice: voice, speed: opts.speed, session: session) { chunk in
        collector.chunks.append(chunk)
        return true
    }
    let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    let audio = SynthesizedAudio(
        samples: collector.chunks.flatMap(\.samples),
        sampleRate: engine.sampleRate
    )
    let outURL = URL(fileURLWithPath: opts.output)
    try audio.writeWAV(to: outURL)
    let realtime = audio.duration / max(ms / 1000, 0.001)
    print("Wrote \(outURL.path)")
    print("Audio: \(String(format: "%.1f", audio.duration))s in \(collector.chunks.count) chunks | synthesize: \(String(format: "%.0f", ms)) ms (\(String(format: "%.1f", realtime))x realtime)")
    exit(0)
}

if opts.stressPlay {
    // Repro of the Stop-while-marker-completion deadlocks: enqueue a short
    // "last" buffer (its completion handler takes the pipeline's lock, like
    // the app does) and call stop() at random offsets around the moment the
    // completion fires. Under the old lock-discipline this hangs reliably;
    // the watchdog below turns a regression into a loud failure.
    let audio = try engine.synthesize(text: text, voice: voice, speed: opts.speed)
    let pipeline = AudioPipeline()
    pipeline.configure(sampleRate: engine.sampleRate)
    let marker = [Float](repeating: 0, count: 2400)  // 0.1 s
    for round in 0..<200 {
        pipeline.enqueue(marker, isLast: true)
        usleep(UInt32.random(in: 60_000...160_000))
        pipeline.stop()
        if round % 50 == 0 { FileHandle.standardError.write("stress round \(round)\n".data(using: .utf8)!) }
    }
    // full-length pass so the completion path runs end to end
    final class Flag: @unchecked Sendable {
        let lock = NSLock()
        var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    let done = Flag()
    pipeline.onPlaybackFinished = { done.set() }
    pipeline.enqueue(Array(audio.samples.prefix(48000)), isLast: true)
    var waited = 0
    while !done.get() && waited < 500 {
        // Pump the run loop: the main actor (where onPlaybackFinished runs)
        // is serviced through it — a bare usleep loop would starve it.
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        waited += 1
    }
    print("stress OK: 200 stop rounds + completion fired=\(done.get())")
    exit(done.get() ? 0 : 1)
}

do {
    let t0 = CFAbsoluteTimeGetCurrent()
    let audio = try engine.synthesize(text: text, voice: voice, speed: opts.speed)
    let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000

    let outURL = URL(fileURLWithPath: opts.output)
    try audio.writeWAV(to: outURL)

    let realtime = audio.duration / max(ms / 1000, 0.001)
    print("Wrote \(outURL.path)")
    print("Audio: \(String(format: "%.1f", audio.duration))s | synthesize: \(String(format: "%.0f", ms)) ms (\(String(format: "%.1f", realtime))x realtime)")
} catch {
    FileHandle.standardError.write("Error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
