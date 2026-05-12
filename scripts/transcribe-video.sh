#!/usr/bin/env bash
# transcribe-video.sh VIDEO
# Extracts audio from VIDEO and transcribes it with whisper.cpp (medium.en, Metal-accelerated).
# Writes <VIDEO basename>.srt next to the input.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 VIDEO" >&2
  exit 1
fi

VIDEO="$1"
MODEL="${WHISPER_MODEL:-${HOME}/models/whisper-cpp/ggml-medium.en.bin}"
BASE="${VIDEO%.*}"
SRT="${BASE}.srt"

if [[ ! -f "$VIDEO" ]]; then echo "No such file: $VIDEO" >&2; exit 1; fi
if [[ ! -f "$MODEL" ]]; then
  echo "Missing whisper model: $MODEL" >&2
  echo "Run setup.sh to download it." >&2
  exit 1
fi
if ! command -v whisper-cli >/dev/null; then
  echo "whisper-cli not found. Run setup.sh." >&2
  exit 1
fi

WAV="$(mktemp -t whisper).wav"
trap '/bin/rm -f "$WAV"' EXIT

echo "Extracting audio..."
ffmpeg -y -i "$VIDEO" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$WAV" >/dev/null 2>&1

echo "Transcribing with whisper.cpp medium.en..."
whisper-cli -m "$MODEL" -f "$WAV" -l en -osrt -of "$BASE" >/dev/null

echo "Wrote: $SRT"
