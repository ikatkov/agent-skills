#!/usr/bin/env bash
# Compute the iTerm2 tab title for the active tmux pane.
#
# tmux calls this from `set-titles-string` via a #() job and forwards the output
# to the outer terminal (iTerm2) as an OSC title. Invoked with the active pane's
# pid and working directory:
#
#     set -g set-titles-string "#(~/.tmux/bin/title.sh #{pane_pid} '#{pane_current_path}')"
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

# Open-PR number for the branch, cached per-branch with a TTL. The network call
# never runs inline (it would stall the status redraw): a stale/missing cache
# fires a background refresh and this call renders whatever the cache holds.
ttl=60
safe="$(printf '%s' "$branch" | tr -c 'A-Za-z0-9' '_')"
cache="${TMPDIR:-/tmp}/tmux-title-pr.$(id -u).$safe"
now="$(date +%s)"
ts=0
pr=""
if [ -f "$cache" ]; then
  read -r ts pr < "$cache" 2>/dev/null || { ts=0; pr=""; }
fi
if [ $(( now - ${ts:-0} )) -ge "$ttl" ]; then
  (
    n="$(cd "$pane_path" 2>/dev/null && timeout 6 gh pr view "$branch" \
          --json number,state --jq 'select(.state=="OPEN")|.number' 2>/dev/null || true)"
    printf '%s %s\n' "$(date +%s)" "$n" > "$cache"
  ) >/dev/null 2>&1 &
fi

if [ -n "$pr" ]; then
  emit "$host · $label · PR #$pr"
fi
emit "$host · $label"
