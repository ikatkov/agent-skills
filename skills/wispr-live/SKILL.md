---
name: wispr-live
description: Read the live transcript of a meeting that Wispr Flow is recording on this Mac, while it happens. Finds the active recording automatically and streams each new line as it lands. macOS only. Use when asked to "use wispr-live", "read the live transcript", "read live streaming", "watch the meeting", "follow the call", or to react to what is being said in an ongoing Wispr Flow meeting.
---

# Read a live Wispr Flow transcript

Wispr Flow appends each finished utterance of a meeting to
`~/Library/Application Support/Wispr Flow/meetings/<meeting-id>/live.ndjson`. The bundled
`wispr-live` command finds the meeting that is recording now and prints it as readable lines:

```text
=== Weekly sync | recording | 3f9c2d1e-7a4b-4c0e-9d2f-1b5e6a8c4d7f ===
[16:47] mic 1: How would you improve the priority system?
[16:58] call 1003 (Alex): I would track how often each notification gets acted on.
[17:20] -- recording paused --
=== recording ended: Weekly sync ===
```

Set `W` at the start of every shell call (harness shells may not share state):

```bash
W="/absolute/path/to/wispr-live/scripts/wispr-live"   # the directory holding this SKILL.md
```

## Commands

| Command | Does |
| --- | --- |
| `"$W" --status` | Shows which meeting would be read: state, title, file, line count, last timestamp. |
| `"$W" --once` | Prints the transcript so far, then exits. |
| `"$W" --once --since 21:43` | Prints from the first line at or after `21:43`, then exits. |
| `"$W"` | Follows the recording: prints everything so far, then each new line. Moves on to the next meeting when one starts. |
| `"$W" --since 21:43` | Follows, starting at `21:43`. |
| `"$W" --meeting <id-prefix>` | Reads a specific meeting instead of the active one. |
| `"$W" --path` | Prints the path of the meeting's `live.ndjson`. |

Exit code 3 means this is not macOS or Wispr Flow is not installed. Exit code 4 means there is
no meeting to read.

## Workflow

1. Run `"$W" --status` first.
   - Exit code 3: **stop**. Tell the user this skill needs macOS with Wispr Flow installed,
     and quote the error. Do not look for transcripts another way.
   - `state: ended`: no meeting is recording now. Tell the user, and ask whether to read the
     last meeting (shown by `--status`) or wait for a recording to start.
   - Check the title is the meeting the user means.
2. Catch up: `"$W" --once`. For a long meeting, read `"$W" --once | tail -n 200` first and the
   rest only if needed.
3. Stream: start a Monitor with command `"$W" --since <last timestamp you read>`,
   description `live transcript: <title>`, and the longest timeout allowed (30 minutes). Each
   batch of new lines arrives as one event, about every 10 seconds.
4. When the Monitor expires, start it again with `--since` set to the last timestamp you saw.
   You see that line again; skip it.
5. On `=== recording ended ... ===`, stop the Monitor. A few minutes after the meeting, Wispr
   Flow writes `refined.ndjson` next to `live.ndjson` (`--status` shows the path). It has a
   cleaned-up transcript and better speaker splits. Prefer it for anything written after the
   meeting.

Without a Monitor tool, poll `"$W" --once --since <last timestamp>` every 15–30 seconds.

## Reading the lines

- **Lag.** Lines land in batches about every 10 seconds, 5–20 seconds after they were spoken.
  The Wispr Flow window shows words while they are spoken; the file only gets finished lines.
  Nothing reads them faster.
- **Speakers.** `mic N` is this Mac's microphone, usually the user. When several people share
  the room, Wispr Flow splits them into `mic 1`, `mic 2`, and so on. `call N` is audio from the
  call. The name in brackets is Wispr Flow's live guess and is often wrong: one voice can
  carry several names, and one name can land on several voices. Go by the number and the
  content, not the name.
- **Timestamps** are minutes:seconds since the recording started. Pause markers use the
  clock time instead (`7:01pm`).

## Rules

- Read only. Never write, move, or delete anything in the Wispr Flow folder.
- The transcript holds other people's words. Keep it on this machine. Do not paste it into
  external services unless the user asks.
- An agent on another host (a VM, a remote box) cannot see these files. Run this on the Mac
  that runs Wispr Flow.
