#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  video_feed_ocr.sh --input VIDEO --output-dir DIR [options]

Required:
  --input PATH          Input video path (mp4/mov/mkv/webm/...)
  --output-dir DIR      Output directory

Options:
  --fps N               Frames per second to sample (default: 1)
  --interval SEC        Sample one frame every N seconds (mutually exclusive with --fps)
  --lang LANG           Tesseract language (default: eng)
  --psm N               Tesseract page segmentation mode (default: 6)
  --frame-limit N       Stop after N frames (0 means all)
  --pattern REGEX       Optional regex filter written to ocr_hits.txt
  -h, --help            Show help
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

INPUT=""
OUT_DIR=""
FPS="1"
INTERVAL=""
LANG="eng"
PSM="6"
FRAME_LIMIT="0"
PATTERN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) INPUT="${2:-}"; shift 2 ;;
    --output-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --fps) FPS="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --lang) LANG="${2:-}"; shift 2 ;;
    --psm) PSM="${2:-}"; shift 2 ;;
    --frame-limit) FRAME_LIMIT="${2:-}"; shift 2 ;;
    --pattern) PATTERN="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$INPUT" || -z "$OUT_DIR" ]]; then
  echo "--input and --output-dir are required" >&2
  usage
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Input file not found: $INPUT" >&2
  exit 1
fi

if [[ -n "$INTERVAL" && "$FPS" != "1" ]]; then
  echo "Use either --fps or --interval (not both)" >&2
  exit 1
fi

require_cmd ffmpeg
require_cmd tesseract

if [[ -n "$PATTERN" ]] && ! command -v rg >/dev/null 2>&1; then
  echo "Warning: rg not found; --pattern filtering will be skipped" >&2
  PATTERN=""
fi

if [[ "$OUT_DIR" == /tmp/* ]]; then
  OUT_DIR="/private${OUT_DIR}"
fi

FRAMES_DIR="$OUT_DIR/frames"
RAW_OUT="$OUT_DIR/ocr_raw.txt"
HITS_OUT="$OUT_DIR/ocr_hits.txt"

mkdir -p "$FRAMES_DIR"
: > "$RAW_OUT"

if [[ -n "$INTERVAL" ]]; then
  VFILTER="fps=1/${INTERVAL}"
else
  VFILTER="fps=${FPS}"
fi

ffmpeg -y -i "$INPUT" -vf "$VFILTER" "$FRAMES_DIR/frame_%05d.png" >/dev/null 2>&1

mapfile -t frames < <(find "$FRAMES_DIR" -type f -name 'frame_*.png' | sort)
if [[ ${#frames[@]} -eq 0 ]]; then
  echo "No frames were extracted. Check input and sampling options." >&2
  exit 1
fi

count=0
for frame in "${frames[@]}"; do
  ((count+=1))
  bn="$(basename "$frame")"

  if ! text="$(tesseract "$frame" stdout -l "$LANG" --psm "$PSM" 2>/dev/null)"; then
    echo "Warning: OCR failed for ${bn}" >&2
    continue
  fi

  if [[ -n "$text" ]]; then
    sed "s/^/${bn}:/" <<< "$text" >> "$RAW_OUT"
  fi

  if [[ "$FRAME_LIMIT" != "0" && "$count" -ge "$FRAME_LIMIT" ]]; then
    break
  fi
done

if [[ -n "$PATTERN" ]]; then
  rg -in -- "$PATTERN" "$RAW_OUT" > "$HITS_OUT" || true
fi

echo "Frames directory: $FRAMES_DIR"
echo "Raw OCR output:  $RAW_OUT"
if [[ -n "$PATTERN" ]]; then
  echo "Filtered hits:   $HITS_OUT"
fi
echo "Processed frames: $count"
