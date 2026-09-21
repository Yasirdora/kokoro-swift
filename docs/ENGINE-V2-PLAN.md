# Kokoro Engine v2 — Prior-Art Study & Architecture Decision

Date: 2026-09-21 · Status: APPROVED for implementation
Objective: the most effective, efficient Apple-native TTS engine — meets Apple standards, then surpasses them.

## 1. Comparison Matrix (from source inspection + published benchmarks)

| Area | Official Kokoro (hexgrad) | kokoro-ios (mlalma) | kokoro-swift (mweinbach) | kokoro-coreml (mattmireles) | FluidAudio | **Our baseline** (sherpa-onnx) |
|---|---|---|---|---|---|---|
| Runtime | Python | Swift | Swift | Swift (+Python export) | Swift (binary targets) | Swift + C API |
| Backend | PyTorch | MLX-Swift | MLX **+** CoreML ANE | CoreML ANE (5 submodels) | CoreML | ONNX Runtime |
| Python at runtime | Yes | No | No | No | No | No |
| ANE use | No | No | Yes (segmented) | Yes (segmented, mask-aware) | Yes | No |
| Native Swift G2P | No (espeak/misaki-py) | MisakiSwift | Misaki (vendored) | MisakiSwift (vendored) | ? | No (espeak-ng, GPL linking exception) |
| Streaming | Chunked generator | No | No | No | ? | Yes (sentence chunks) |
| Measured speed | — | 3.3× RT (iPhone 13 Pro, warm) | Not published | **14× RT M1 Mini · 70× RT M2 Ultra** | Not published | 9× RT (M-series, fp32 CLI) |
| Model size | ~350 MB fp32 | MLX fp16/bf16 | MLX + CoreML pkgs | CoreML segmented pkgs | Binary | fp32 / int8 ONNX |
| License | Apache 2.0 | MIT | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache/MIT + **espeak GPL-exception** |
| Maturity | Reference | Stable (1.0.8) | Early (0.1.x), 0 open issues | Research, active | 2.7k★, prod apps | **Proven in our app** |
| iOS | — | iOS 18+ | macOS 14+ (iOS path) | ios-bench included | iOS | Same C API works |

Newer-work sweep: FluidAudio (FluidInference) is the significant find the original brief missed — production CoreML audio suite, Kokoro TTS with SSML across 9 languages, but **binary-only targets** (no auditable source, no modification possible). Disqualified as a core dependency for that reason; kept as API-design reference.

## 2. What each project does well / poorly

- **hexgrad/kokoro** — canonical fidelity reference. Apache 2.0. All ports must match its output.
- **mlalma/kokoro-ios** — faithful MLX-Swift execution; *only* 3.3× RT on iPhone 13 Pro (GPU path, no ANE). Best used as numerical oracle.
- **mweinbach/kokoro-swift** — best *architecture*: one package, dual backend (MLX GPU + segmented CoreML ANE), vendored Misaki G2P (kills the espeak GPL problem), on-demand voice downloads. Weakness: early, unverified, no published benchmarks.
- **mattmireles/kokoro-coreml** — best *performance evidence*: mask-aware bucketing, ANE segmentation, reproduced-on-hardware numbers (14× M1 Mini). Weakness: research-grade packaging, G2P not its focus, several perf-level open issues.
- **Our sherpa baseline** — proven, streaming, multi-engine (Piper German). Weakness: C dylibs in bundle, no ANE, espeak dependency, fp32 model heavier than needed.

## 3. Decision — "Surpass" Architecture

**Do not fork or rewrite. Compose.** SPM-depend on `mweinbach/kokoro-swift` (Apache 2.0) as the v2 engine core, wrap it behind our existing engine interface, and keep our sherpa engine as:

1. **Correctness oracle** — v2 output must match sherpa/official output (same text+voice → sample-level A/B).
2. **Fallback backend** — if ANE/CoreML fails on a device, degrade to proven ONNX.

```
KokoroApp / kokorocli
   └── EngineRouter (new)
         ├── KokoroANEEngine  ──▶ Kokoro package (Misaki G2P → SegmentedCoreML ANE)
         │                         MLX backend retained as validation oracle
         ├── KokoroOnnxEngine ──▶ existing sherpa path (fallback + oracle)
         └── VitsPiperEngine  ──▶ existing German/multi-language packs
```

**Why this surpasses Apple-grade:**
- Pure Swift + ANE = the same silicon class as on-device Siri; lower power than our GPU/CPU ONNX path.
- Native Misaki G2P removes the last GPL/espeak entanglement → App Store-clean.
- On-demand voice packs → small app, downloadable voices (our README roadmap item #3 ✅).
- Streaming sentence pipeline we already built rides on top unchanged.
- Every claim gets reproduced on real hardware before it becomes a design assumption (the brief's rule).

## 4. Implementation & Validation Gates

- G1: depend, build, synthesize one utterance via ANE backend → audio non-silent, matches oracle (correlation ≥ 0.99 after alignment).
- G2: RTF benchmark (this Mac) — target ≥ our 9× baseline; cold vs warm latency recorded.
- G3: streaming integration + voice download manager.
- G4: iPhone device benchmark (M-series + one older device).

## 5. Risks

- mweinbach maturity → mitigated by G1 oracle check + sherpa fallback always present.
- ANE fixed-shape limits on long utterances → bucketing handled inside dependency; verified at G2.
- Binary-only FluidAudio avoided deliberately.
