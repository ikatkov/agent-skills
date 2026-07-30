#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  customize_devbox.sh <ssh-target> [--ssh-arg <arg>]...
  customize_devbox.sh --sbx <sandbox-name>
  customize_devbox.sh --transport ssh <ssh-target> [--ssh-arg <arg>]...
  customize_devbox.sh --transport sbx <sandbox-name>

Examples:
  customize_devbox.sh devbox-host
  customize_devbox.sh igor@devbox-host
  customize_devbox.sh devbox-host --ssh-arg -p --ssh-arg 2222
  customize_devbox.sh --transport ssh devbox-host
  customize_devbox.sh --sbx devbox-sandbox
  customize_devbox.sh --transport sbx devbox-sandbox
  sbx ls

The default transport is ssh. The SSH target can be a hostname, user@host,
or an SSH config alias. Extra SSH args are reused for scp; ssh -p is
translated to scp -P. Use sbx ls to discover Docker Sandbox names.

Required input:
  Pass exactly one SSH target or sandbox name. The script does not infer
  the target. --ssh-arg is valid only with the ssh transport.

Local requirements:
  - ssh mode: ssh and scp on PATH
  - sbx mode: sbx on PATH and access to the target Docker Sandbox

Target requirements:
  - Ubuntu, verified via /etc/os-release
  - ssh mode: ssh access
  - sbx mode: sandbox access through sbx
  - sudo, wget, dpkg, awk, grep, and mktemp on the target
  - apt-get on the target when tmux or psmisc is missing
  - interactive sudo if sudo credentials are not cached; sbx mode generally
    requires passwordless sudo for non-interactive package installation
  - git and gh on the target are optional: the tab title adds the branch ticket
    id when git is present and the open-PR number when gh is authenticated,
    and degrades gracefully to the bare hostname otherwise

Target changes:
  1. Install rsub:
       sudo wget -O /usr/local/bin/rsub https://raw.github.com/aurora/rmate/master/rmate
       sudo chmod +x /usr/local/bin/rsub
  2. Install tmux with apt-get if it is missing.
  3. Install psmisc (pstree) with apt-get if it is missing; title.sh uses it to
     detect a Claude session in the pane process tree.
  4. Add a managed tmux auto-attach block to ~/.bashrc:
       if { [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SANDBOX_VM_ID:-}" ]; } && [ -z "${TMUX:-}" ] && [[ $- == *i* ]]; then
         tmux attach-session -t main || tmux new-session -s main
       fi
  5. Install the tpack 1.0.0 Debian package matching the target architecture:
       https://github.com/tmuxpack/tpack/releases/download/v1.0.0/tpack_1.0.0_linux_<arch>.deb
  6. Replace ~/.tmux.conf with the bundled assets/tmux.conf template. It sets the
     parent terminal (iTerm2) tab title from a #() job (#{q:...} shell-escapes the
     path so a directory name cannot inject commands):
       set -g set-titles-string "#(~/.tmux/bin/title.sh #{pane_pid} #{q:pane_current_path})"
  7. Install the bundled assets/title.sh to ~/.tmux/bin/title.sh (chmod +x). It
     renders the tab title as <host>, <host> · TICKET, or <host> · TICKET · PR #n.
  8. Run tmux source-file ~/.tmux.conf when tmux is available and a tmux
     server is already running. New sessions read ~/.tmux.conf automatically.

Idempotence:
  The script rewrites only its own marked block in ~/.bashrc.
  It replaces ~/.tmux.conf and ~/.tmux/bin/title.sh with the same bundled local
  templates on every run.
  Existing unmarked tmux auto-attach setup is detected and left unchanged.

Troubleshooting:
  - If SSH fails, verify the target with: ssh <ssh-target>
  - If sbx mode fails before setup starts, verify the sandbox with: sbx ls
  - If sudo fails, rerun from a terminal where interactive sudo can prompt.
  - If the target is not Ubuntu, this script exits without applying changes.
  - If tmux is missing, the script finishes with a warning; install tmux before
    relying on auto-attach behavior.
USAGE
}

transport="ssh"
target=""
ssh_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --transport)
      if [[ $# -lt 2 ]]; then
        echo "Error: --transport requires a value" >&2
        exit 2
      fi
      case "$2" in
        ssh|sbx)
          transport="$2"
          ;;
        *)
          echo "Error: unknown transport: $2" >&2
          usage >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --sbx)
      if [[ $# -lt 2 ]]; then
        echo "Error: --sbx requires a sandbox name" >&2
        exit 2
      fi
      if [[ -n "$target" ]]; then
        echo "Error: pass exactly one target" >&2
        usage >&2
        exit 2
      fi
      transport="sbx"
      target="$2"
      shift 2
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
        echo "Error: pass exactly one target" >&2
        usage >&2
        exit 2
      fi
      target="$1"
      shift
      ;;
  esac
done

if [[ -z "$target" ]]; then
  echo "Error: missing target" >&2
  usage >&2
  exit 2
fi

if [[ "$transport" == "sbx" && "${#ssh_args[@]}" -gt 0 ]]; then
  echo "Error: --ssh-arg is valid only with the ssh transport" >&2
  exit 2
fi

case "$transport" in
  ssh)
    if ! command -v ssh >/dev/null 2>&1; then
      echo "Error: ssh is not installed or not on PATH" >&2
      exit 1
    fi

    if ! command -v scp >/dev/null 2>&1; then
      echo "Error: scp is not installed or not on PATH" >&2
      exit 1
    fi
    ;;
  sbx)
    if ! command -v sbx >/dev/null 2>&1; then
      echo "Error: sbx is not installed or not on PATH" >&2
      exit 1
    fi
    ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmux_conf_template="${script_dir}/../assets/tmux.conf"
if [[ ! -r "$tmux_conf_template" ]]; then
  echo "Error: missing bundled tmux template: ${tmux_conf_template}" >&2
  exit 1
fi

# tmux.conf's set-titles-string runs this script; ship them together.
title_script_template="${script_dir}/../assets/title.sh"
if [[ ! -r "$title_script_template" ]]; then
  echo "Error: missing bundled title script: ${title_script_template}" >&2
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

remote_exec() {
  case "$transport" in
    ssh)
      ssh "${ssh_args[@]}" "$target" "$@"
      ;;
    sbx)
      sbx exec -i "$target" "$@"
      ;;
  esac
}

remote_home() {
  case "$transport" in
    ssh)
      ssh "${ssh_args[@]}" "$target" 'printf %s "$HOME"'
      ;;
    sbx)
      sbx exec "$target" sh -lc 'printf %s "$HOME"'
      ;;
  esac
}

copy_tmux_conf() {
  case "$transport" in
    ssh)
      scp "${scp_args[@]}" "$tmux_conf_template" "${target}:~/.tmux.conf"
      ;;
    sbx)
      local home
      home="$(remote_home)"
      if [[ -z "$home" ]]; then
        echo "Error: could not resolve sandbox HOME" >&2
        exit 1
      fi
      sbx cp "$tmux_conf_template" "${target}:${home}/.tmux.conf"
      ;;
  esac
}

copy_title_script() {
  case "$transport" in
    ssh)
      ssh "${ssh_args[@]}" "$target" 'mkdir -p ~/.tmux/bin'
      scp "${scp_args[@]}" "$title_script_template" "${target}:~/.tmux/bin/title.sh"
      ssh "${ssh_args[@]}" "$target" 'chmod +x ~/.tmux/bin/title.sh'
      ;;
    sbx)
      local home
      home="$(remote_home)"
      if [[ -z "$home" ]]; then
        echo "Error: could not resolve sandbox HOME" >&2
        exit 1
      fi
      sbx exec "$target" sh -lc 'mkdir -p ~/.tmux/bin'
      sbx cp "$title_script_template" "${target}:${home}/.tmux/bin/title.sh"
      sbx exec "$target" sh -lc 'chmod +x ~/.tmux/bin/title.sh'
      ;;
  esac
}

echo "Connecting to ${transport} target ${target}..."

remote_exec bash -s <<'REMOTE_SETUP'
set -euo pipefail

if [[ ! -r /etc/os-release ]]; then
  echo "Error: /etc/os-release not found; expected Ubuntu target" >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Error: target must be Ubuntu; got ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is missing on the target" >&2
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

install_tmux() {
  if command -v tmux >/dev/null 2>&1; then
    echo "tmux is already installed."
    return
  fi

  require_command apt-get

  echo "Installing tmux..."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y tmux
}

install_psmisc() {
  # title.sh walks the pane process tree with pstree to detect a Claude session;
  # without it the tab title degrades to the bare hostname.
  if command -v pstree >/dev/null 2>&1; then
    echo "pstree is already installed."
    return
  fi

  require_command apt-get

  echo "Installing psmisc (pstree)..."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y psmisc
}

configure_bashrc() {
  local bashrc="$HOME/.bashrc"
  local begin="# >>> customize-devbox tmux auto-attach >>>"
  local end="# <<< customize-devbox tmux auto-attach <<<"
  local block

  block=$(cat <<'BASHRC_BLOCK'
# >>> customize-devbox tmux auto-attach >>>
if { [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SANDBOX_VM_ID:-}" ]; } && [ -z "${TMUX:-}" ] && [[ $- == *i* ]]; then
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
  local version="1.0.0"
  local arch
  local package
  local url
  local tmpdir

  if dpkg-query -W -f='${Version}' tpack 2>/dev/null | grep -Fxq "$version"; then
    echo "tpack ${version} is already installed."
    return
  fi

  arch=$(dpkg --print-architecture)
  case "$arch" in
    amd64|arm64)
      ;;
    *)
      echo "Error: unsupported architecture for tpack: ${arch}" >&2
      exit 1
      ;;
  esac

  package="tpack_${version}_linux_${arch}.deb"
  url="https://github.com/tmuxpack/tpack/releases/download/v${version}/${package}"

  echo "Installing tpack ${version} (${arch})..."
  tmpdir=$(mktemp -d)
  wget -O "${tmpdir}/${package}" "$url" || {
    rm -rf "$tmpdir"
    return 1
  }
  sudo dpkg -i "${tmpdir}/${package}" || {
    rm -rf "$tmpdir"
    return 1
  }
  rm -rf "$tmpdir"
}

install_rsub
install_tmux
install_psmisc
configure_bashrc
install_tpack
REMOTE_SETUP

echo "Copying bundled tmux template to target ~/.tmux.conf..."
copy_tmux_conf

echo "Copying bundled title script to target ~/.tmux/bin/title.sh..."
copy_title_script

echo "Sourcing target ~/.tmux.conf..."
remote_exec bash -s <<'REMOTE_TMUX_SOURCE'
set -euo pipefail

if command -v tmux >/dev/null 2>&1; then
  if tmux list-sessions >/dev/null 2>&1; then
    if ! tmux source-file "$HOME/.tmux.conf"; then
      echo "Warning: tmux source-file failed; existing sessions may need manual reload." >&2
    fi
  else
    echo "No running tmux server; new sessions will read ~/.tmux.conf automatically."
  fi
else
  echo "Warning: tmux is not installed on the target; install tmux before relying on auto-attach." >&2
fi
REMOTE_TMUX_SOURCE

echo "Ubuntu devbox setup complete."
