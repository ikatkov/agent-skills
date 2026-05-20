---
name: instagram-gallery-download
description: Download Instagram post/carousel media from URLs matching instagram.com/p/<code>/ using gallery-dl. Use only when the user provides a post URL in /p/ form and asks to download that media with metadata/tags. Do not use for instagram.com/reel/<code>/ or instagram.com/reels/<code>/; use the yt-dlp skill for those.
---

# Instagram Gallery Download

Use this skill to run `gallery-dl` for Instagram post/carousel URLs in `/p/` form.

## Quick Start

1. Use the helper script for consistent defaults:
   - `scripts/download_instagram_gallery.sh 'https://www.instagram.com/p/<code>/'`
2. For login-required content, pass browser cookies:
   - `scripts/download_instagram_gallery.sh '<instagram-url>' --cookies-browser chrome`

## Execution Context

Always run this skill in escalation permission mode.

Required for every invocation:
- `sandbox_permissions`: `"require_escalated"`
- Run `gallery-dl` commands outside the Codex sandbox (escalated permissions).

## Workflow

1. Validate URL shape:
   - Supported: `https://www.instagram.com/p/<code>/`
   - Not supported by this skill: `.../reel/...` and `.../reels/...` (route to `yt-dlp`)
2. Choose output folder (default: current directory).
3. Run the helper script with `sandbox_permissions: "require_escalated"`.
4. Verify output files and `.json` metadata sidecars.

## Command Patterns
Recommended - with cookies

Instagram often blocks direct downloads with redirect to login page. Always use browser cookies:

- Basic:
  - `scripts/download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/'`
- With cookies:
  - `scripts/download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/' --cookies-browser chrome`
- Pass-through gallery-dl flags:
  - `scripts/download_instagram_gallery.sh 'https://www.instagram.com/p/POST_ID/' -- -R 2 --sleep 1-3`

## Routing Rule

- If URL matches `instagram.com/reel/<code>/` or `instagram.com/reels/<code>/`, use the `yt-dlp` skill instead of this skill.

It enables:
- tag text files
   - JSON metadata sidecars
- archive tracking file (`.gallery-dl-archive.sqlite3`) to reduce duplicates

## Troubleshooting

1. Redirect to login page:
   - Retry with `--cookies-browser` using a logged-in browser profile.
2. No new downloads:
   - Expected when archive tracking sees already-downloaded items.
   - Use a new output directory if re-download is required.
3. Rate limiting:
   - Add delay/retry flags via pass-through options (after `--`).

## Resources

- Script runner: `scripts/download_instagram_gallery.sh`
- Extra examples/options: `references/gallery-dl-instagram.md`
