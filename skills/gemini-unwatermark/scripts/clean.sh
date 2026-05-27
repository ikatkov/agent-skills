#!/usr/bin/env bash
# Remove Gemini watermarks from local images. POSIX (macOS / Linux).
# Outputs are written next to each input as <slug>-clean.<ext>.

set -euo pipefail

PACKAGE_SPEC="${GWR_SKILL_CLI_SPEC:-@pilio/gemini-watermark-remover}"

usage() {
  cat <<'EOF'
Usage: clean.sh [-f|--overwrite] [-r|--recursive] <path> [<path>...]

Each <path> can be:
  - a single image file        (e.g. ./foo.png)
  - a directory                (processes images inside; non-recursive unless -r)
  - a glob mask                (quote it: './photos/IMG_*.png')

Supported extensions: png, jpg, jpeg, webp (case-insensitive).
Outputs are written as <dir>/<slug>-clean.<ext>.
Files whose basename already ends in "-clean" are skipped.
Existing outputs are skipped unless -f / --overwrite is given.

Options:
  -f, --overwrite   Overwrite existing <slug>-clean.<ext> outputs.
  -r, --recursive   Recurse into subdirectories when a directory is given.
  -h, --help        Show this help.
EOF
}

overwrite=0
recursive=0
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--overwrite) overwrite=1; shift ;;
    -r|--recursive) recursive=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do inputs+=("$1"); shift; done ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) inputs+=("$1"); shift ;;
  esac
done

if [[ ${#inputs[@]} -eq 0 ]]; then
  usage >&2
  exit 2
fi

ensure_gwr() {
  if command -v gwr >/dev/null 2>&1; then
    return
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm not found; cannot install ${PACKAGE_SPEC}." >&2
    exit 1
  fi
  echo "Installing ${PACKAGE_SPEC} globally (first-run setup)..." >&2
  npm install -g "${PACKAGE_SPEC}" >&2
  if command -v gwr >/dev/null 2>&1; then
    return
  fi
  local bin
  bin=$(npm config get prefix 2>/dev/null)/bin
  echo "Installed ${PACKAGE_SPEC} but 'gwr' is not on PATH." >&2
  echo "Add the npm global bin to PATH and retry:" >&2
  echo "  export PATH=\"${bin}:\$PATH\"" >&2
  exit 1
}

# Collect input files into the `files` array, NUL-safe.
files=()

collect_from_dir() {
  local dir="$1"
  local depth_args=(-maxdepth 1)
  [[ $recursive -eq 1 ]] && depth_args=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$dir" "${depth_args[@]}" -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
    -print0)
}

collect_from_glob() {
  # Handle a glob-bearing path by splitting into dir + filename pattern and
  # using `find -name`, which handles spaces and quoting cleanly.
  local pattern="$1"
  local dir pat
  dir=$(dirname -- "$pattern")
  pat=$(basename -- "$pattern")
  [[ -d "$dir" ]] || { echo "No such directory for pattern: $pattern" >&2; return 1; }
  local found=0
  while IFS= read -r -d '' f; do
    files+=("$f")
    found=1
  done < <(find "$dir" -maxdepth 1 -type f -iname "$pat" -print0)
  if [[ $found -eq 0 ]]; then
    echo "No matches for: $pattern" >&2
    return 1
  fi
}

for input in "${inputs[@]}"; do
  if [[ -d "$input" ]]; then
    collect_from_dir "$input"
  elif [[ -f "$input" ]]; then
    files+=("$input")
  else
    collect_from_glob "$input" || true
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No image files found." >&2
  exit 1
fi

ensure_gwr

ok=0
fail=0
skipped=0

for file in "${files[@]}"; do
  filename=$(basename -- "$file")
  extension="${filename##*.}"
  slug="${filename%.*}"

  if [[ "$slug" == *-clean ]]; then
    echo "skip (already clean): $file"
    skipped=$((skipped+1))
    continue
  fi

  output_dir=$(dirname -- "$file")
  output="$output_dir/$slug-clean.$extension"

  if [[ -e "$output" && $overwrite -ne 1 ]]; then
    echo "skip (exists, use -f to overwrite): $output"
    skipped=$((skipped+1))
    continue
  fi

  args=(remove "$file" --output "$output")
  [[ $overwrite -eq 1 ]] && args+=(--overwrite)

  echo "clean: $file -> $output"
  if gwr "${args[@]}"; then
    ok=$((ok+1))
  else
    echo "  failed: $file" >&2
    fail=$((fail+1))
  fi
done

echo "Done. cleaned=$ok skipped=$skipped failed=$fail"
[[ $fail -eq 0 ]]
