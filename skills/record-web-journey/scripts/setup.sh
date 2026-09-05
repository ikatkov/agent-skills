#!/usr/bin/env bash
# One-time setup: installs the browser driver and recorder dependencies beside the skill.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v node >/dev/null; then
  echo "Node.js 20 or newer is required." >&2
  exit 1
fi

node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
if (( node_major < 20 )); then
  echo "Node.js 20 or newer is required; found $(node --version)." >&2
  exit 1
fi

if command -v pnpm >/dev/null; then
  pnpm install --ignore-workspace --no-lockfile --ignore-scripts --silent
else
  npm install --ignore-scripts --no-audit --no-fund --no-package-lock --silent
fi

./node_modules/.bin/playwright install ffmpeg

has_chrome=false
case "$(uname -s)" in
  Darwin)
    [[ -x "${CHROME_PATH:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}" ]] && has_chrome=true
    ;;
  Linux)
    command -v google-chrome >/dev/null && has_chrome=true
    ;;
esac

if [[ "$has_chrome" == true ]]; then
  echo "Google Chrome found; recordings will use it (--chrome)."
else
  ./node_modules/.bin/playwright install chromium
  echo "Playwright Chromium installed."
fi

echo "record-web-journey setup complete"
