# video-captions

Fast local video captioning for macOS. Transcribes with whisper.cpp (Metal-accelerated) and burns captions in with ffmpeg using Apple's hardware H.264 encoder and segment-parallel encoding.

End-to-end for a 6-minute 1080p60 video on an M3 Mac: **~2 minutes 40 seconds**. Same job with vanilla `openai-whisper` + sequential ffmpeg took over 3 hours.

## Setup

```
git clone https://github.com/<you>/video-captions ~/code/video-captions
cd ~/code/video-captions
./setup.sh
```

`setup.sh` installs `ffmpeg` and `whisper-cpp` via Homebrew, downloads the `medium.en` GGML model (~1.5 GB) into `~/models/whisper-cpp/`, and symlinks the three scripts into `~/bin/`.

If `~/bin` is not on your `PATH`, add this to your `~/.zshrc` or `~/.bashrc`:

```
export PATH="$HOME/bin:$PATH"
```

## Usage

### Caption a video in one command

```
caption-video.sh "my-video.mp4"
# writes "my-video - captioned.mp4" next to the source
```

### Two-step: transcribe, manually fix the SRT, then burn

```
transcribe-video.sh "my-video.mp4"
# writes "my-video.srt" next to the source
# open and edit "my-video.srt" to fix any misheard words

burn-captions.sh "my-video.mp4" "my-video.srt"
# writes "my-video - captioned.mp4" next to the source
```

You can also pass a custom output path as the third argument:

```
burn-captions.sh "input.mp4" "input.srt" "/path/to/output.mp4"
```

### Tuning

- `PARALLEL=N` controls how many ffmpeg processes run in parallel for the burn-in. Default `6`. On Apple Silicon, the useful ceiling is your performance-core count.
  ```
  PARALLEL=8 burn-captions.sh input.mp4 input.srt
  ```
- `WHISPER_MODEL=/path/to/ggml-*.bin` overrides which model `transcribe-video.sh` uses.

## What it does, technically

**Transcription** — `transcribe-video.sh`:
1. Extracts a 16 kHz mono PCM WAV from the video with ffmpeg.
2. Runs `whisper-cli` (whisper.cpp) with the `medium.en` model and Metal acceleration.
3. Writes an SRT alongside the source video.

**Burn-in** — `burn-captions.sh`:
1. Splits the video into N equal-length segments.
2. Trims the SRT to each segment, shifting timestamps to start at 0.
3. Renders all segments in parallel:
   - Scales to 1920 wide (preserving aspect and 60fps).
   - Applies the SRT via libass with a fixed YouTube-style `force_style`.
   - Encodes with `h264_videotoolbox` (Apple hardware encoder).
4. Concatenates the segments losslessly with `ffmpeg -f concat -c copy`.

**Caption style** is fixed:

```
Fontname=Helvetica
Fontsize=18
Bold=1
PrimaryColour=&H00FFFFFF      # white
BackColour=&HCC000000          # 80% black box behind text
BorderStyle=3                  # opaque box
Outline=4
Shadow=0
Alignment=2                    # bottom-center
MarginV=60
```

Edit the `STYLE=` line in `scripts/burn-captions.sh` to change it. ASS `force_style` syntax. Colors are `&HAABBGGRR` (BGR, not RGB, with alpha first).

## As a Claude Code skill

`SKILL.md` makes this directory usable as a Claude Code skill. Drop the repo into `~/.claude/skills/video-captions/` (or a project's `.claude/skills/`) and Claude will invoke the scripts when the user asks to caption or subtitle a video.

## Why it's fast

Two practical decisions:

1. **whisper.cpp instead of openai-whisper.** Same model weights; the C++ port with Metal acceleration is roughly 200x faster on Apple Silicon than the PyTorch CLI running on CPU.
2. **Segment-parallel burn-in.** libass renders subtitles one CPU thread at a time. Splitting the video into N segments and running N ffmpeg processes in parallel lets the burn step use all your cores at once.

## Limitations

- macOS only (uses `h264_videotoolbox` and assumes Homebrew). Linux/Windows users would need to swap the encoder to `libx264` and adjust setup.
- English-only by default (model is `medium.en`). Set `WHISPER_MODEL` to a multilingual model file if you need other languages.
- Burn-in caption style is fixed in code. There's no CLI flag for it; edit the script.

## License

MIT.
