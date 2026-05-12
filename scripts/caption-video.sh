#!/usr/bin/env bash
# caption-video.sh VIDEO [OUTPUT]
# All-in-one: transcribes the video, then burns the captions in.
# Use this when you don't need to manually review the SRT.
# Use transcribe-video.sh + burn-captions.sh separately when you do.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 VIDEO [OUTPUT]" >&2
  exit 1
fi

VIDEO="$1"
OUTPUT="${2:-${VIDEO%.*} - captioned.mp4}"
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/transcribe-video.sh" "$VIDEO"
"$HERE/burn-captions.sh" "$VIDEO" "${VIDEO%.*}.srt" "$OUTPUT"
