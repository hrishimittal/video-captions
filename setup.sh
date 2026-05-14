#!/usr/bin/env bash
# setup.sh
# One-time setup: installs ffmpeg + whisper.cpp via Homebrew, downloads the medium.en GGML model,
# and symlinks scripts into ~/bin.

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This setup script targets macOS. ffmpeg + whisper.cpp will work elsewhere, but install them manually." >&2
  exit 1
fi

if ! command -v brew >/dev/null; then
  echo "Homebrew not found. Install from https://brew.sh and re-run." >&2
  exit 1
fi

echo "Installing ffmpeg and whisper-cpp via Homebrew..."
brew install ffmpeg whisper-cpp

MODEL_DIR="${HOME}/models/whisper-cpp"
MODEL="${MODEL_DIR}/ggml-medium.en.bin"
if [[ ! -f "$MODEL" ]]; then
  echo "Downloading medium.en GGML model (~1.5GB)..."
  /bin/mkdir -p "$MODEL_DIR"
  curl -L --fail -o "$MODEL" \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin
else
  echo "Model already present: $MODEL"
fi

VENV="${HOME}/.cache/video-captions/venv"
if [[ ! -x "${VENV}/bin/python" ]]; then
  echo "Creating Python venv with Pillow at ${VENV}..."
  /bin/mkdir -p "$(dirname "$VENV")"
  python3 -m venv "$VENV"
  "${VENV}/bin/pip" install --quiet Pillow
else
  echo "Caption venv already present: $VENV"
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
/bin/mkdir -p "${HOME}/bin"
for s in transcribe-video.sh burn-captions.sh caption-video.sh; do
  /bin/ln -sf "${HERE}/scripts/${s}" "${HOME}/bin/${s}"
  /bin/chmod +x "${HERE}/scripts/${s}"
done

echo
echo "Done."
echo "If ~/bin is not on your PATH, add this line to your shell rc:"
echo "  export PATH=\"\$HOME/bin:\$PATH\""
