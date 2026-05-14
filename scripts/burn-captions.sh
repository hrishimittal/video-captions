#!/usr/bin/env bash
# burn-captions.sh VIDEO SRT [OUTPUT]
# Burns SRT into VIDEO as rounded gray "pill" captions, scaled to 1080p (1920 wide).
# Renders each caption to a PNG with Pillow, then composites via ffmpeg overlay chain.
# Requires Pillow available at ~/.cache/video-captions/venv (created by setup.sh).

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 VIDEO SRT [OUTPUT]" >&2
  exit 1
fi

VIDEO="$1"
SRT="$2"
OUTPUT="${3:-${VIDEO%.*} - captioned.mp4}"
SCALE_W="${SCALE_W:-1920}"

if [[ ! -f "$VIDEO" ]]; then echo "No such file: $VIDEO" >&2; exit 1; fi
if [[ ! -f "$SRT" ]]; then echo "No such file: $SRT" >&2; exit 1; fi
if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg not found. Run setup.sh." >&2
  exit 1
fi

VENV="$HOME/.cache/video-captions/venv"
PY="$VENV/bin/python"
if [[ ! -x "$PY" ]]; then
  echo "Caption venv missing at $VENV. Run setup.sh." >&2
  exit 1
fi

WORK=$(mktemp -d -t burn-captions)
trap '/bin/rm -rf "$WORK"' EXIT

echo "Rendering caption PNGs..."
"$PY" - "$SRT" "$WORK" "$SCALE_W" > "$WORK/graph.txt" <<'PYEOF'
import sys, re, os
from PIL import Image, ImageDraw, ImageFont

srt_path, out_dir, video_w = sys.argv[1], sys.argv[2], int(sys.argv[3])

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
FONT_SIZE = 30
PAD_X = 22
PAD_Y = 12
RADIUS = 18
BG = (50, 50, 50, 220)
FG = (255, 255, 255, 255)
MARGIN_BOTTOM = 90
MAX_W = int(video_w * 0.85)

def to_s(ts):
    h, m, rest = ts.split(":")
    s, ms = rest.split(",")
    return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000

def wrap(draw, text, font, max_w):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=font) <= max_w:
            cur = trial
        else:
            if cur: lines.append(cur)
            cur = w
    if cur: lines.append(cur)
    return lines

font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
ascent, descent = font.getmetrics()
line_h = ascent + descent

with open(srt_path) as f:
    blocks = f.read().strip().split("\n\n")

os.makedirs(out_dir, exist_ok=True)
entries = []
for i, b in enumerate(blocks):
    lines = b.split("\n")
    if len(lines) < 3: continue
    m = re.match(r"([\d:,]+) --> ([\d:,]+)", lines[1])
    if not m: continue
    start, end = to_s(m.group(1)), to_s(m.group(2))
    text = " ".join(lines[2:]).strip()
    text = re.sub(r"\s+", " ", text).lstrip(">").strip()
    if not text: continue

    wrapped = wrap(probe, text, font, MAX_W - 2*PAD_X)
    text_w = max(probe.textlength(l, font=font) for l in wrapped)
    text_h = line_h * len(wrapped)
    box_w = int(text_w) + 2*PAD_X
    box_h = int(text_h) + 2*PAD_Y

    img = Image.new("RGBA", (box_w, box_h), (0,0,0,0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([(0,0),(box_w-1,box_h-1)], radius=RADIUS, fill=BG)
    y = PAD_Y
    for l in wrapped:
        lw = probe.textlength(l, font=font)
        d.text(((box_w - lw)/2, y), l, font=font, fill=FG)
        y += line_h
    path = os.path.join(out_dir, f"cap{i:04d}.png")
    img.save(path)
    entries.append((path, start, end))

filt = f"[0:v]scale={video_w}:-2[base];"
prev = "base"
inputs = []
for idx, (path, s, e) in enumerate(entries):
    inputs.append(path)
    nxt = f"v{idx}"
    filt += f"[{prev}][{idx+1}:v]overlay=x=(W-w)/2:y=H-h-{MARGIN_BOTTOM}:enable='between(t,{s:.3f},{e:.3f})'[{nxt}];"
    prev = nxt

print("__INPUTS__")
for p in inputs: print(p)
print("__FILTER__")
print(filt.rstrip(";"))
print("__LAST__")
print(prev)
PYEOF

INPUTS=$(awk '/__INPUTS__/{flag=1;next}/__FILTER__/{flag=0}flag' "$WORK/graph.txt")
FILTER=$(awk '/__FILTER__/{flag=1;next}/__LAST__/{flag=0}flag' "$WORK/graph.txt")
LAST=$(awk '/__LAST__/{flag=1;next}flag' "$WORK/graph.txt")

INPUT_ARGS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && INPUT_ARGS+=(-i "$p")
done <<< "$INPUTS"

echo "Burning ${#INPUT_ARGS[@]} caption overlays..."
ffmpeg -y -i "$VIDEO" "${INPUT_ARGS[@]}" \
  -filter_complex "$FILTER" -map "[$LAST]" -map 0:a \
  -c:v h264_videotoolbox -b:v 6M -c:a aac -b:a 192k \
  "$OUTPUT"

echo "Wrote: $OUTPUT"
