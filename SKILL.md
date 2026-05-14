---
name: video-captions
description: Transcribe a local video file and/or burn captions into it. Triggers when the user asks to caption/subtitle a video, burn subtitles, transcribe an mp4/mov, or generate an SRT for a video.
---

# video-captions

This skill captions local video files on macOS using whisper.cpp (Metal-accelerated transcription) and ffmpeg (parallel burn-in with Apple's hardware H.264 encoder). End-to-end is ~2-3 minutes for a 6-minute 1080p60 video on an M-series Mac.

## When to use

Use this skill when the user wants to:
- Generate captions/subtitles/an SRT for a video file
- Burn captions into a video so they're visible without a subtitle track
- Add subtitles to an mp4, mov, etc.

Do NOT use this skill for:
- Live captioning or streaming captions
- Soft subtitles (mov_text) where the user wants a selectable subtitle track. This skill only burns in.
- Non-English content (the default model is medium.en).

## Prerequisites

Before invoking the scripts, verify setup:
- `whisper-cli` is on PATH (Homebrew `whisper-cpp` package)
- `ffmpeg` is on PATH
- Model exists at `~/models/whisper-cpp/ggml-medium.en.bin`

If any are missing, run `setup.sh` from the skill directory. It is idempotent.

## Scripts

All three scripts live in `scripts/` and (after setup) are symlinked into `~/bin/`.

### All-in-one

```
caption-video.sh VIDEO [OUTPUT]
```

Transcribes then burns in one command. No manual SRT review step. Output defaults to `<basename> - captioned.mp4` next to the source.

### Two-step (recommended when caption accuracy matters)

```
transcribe-video.sh VIDEO          # writes <basename>.srt next to the video
# user manually reviews / edits the .srt
burn-captions.sh VIDEO SRT [OUTPUT]
```

### Tuning

- `PARALLEL=N burn-captions.sh ...` controls segment parallelism (default 6, max useful = P-core count).
- `WHISPER_MODEL=/path/to/ggml-*.bin transcribe-video.sh ...` overrides the model.

## Caption style

Captions are rendered as PNG "pills" — white text on a rounded, semi-transparent dark-gray rectangle — then composited onto the video with ffmpeg's overlay filter. Output is 1920 wide regardless of source. To tweak the look, edit the constants near the top of the inline Python block in `scripts/burn-captions.sh` (`FONT_SIZE`, `PAD_X`, `PAD_Y`, `RADIUS`, `BG`, `FG`, `MARGIN_BOTTOM`).

The renderer needs Pillow, which `setup.sh` installs into `~/.cache/video-captions/venv`.

## Performance notes for the agent

- The first invocation downloads the ~1.5 GB whisper model. Subsequent runs are instant to start.
- Burn-in time scales with output resolution and fps, not source resolution. The script scales to 1920 wide regardless of source, preserving aspect and 60fps.
- If burn-in is slow on a non-M-series Mac, drop `h264_videotoolbox` to libx264 with `-preset veryfast` in `burn-captions.sh`.
