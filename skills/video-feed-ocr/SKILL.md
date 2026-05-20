---
name: video-feed-ocr
description: Extract visible text from local video files by sampling frames and running OCR via a local multimodal LLM. Use when requests involve reading on-screen text, burned-in subtitles, slides, code snippets, captions, signs, or UI text from mp4/mov/mkv/webm recordings, reels, screen captures, or video feeds.
---

# Video Feed OCR

If the task is extracting on-screen text from video, use this skill first.

## Overview

Run frame-by-frame OCR for general video analysis using one self-contained Python script in this skill.

The script supports two OCR engines:
- Fast path: Tesseract via `--fast` (lower latency, may be less accurate)
- High quality: Local multimodal LLM (higher quality on complex layouts)

If fast output is noisy, missing lines, or misread, rerun without `--fast` to use the LLM path.

## Workflow

1. Confirm the input video exists and is readable.
2. Run `python3 scripts/video_feed_ocr.py` with an output directory under `/tmp` or the current workspace.
3. For quick/cheap pass, add `--fast`.
4. Review `ocr_raw.txt` for full extracted text.
5. Optionally filter with `--pattern` to generate `ocr_hits.txt`.
6. Report both what was detected and confidence caveats (OCR typos, low contrast, motion blur, model hallucination risk).

## Quick Start


Fast (Tesseract):

```bash
python3 scripts/video_feed_ocr.py \
  --input /path/to/video.mp4 \
  --output-dir /tmp/video-ocr \
  --fast
```

High Quality (LLM):

```bash
python3 scripts/video_feed_ocr.py \
  --input /path/to/video.mp4 \
  --output-dir /tmp/video-ocr
```


## Execution Context

Always run this skill in escalation permission mode.

## Common Options

- `--fps N`: frames per second to sample (default `1`)
- `--interval S`: sample one frame every `S` seconds (alternative to `--fps`)
- `--frame-limit N`: stop after `N` frames (for quick previews)
- `--pattern REGEX`: write filtered matches to `ocr_hits.txt`
- `--fast`: use Tesseract instead of the LLM path
- `--lang LANG`: Tesseract language in fast mode (default `eng`)
- `--psm N`: Tesseract page segmentation mode in fast mode (default `6`)
- `--task-prompt TEXT`: optional custom OCR extraction instruction for LLM mode
- `--timeout SEC`: timeout per OCR call

Model is hardcoded in the script to `qwen/qwen3-vl-4b` for LLM mode.

Default OCR prompt used when `--task-prompt` is omitted:

```text
Extract all text exactly as seen.
Keep reading order.
Keep line breaks.
Do not paraphrase.
Do not translate.
If unsure add (?).
If unreadable write [illegible].

Use:
Paragraphs for normal text.
Bullets for obvious lists.
Tables only if clearly a table.

Return Markdown only.
```

Examples:

```bash
# Every 2 seconds, faster sampling
python3 scripts/video_feed_ocr.py --input input.mp4 --output-dir /tmp/ocr --interval 2

# Fast OCR with explicit Tesseract options
python3 scripts/video_feed_ocr.py \
  --input input.mp4 \
  --output-dir /tmp/ocr \
  --fast \
  --lang eng \
  --psm 6

# If fast output is poor, rerun with LLM + optional custom prompt
python3 scripts/video_feed_ocr.py \
  --input input.mp4 \
  --output-dir /tmp/ocr \
  --task-prompt "Extract subtitles only. Preserve line breaks."

# Look for emails, URLs, ticket ids, or any custom regex
python3 scripts/video_feed_ocr.py \
  --input input.mp4 \
  --output-dir /tmp/ocr \
  --pattern 'https?://[^ ]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+'
```

## Resource
- `scripts/video_feed_ocr.py`
