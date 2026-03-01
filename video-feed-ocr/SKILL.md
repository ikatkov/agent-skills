---
name: video-feed-ocr
description: Extract visible text from local video files by sampling frames and running OCR. Use when requests involve reading on-screen text, burned-in subtitles, slides, code snippets, captions, signs, or UI text from mp4/mov/mkv/webm recordings, reels, screen captures, or video feeds.
---

# Video Feed OCR

## Overview

Run frame-by-frame OCR for general video analysis. This skill is for any on-screen text extraction task, not just URLs.

## Workflow

1. Confirm the input video exists and is readable.
2. Run `scripts/video_feed_ocr.sh` with an output directory under `/tmp` or the current workspace.
3. Review `ocr_raw.txt` for full extracted text.
4. Optionally filter with `--pattern` to generate `ocr_hits.txt`.
5. Report both what was detected and confidence caveats (OCR typos, low contrast, motion blur).

## Quick Start

```bash
scripts/video_feed_ocr.sh \
  --input /path/to/video.mp4 \
  --output-dir /tmp/video-ocr
```

## Common Options

- `--fps N`: frames per second to sample (default `1`).
- `--interval S`: sample one frame every `S` seconds (alternative to `--fps`).
- `--lang LANG`: tesseract language code (default `eng`).
- `--psm N`: tesseract page segmentation mode (default `6`).
- `--frame-limit N`: stop after `N` frames (for quick previews).
- `--pattern REGEX`: write filtered matches to `ocr_hits.txt`.

Examples:

```bash
# Every 2 seconds, faster pass
scripts/video_feed_ocr.sh --input input.mp4 --output-dir /tmp/ocr --interval 2

# Look for emails, URLs, ticket ids, or any custom regex
scripts/video_feed_ocr.sh \
  --input input.mp4 \
  --output-dir /tmp/ocr \
  --pattern 'https?://[^ ]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+'
```

## Resource

- Main script: `scripts/video_feed_ocr.sh`
