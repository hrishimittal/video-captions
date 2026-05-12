#!/usr/bin/env bash
# burn-captions.sh VIDEO SRT [OUTPUT]
# Burns SRT into VIDEO using a YouTube-style caption box, scaled to 1080p, 60fps preserved.
# Splits into PARALLEL=6 segments and runs ffmpeg in parallel for speed.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 VIDEO SRT [OUTPUT]" >&2
  exit 1
fi

VIDEO="$1"
SRT="$2"
OUTPUT="${3:-${VIDEO%.*} - captioned.mp4}"
PARALLEL="${PARALLEL:-6}"

if [[ ! -f "$VIDEO" ]]; then echo "No such file: $VIDEO" >&2; exit 1; fi
if [[ ! -f "$SRT" ]]; then echo "No such file: $SRT" >&2; exit 1; fi
if ! command -v ffmpeg >/dev/null; then
  echo "ffmpeg not found. Run setup.sh." >&2
  exit 1
fi

STYLE='Fontname=Helvetica,Fontsize=18,Bold=1,PrimaryColour=&H00FFFFFF,BackColour=&HCC000000,BorderStyle=3,Outline=4,Shadow=0,Alignment=2,MarginV=60'

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
WORK=$(mktemp -d -t burn-captions)
trap '/bin/rm -rf "$WORK"' EXIT

echo "Duration ${DUR}s, splitting into ${PARALLEL} parallel segments..."

SEG_LEN=$(python3 -c "print($DUR / $PARALLEL)")

# Trim SRT for each segment (shifted to start at 0)
python3 - "$SRT" "$WORK" "$PARALLEL" "$SEG_LEN" <<'PYEOF'
import sys, re, os
srt_path, work_dir, n, seg_len = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
def to_s(ts):
    h, m, rest = ts.split(":")
    s, ms = rest.split(",")
    return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000
def to_ts(s):
    if s < 0: s = 0
    h = int(s // 3600); m = int((s % 3600) // 60); sec = s - h*3600 - m*60
    return f"{h:02d}:{m:02d}:{int(sec):02d},{int(round((sec - int(sec))*1000)):03d}"
with open(srt_path) as f:
    blocks = f.read().strip().split("\n\n")
parsed = []
for b in blocks:
    lines = b.split("\n")
    if len(lines) < 3: continue
    m = re.match(r"([\d:,]+) --> ([\d:,]+)", lines[1])
    if not m: continue
    parsed.append((to_s(m.group(1)), to_s(m.group(2)), "\n".join(lines[2:])))
for i in range(n):
    start = i * seg_len
    end = start + seg_len
    out, idx = [], 1
    for s, e, text in parsed:
        if e <= start or s >= end: continue
        ns = max(s, start) - start
        ne = min(e, end) - start
        out.append(f"{idx}\n{to_ts(ns)} --> {to_ts(ne)}\n{text}")
        idx += 1
    with open(os.path.join(work_dir, f"seg{i}.srt"), "w") as f:
        f.write("\n\n".join(out) + ("\n" if out else ""))
PYEOF

echo "Burning captions..."
PIDS=()
for i in $(seq 0 $((PARALLEL - 1))); do
  START=$(python3 -c "print($i * $SEG_LEN)")
  ffmpeg -y -ss "$START" -i "$VIDEO" -t "$SEG_LEN" \
    -vf "scale=1920:-2,subtitles=$WORK/seg$i.srt:force_style='$STYLE'" \
    -c:v h264_videotoolbox -b:v 6M -c:a aac -b:a 192k \
    "$WORK/seg$i.mp4" >"$WORK/seg$i.log" 2>&1 &
  PIDS+=($!)
done

FAIL=0
for i in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$i]}"; then
    echo "Segment $i failed. Log: $WORK/seg$i.log" >&2
    /bin/cat "$WORK/seg$i.log" | tail -10 >&2
    FAIL=1
  fi
done
[[ $FAIL -eq 1 ]] && exit 1

echo "Concatenating..."
: > "$WORK/concat.txt"
for i in $(seq 0 $((PARALLEL - 1))); do
  echo "file '$WORK/seg$i.mp4'" >> "$WORK/concat.txt"
done
ffmpeg -y -f concat -safe 0 -i "$WORK/concat.txt" -c copy "$OUTPUT" >/dev/null 2>&1

echo "Wrote: $OUTPUT"
