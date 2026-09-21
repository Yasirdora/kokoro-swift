import Foundation
import Kokoro

// kokoroane — v2 engine prototype: Segmented CoreML ANE backend.
// Usage: kokoroane <modelRoot> <voice> <out.wav> [text...]
let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: kokoroane <modelRoot> <voice> <out.wav> [text...]\n".utf8))
    exit(1)
}
let root = URL(fileURLWithPath: args[1], isDirectory: true)
let voice = args[2]
let outURL = URL(fileURLWithPath: args[3])
let text = args.count > 4 ? args[4...].joined(separator: " ")
    : "Reading should feel effortless. This is Kokoro running on the Apple Neural Engine."

let t0 = Date()
let model = try SegmentedCoreMLModel(
    segmentedDir: root.appendingPathComponent("CoreML_ANE/segmented"),
    configURL: root.appendingPathComponent("MLX_GPU/config.json")
)
let voices = VoiceLoader(
    baseDirectory: root.appendingPathComponent("MLX_GPU/voices"),
    enableDownload: false
)
let pipeline = KPipeline(coreMLSegmentedModel: model, voices: voices)
let tLoad = Date().timeIntervalSince(t0)

let t1 = Date()
let result = try pipeline.synthesize(text: text, voice: voice)
let tGen = Date().timeIntervalSince(t1)

try AudioWriter.writeWAV(samples: result.audio, to: outURL, sampleRate: 24_000)
let dur = Double(result.audio.count) / 24_000.0
print("kokoroane (ANE): load \(String(format: "%.2f", tLoad))s | " +
      "gen \(String(format: "%.2f", tGen))s | audio \(String(format: "%.2f", dur))s | " +
      "RTF \(String(format: "%.2f", tGen / dur))x")
print("wrote \(outURL.path)")
