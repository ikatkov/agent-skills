---
name: parakeet-mlx-transcribe
description: Transcribe local audio and video media into text/subtitles using the parakeet-mlx CLI. Use only on macOS hosts where parakeet-mlx is installed and available on PATH. Use when requests mention transcription, subtitles, captions, timestamps, SRT/VTT/JSON output, or converting spoken content from files such as mp3, wav, m4a, mp4, mov, or mkv. Do not use on non-macOS systems or when parakeet-mlx is unavailable.
---

# Parakeet MLX Transcribe

## Overview

Use `parakeet-mlx` to transcribe media files and generate `txt`, `srt`, `vtt`, or `json` outputs on macOS systems with `parakeet-mlx` installed. For video inputs, extract audio with `ffmpeg` first, then transcribe the extracted audio.

## Execution Context

Before using this skill, verify the host is macOS and the CLI is installed:

```bash
test "$(uname -s)" = "Darwin"
command -v parakeet-mlx
```

If either check fails, do not use this skill. Tell the user that `parakeet-mlx` transcription requires macOS with `parakeet-mlx` installed.

Run `parakeet-mlx` in an environment with access to MLX/Metal. Restricted agent sandboxes may block device initialization even when the same command works in a normal terminal session.

## Workflow

1. Confirm input files exist and are readable.
2. Confirm the host is macOS and `parakeet-mlx` is installed.
3. If the input is video, extract audio first with `ffmpeg`.
4. Run `parakeet-mlx` with explicit output format and output directory.
5. Return output file paths and summarize what was generated.

## Quick Start

Transcribe a single audio file:

```bash
parakeet-mlx input.wav --output-dir ./transcripts --output-format srt
```

Transcribe and produce all formats:

```bash
parakeet-mlx input.m4a --output-dir ./transcripts --output-format all
```

Transcribe with word highlighting in subtitles:

```bash
parakeet-mlx input.wav --output-dir ./transcripts --output-format srt --highlight-words
```

## Video Input Handling

Extract mono 16k WAV, then transcribe:

```bash
ffmpeg -y -i input.mp4 -vn -ac 1 -ar 16000 ./tmp/input.wav
parakeet-mlx ./tmp/input.wav --output-dir ./transcripts --output-format srt
```

Prefer `scripts/transcribe_media.sh` for repeatable handling of mixed audio/video inputs.

## Decoding and Segmentation

Use decoding options only when needed:

- Default: `--decoding greedy`
- Higher quality but slower: `--decoding beam --beam-size 5 --patience 3.5`
- Sentence splitting: `--max-words`, `--silence-gap`, `--max-duration`
- Long files: tune `--chunk-duration` and `--overlap-duration`

## Output and Naming

Set deterministic naming with `--output-template`:

```bash
parakeet-mlx input.wav \
  --output-dir ./transcripts \
  --output-format json \
  --output-template '{filename}_{date}_{index}'
```

Useful template variables: `{filename}`, `{parent}`, `{date}`, `{index}`.

## Environment Variables

Use env vars for persistent defaults:

- `PARAKEET_MODEL`
- `PARAKEET_OUTPUT_FORMAT`
- `PARAKEET_OUTPUT_TEMPLATE`
- `PARAKEET_DECODING`
- `PARAKEET_CHUNK_DURATION`
- `PARAKEET_OVERLAP_DURATION`
- `PARAKEET_BEAM_SIZE`
- `PARAKEET_LENGTH_PENALTY`
- `PARAKEET_PATIENCE`
- `PARAKEET_DURATION_REWARD`
- `PARAKEET_MAX_WORDS`
- `PARAKEET_SILENCE_GAP`
- `PARAKEET_MAX_DURATION`
- `PARAKEET_FP32`
- `PARAKEET_LOCAL_ATTENTION`
- `PARAKEET_LOCAL_ATTENTION_CTX`
- `PARAKEET_CACHE_DIR`

## Troubleshooting

- If `parakeet-mlx --help` crashes with MLX/Metal initialization errors, rerun in a normal macOS terminal session with active GPU access.
- If transcription fails for video files, check `ffmpeg` availability and confirm audio extraction succeeded.
- If model download fails, set `--cache-dir` or `PARAKEET_CACHE_DIR` to a writable path.

## Resources

- Use `scripts/transcribe_media.sh` for one-command transcription of audio/video files.
- Read `references/cli-options.md` for the complete option map used by this skill.
