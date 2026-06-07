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
