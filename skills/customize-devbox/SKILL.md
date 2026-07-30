---
name: customize-devbox
description: Customize an Ubuntu host through SSH or a Docker Sandbox through sbx.
disable-model-invocation: true
---

# Customize Devbox

Run against an SSH-accessible Ubuntu host:

`scripts/customize_devbox.sh <ssh-target>`

Run against a Docker Sandbox:

`scripts/customize_devbox.sh --sbx <sandbox-name>`

Use `sbx ls` to find sandbox names.

## What it installs

rsub, tmux (+ tpack plugins), a `~/.bashrc` tmux auto-attach block, and a tmux
config that drives the parent terminal (iTerm2) tab title from `~/.tmux/bin/title.sh`.
The title reads `<host>`, `<host> · TICKET` when a Claude session runs in the pane,
and `<host> · TICKET · PR #n` when the branch has an open PR (needs `git` + an
authenticated `gh`; degrades to the bare hostname otherwise).

Editing the title format: `assets/tmux.conf` and `assets/title.sh` are the source
of truth — the script copies them verbatim, so change them here, not on a devbox.
