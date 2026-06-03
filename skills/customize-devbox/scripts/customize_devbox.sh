#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  customize_devbox.sh <ssh-target> [--ssh-arg <arg>]...

Examples:
  customize_devbox.sh devbox-host
  customize_devbox.sh igor@devbox-host
  customize_devbox.sh devbox-host --ssh-arg -p --ssh-arg 2222

The target can be a hostname, user@host, or an SSH config alias.
Extra SSH args are reused for scp; ssh -p is translated to scp -P.

Required input:
  Pass exactly one target hostname or SSH target. The script does not infer
  the target.

Local requirements:
  - ssh and scp on PATH

Remote requirements:
  - Ubuntu, verified via /etc/os-release
  - ssh access
  - sudo, wget, dpkg, awk, grep, and mktemp on the remote host
  - interactive sudo if sudo credentials are not cached

Remote changes:
  1. Install rsub:
       sudo wget -O /usr/local/bin/rsub https://raw.github.com/aurora/rmate/master/rmate
       sudo chmod +x /usr/local/bin/rsub
  2. Add a managed tmux auto-attach block to ~/.bashrc:
       if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && [[ $- == *i* ]]; then
         tmux attach-session -t main || tmux new-session -s main
       fi
  3. Install tpack 1.0.0 from:
       https://github.com/tmuxpack/tpack/releases/download/v1.0.0/tpack_1.0.0_linux_amd64.deb
  4. Replace ~/.tmux.conf with the bundled assets/tmux.conf template:
       set -g @plugin "tmux-plugins/tmux-sensible"
       set -g @plugin "sainnhe/tmux-fzf"
       set -g status-right ''
       set -g status-left '#H #S '
       set -g status-left-length 100
       set -g status-justify left
       run "tpack init"
  5. Run tmux source-file ~/.tmux.conf when tmux is available.

Idempotence:
  The script rewrites only its own marked block in ~/.bashrc.
  It replaces ~/.tmux.conf with the same bundled local template on every run.
  Existing unmarked tmux auto-attach setup is detected and left unchanged.

Troubleshooting:
  - If SSH fails, verify the target with: ssh <ssh-target>
  - If sudo fails, rerun from a terminal where interactive sudo can prompt.
  - If the remote is not Ubuntu, this script exits without applying changes.
  - If tmux is missing, the script finishes with a warning; install tmux before
    relying on auto-attach behavior.
USAGE
}

target=""
ssh_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --ssh-arg)
      if [[ $# -lt 2 ]]; then
        echo "Error: --ssh-arg requires a value" >&2
        exit 2
      fi
      ssh_args+=("$2")
      shift 2
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$target" ]]; then
        echo "Error: pass exactly one SSH target" >&2
        usage >&2
        exit 2
      fi
      target="$1"
      shift
      ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "Error: missing SSH target" >&2
  usage >&2
  exit 2
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "Error: ssh is not installed or not on PATH" >&2
  exit 1
fi

if ! command -v scp >/dev/null 2>&1; then
  echo "Error: scp is not installed or not on PATH" >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmux_conf_template="${script_dir}/../assets/tmux.conf"
if [[ ! -r "$tmux_conf_template" ]]; then
  echo "Error: missing bundled tmux template: ${tmux_conf_template}" >&2
  exit 1
fi

scp_args=()
for arg in "${ssh_args[@]}"; do
  if [[ "$arg" == "-p" ]]; then
    scp_args+=("-P")
  else
    scp_args+=("$arg")
  fi
done

echo "Connecting to ${target}..."

ssh "${ssh_args[@]}" "$target" 'bash -s' <<'REMOTE_SETUP'
set -euo pipefail

if [[ ! -r /etc/os-release ]]; then
  echo "Error: /etc/os-release not found; expected Ubuntu remote host" >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Error: remote host must be Ubuntu; got ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is missing on the remote host" >&2
    exit 1
  fi
}

require_command sudo
require_command wget
require_command dpkg
require_command awk
require_command mktemp
require_command grep

append_or_replace_marked_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local block="$4"
  local tmp
  local clean

  touch "$file"
  tmp=$(mktemp)
  clean=$(mktemp)
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip { next }
    { print }
  ' "$file" > "$tmp"

  awk '
    NF {
      for (i = 0; i < blanks; i++) print ""
      blanks = 0
      print
      next
    }
    { blanks++ }
  ' "$tmp" > "$clean"

  {
    cat "$clean"
    if [[ -s "$clean" ]]; then
      printf '\n'
    fi
    printf '%s\n' "$block"
  } > "$file"
  rm -f "$tmp" "$clean"
}

install_rsub() {
  echo "Installing rsub..."
  sudo wget -O /usr/local/bin/rsub https://raw.github.com/aurora/rmate/master/rmate
  sudo chmod +x /usr/local/bin/rsub
}

configure_bashrc() {
  local bashrc="$HOME/.bashrc"
  local begin="# >>> customize-devbox tmux auto-attach >>>"
  local end="# <<< customize-devbox tmux auto-attach <<<"
  local block

  block=$(cat <<'BASHRC_BLOCK'
# >>> customize-devbox tmux auto-attach >>>
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && [[ $- == *i* ]]; then
  tmux attach-session -t main || tmux new-session -s main
fi
# <<< customize-devbox tmux auto-attach <<<
BASHRC_BLOCK
)

  if grep -Fq "$begin" "$bashrc" 2>/dev/null; then
    echo "Updating managed tmux auto-attach block in ~/.bashrc..."
    append_or_replace_marked_block "$bashrc" "$begin" "$end" "$block"
  elif grep -Fq 'tmux attach-session -t main || tmux new-session -s main' "$bashrc" 2>/dev/null; then
    echo "tmux auto-attach already appears in ~/.bashrc; leaving existing block unchanged."
  else
    echo "Adding tmux auto-attach block to ~/.bashrc..."
    append_or_replace_marked_block "$bashrc" "$begin" "$end" "$block"
  fi
}

install_tpack() {
  local package="tpack_1.0.0_linux_amd64.deb"
  local url="https://github.com/tmuxpack/tpack/releases/download/v1.0.0/${package}"
  local tmpdir

  if dpkg-query -W -f='${Version}' tpack 2>/dev/null | grep -Fxq '1.0.0'; then
    echo "tpack 1.0.0 is already installed."
    return
  fi

  echo "Installing tpack 1.0.0..."
  tmpdir=$(mktemp -d)
  wget -O "${tmpdir}/${package}" "$url"
  sudo dpkg -i "${tmpdir}/${package}"
  rm -rf "$tmpdir"
}

install_rsub
configure_bashrc
install_tpack
REMOTE_SETUP

echo "Copying bundled tmux template to ${target}:~/.tmux.conf..."
scp "${scp_args[@]}" "$tmux_conf_template" "${target}:~/.tmux.conf"

echo "Sourcing remote ~/.tmux.conf..."
ssh "${ssh_args[@]}" "$target" 'bash -s' <<'REMOTE_TMUX_SOURCE'
set -euo pipefail

if command -v tmux >/dev/null 2>&1; then
  if ! tmux source-file "$HOME/.tmux.conf"; then
    echo "Warning: tmux source-file failed; existing sessions may need manual reload." >&2
  fi
else
  echo "Warning: tmux is not installed on the remote host; install tmux before relying on auto-attach." >&2
fi
REMOTE_TMUX_SOURCE

echo "Remote Ubuntu devbox setup complete."
