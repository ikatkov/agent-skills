#!/usr/bin/env bash
# Compute the iTerm2 tab title for the active tmux pane.
#
# tmux calls this from `set-titles-string` via a #() job and forwards the output
# to the outer terminal (iTerm2) as an OSC title. Invoked with the active pane's
# pid and working directory (the path is shell-escaped by tmux, no manual quotes):
#
#     set -g set-titles-string "#(~/.tmux/bin/title.sh #{pane_pid} #{q:pane_current_path})"
#
# Output shape:
#   <host>                              # plain shell / anything else
#   <host> · <TICKET>                   # a Claude Code session lives in this pane
#   <host> · <TICKET> · PR #<n>         # ...and the branch has an open PR
#
# "In a Claude session" is decided by the pane's process TREE, not the foreground
# command: while Claude runs a tool it spawns a foreground child, so
# #{pane_current_command} flickers bash/node — the tree stays stable.
set -uo pipefail

pane_pid="${1:-}"
pane_path="${2:-$PWD}"

# Host label: short hostname, "kernel-" prefix and dashes removed (kernel-dev-2 -> dev2).
host="$(hostname -s)"
host="${host#kernel-}"
host="${host//-/}"

emit() { printf '%s' "$1"; exit 0; }

# Not a Claude session -> just the host.
if [ -z "$pane_pid" ] || ! pstree "$pane_pid" 2>/dev/null | grep -qiw claude; then
  emit "$host"
fi

branch="$(git -C "$pane_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[ -z "$branch" ] && emit "$host · claude"

# Linear-style ticket id from the branch (igor/inf-2400-foo -> INF-2400).
ticket="$(printf '%s' "$branch" | grep -oiE '[a-z]{2,}-[0-9]+' | head -n1 || true)"
if [ -n "$ticket" ]; then
  label="$(printf '%s' "$ticket" | tr '[:lower:]' '[:upper:]')"
else
  label="claude"
fi

# Open-PR number, cached with a TTL. The network call never runs inline (it would
# stall the status redraw): a stale/missing cache fires a background refresh and
# this call renders whatever the cache holds.
#
# Cache lives in a mode-0700 user-private dir, never shared /tmp: the file content
# is read back as bash arithmetic, so a path another local user can pre-create or
# symlink is a code-execution vector. The key is a hash of repo root + exact
# branch, so different repos (or branch names that normalize alike) never collide.
ttl=60
cachedir="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-title"
mkdir -p "$cachedir" 2>/dev/null && chmod 700 "$cachedir" 2>/dev/null
repo="$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$pane_path")"
key="$(printf '%s\n%s' "$repo" "$branch" | { sha256sum 2>/dev/null || cksum; } | cut -d' ' -f1)"
cache="$cachedir/pr.$key"

now="$(date +%s)"
ts=0
pr=""
# Read cached "<ts> <pr>", but trust neither field: validate both as digits before
# the arithmetic (ts) or interpolation (pr) below.
if [ -f "$cache" ] && [ ! -L "$cache" ]; then
  read -r ts pr < "$cache" 2>/dev/null || { ts=0; pr=""; }
fi
case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
case "$pr" in ''|*[!0-9]*) pr="" ;; esac

if [ $(( now - ts )) -ge "$ttl" ]; then
  (
    n="$(cd "$pane_path" 2>/dev/null && timeout 6 gh pr view "$branch" \
          --json number,state --jq 'select(.state=="OPEN")|.number' 2>/dev/null || true)"
    case "$n" in *[!0-9]*) n="" ;; esac
    # Write atomically via a private temp file so a concurrent reader never sees a
    # half-written line and the final name is created by rename, not a followed symlink.
    tmp="$(mktemp "$cachedir/.pr.XXXXXX" 2>/dev/null)" || exit 0
    if printf '%s %s\n' "$(date +%s)" "$n" > "$tmp"; then
      mv -f "$tmp" "$cache" || rm -f "$tmp"
    else
      rm -f "$tmp"
    fi
  ) >/dev/null 2>&1 &
fi

if [ -n "$pr" ]; then
  emit "$host · $label · PR #$pr"
fi
emit "$host · $label"
