#!/bin/bash
# One-time setup: fetch the sherpa-onnx runtime + Kokoro model into vendor/.
set -euo pipefail
cd "$(dirname "$0")/.."

SHERPA_VER=1.12.23
SHERPA_DIR="vendor/sherpa-onnx-v${SHERPA_VER}-osx-universal2-shared"
KOKORO_DIR="vendor/kokoro-multi-lang-v1_0"

# 1. sherpa-onnx macOS universal runtime (headers + dylibs)
if [ ! -d "$SHERPA_DIR" ]; then
  echo "→ downloading sherpa-onnx ${SHERPA_VER}"
  curl -sL -o vendor/sherpa-onnx-osx.tar.bz2 \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VER}/sherpa-onnx-v${SHERPA_VER}-osx-universal2-shared.tar.bz2"
  tar xjf vendor/sherpa-onnx-osx.tar.bz2 -C vendor
fi

# 2. Kokoro v1.0 multi-lang model (fp32)
if [ ! -d "$KOKORO_DIR" ]; then
  echo "→ downloading Kokoro multi-lang v1.0"
  curl -sL -o vendor/kokoro.tar.bz2 \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
  mkdir -p "$KOKORO_DIR"
  tar xjf vendor/kokoro.tar.bz2 -C "$KOKORO_DIR" --strip-components=1
fi

# 3. symlink expected by Sources/CSherpaOnnx/module.modulemap
ln -sfn "../../${SHERPA_DIR}/include/sherpa-onnx" Sources/CSherpaOnnx/sherpa-onnx

echo "✓ setup complete. Build with: swift build -c release"
