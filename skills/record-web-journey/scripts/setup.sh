#!/usr/bin/env bash
# One-time setup: installs Playwright next to the recorder, the ffmpeg helper it needs for
# video, and a Chromium only when no Google Chrome is installed.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null; then
  echo "node is required (v20+)." >&2
  exit 1
fi

if command -v pnpm >/dev/null; then pnpm install --silent; else npm install --no-audit --no-fund --silent; fi
npx --yes playwright install ffmpeg

if node -e "require('playwright').chromium.executablePath({channel:'chrome'})" 2>/dev/null; then
  echo "Google Chrome found; recordings will use it (--chrome)."
else
  echo "No Google Chrome found; installing Playwright's Chromium."
  npx --yes playwright install chromium
fi
echo "setup done"
