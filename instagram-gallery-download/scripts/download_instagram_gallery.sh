#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  download_instagram_gallery.sh <instagram-post-url> [--output <dir>] [--cookies-browser <name>] [--] [extra gallery-dl args...]

Examples:
  download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/'
  download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/' --output ./downloads/instagram
  download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/' --cookies-browser chrome
  download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/' -- -R 2 --sleep 1-3
USAGE
}

if ! command -v gallery-dl >/dev/null 2>&1; then
  echo "Error: gallery-dl is not installed or not in PATH" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

url=""
out_dir="."
cookies_browser=""
extra_args=()
parsing_extra=false

while [[ $# -gt 0 ]]; do
  if [[ "$parsing_extra" == "true" ]]; then
    extra_args+=("$1")
    shift
    continue
  fi

  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --output|-o)
      if [[ $# -lt 2 ]]; then
        echo "Error: --output requires a value" >&2
        exit 1
      fi
      out_dir="$2"
      shift 2
      ;;
    --cookies-browser)
      if [[ $# -lt 2 ]]; then
        echo "Error: --cookies-browser requires a value" >&2
        exit 1
      fi
      cookies_browser="$2"
      shift 2
      ;;
    --)
      parsing_extra=true
      shift
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$url" ]]; then
        echo "Error: Multiple URLs provided. Pass exactly one Instagram URL." >&2
        exit 1
      fi
      url="$1"
      shift
      ;;
  esac
done

if [[ -z "$url" ]]; then
  echo "Error: Missing Instagram URL" >&2
  usage
  exit 1
fi

if [[ ! "$url" =~ ^https?://(www\.)?instagram\.com/ ]]; then
  echo "Error: URL must be an Instagram URL" >&2
  exit 1
fi

if [[ "$url" =~ ^https?://(www\.)?instagram\.com/reels?/ ]]; then
  echo "Error: reel/reels URLs are not handled by this script. Use the yt-dlp skill." >&2
  exit 1
fi

if [[ ! "$url" =~ ^https?://(www\.)?instagram\.com/p/[^/?#]+/?(\?.*)?$ ]]; then
  echo "Error: URL must match https://www.instagram.com/p/<code>/" >&2
  exit 1
fi

mkdir -p "$out_dir"

cmd=(
  gallery-dl
  --write-metadata
  --write-info-json
  --write-tags
  --download-archive "$out_dir/.gallery-dl-archive.sqlite3"
  -d "$out_dir"
)

if [[ -n "$cookies_browser" ]]; then
  cmd+=(--cookies-from-browser "$cookies_browser")
fi

cmd+=("${extra_args[@]}")
cmd+=("$url")

printf 'Running:'
printf ' %q' "${cmd[@]}"
printf '\n'

"${cmd[@]}"
