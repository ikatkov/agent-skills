---
name: record-web-journey
description: Record a web journey as evidence - a WebM video, a screenshot after every click and page load with a red marker at the click point, and a steps.md log. Works two ways - an agent drives the browser itself through agent-browser over CDP, or a human clicks through a Playwright-launched window while the script records. Use when asked to "record a web journey", "record the flow", "capture a user flow", "show me what you clicked", or when a walkthrough needs screenshots and video as proof.
---

# Record a web journey

Produces `<out>/<NAME>-<timestamp>/` with `steps.md`, `screenshots/NNN-<kind>-<label>.png`, and
`videos/*.webm`. Typed values and query strings are never logged.

## Setup (once per machine)

```bash
scripts/setup.sh
```

Installs Playwright next to the recorder, its ffmpeg helper for video, and a Chromium only when
Google Chrome is absent. Prefer `--chrome` when Google Chrome exists: it looks like a normal
browser to sign-in pages.

## Agent-driven recording (you drive)

Parse the request into: start URL, recording NAME, and the steps to perform.

1. Check the host. `pgrep -a Xvnc` or `echo $DISPLAY` tells you whether a desktop exists; if
   it does, `export DISPLAY=<it>` in every shell call and the human can watch live. Without a
   display add `--headless`. Check `df -h /dev/shm`; remount to 2G if it is 64M or Chrome
   renderers crash. Never close or kill other agents' browsers.
2. Start the recorder in the background with a CDP port nobody else uses:

   ```bash
   node scripts/record-flow.mjs <url> -name "<NAME>" --chrome --cdp 9333 > /tmp/record-flow.log 2>&1 &
   sleep 7 && grep -v dbus /tmp/record-flow.log   # prints the recording dir
   ```

   Pass `--profile <dir>` for a signed-in journey (see `references/auth-and-bot-checks.md`).
3. Attach agent-browser to that Chrome with a unique session name and drive as usual:

   ```bash
   agent-browser --session rec-<NAME> --cdp 9333 snapshot -i -u
   agent-browser --session rec-<NAME> --cdp 9333 click @e5
   ```

   Every command needs both `--session` and `--cdp`. Do not `open` a new URL unless the step
   is a navigation; the recorder already loaded the start URL.
4. Pace like a person: about a second between actions, `wait --load networkidle` after
   navigations. Each screenshot is taken 250 ms after the click, so back-to-back clicks blur
   which screenshot belongs to which step.
5. For anything below the fold: `scrollintoview @ref`, then `wait 1000`, then `click @ref`.
   Sites with `scroll-behavior: smooth` animate the scroll, and agent-browser's own
   scroll-then-click reads coordinates mid-animation, so the click lands on nothing and logs
   "(no visible target)" (verified on claude.ai). Use refs from `snapshot -i` rather than
   `find text`, and click visible targets: a visually hidden 1x1 input logs the same way.
6. Finish: `agent-browser --session rec-<NAME> close`, then `touch <recordingDir>/STOP` and
   wait for "Saved N visual steps" in the log. The video is only finalized after STOP.
7. Annotate `steps.md`: under each step add one line of what you observed (copy shown, API
   responses seen in `agent-browser network requests`, anything that contradicts the
   expectation). The log records clicks; you record meaning. Then report the folder path,
   the step count, and anything that blocked a step.

## Human-driven recording (a person drives)

```bash
node scripts/record-flow.mjs https://app.example.com/ -name "F06" --chrome --profile .context/chrome-profile
```

The person uses the window normally and presses Enter in the terminal when done. Give the
resulting folder to an agent and ask it to start with `steps.md`.

## Flags

| Flag | Meaning |
| --- | --- |
| `-name "<NAME>"` | Folder prefix, e.g. `F06-custom-mcp-<timestamp>` |
| `--chrome` | Use installed Google Chrome (recommended when present) |
| `--profile <dir>` | Reuse a Chrome user-data dir so sign-ins survive between recordings |
| `--cdp <port>` | Expose CDP so an agent can attach with `agent-browser --cdp <port>` |
| `--headless` | No window; video and screenshots still produced |
| `--out <dir>` | Parent directory, default `.context/flow-recordings` |
| `--viewport WxH` | Viewport and video size, default `1440x900` |
| `--sign-in` | With `--profile`: open plain Chrome to pass a bot check or sign in, then quit |

Ending signals: Enter (TTY), `STOP` file, browser close, SIGTERM. Only Enter or STOP lets
Playwright finalize the video cleanly.
