---
name: gemini-unwatermark
description: Remove visible Gemini image watermarks from local image files. Use when the user wants an agent to clean one or more local Gemini-generated images and save de-watermarked output files.
---

# Workflow

1. Identify the input(s) from the user message — each input may be a file, a directory, or a quoted glob mask.
2. Run `scripts/clean.sh <input> [<input>...]`. Outputs are always written next to each input as `<slug>-clean.<ext>`; you do not need to pick output paths.
3. Report the final written file path(s).

Flags:

- `-r` / `--recursive` — recurse into subdirectories when an input is a directory.
- `-f` / `--overwrite` — overwrite existing `<slug>-clean.<ext>` outputs (default: skipped).

Examples:

```sh
scripts/clean.sh ./foo.png                 # single file
scripts/clean.sh ./photos                  # whole folder (non-recursive)
scripts/clean.sh -r ./photos               # recurse into subfolders
scripts/clean.sh './photos/IMG_*.png'      # glob mask (quote it)
scripts/clean.sh -f ./photos               # overwrite existing *-clean.* outputs
```

Files whose basename already ends in `-clean` and existing `<slug>-clean.<ext>` outputs are skipped by default.

The script auto-installs `@pilio/gemini-watermark-remover` globally on first run if `gwr` is not on `PATH`. If `npm`'s global bin directory is not on `PATH`, the script prints the directory and exits — instruct the user to add it to `PATH` and retry.
