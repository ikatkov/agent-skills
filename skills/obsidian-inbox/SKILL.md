---
name: obsidian-inbox
description: Process an unsorted raw markdown note dropped in /Users/ikatkov/Obsidian/Default/inbox/ — classify it (movie / book / idea / poses / travel / new category), reformat per the matching per-folder conventions, rename and prefix images for vault-wide uniqueness, then file it into the correct subfolder. Use when the user says "sort my inbox", "process the new note in inbox", "file this", or drops a raw note + URL/screenshots in /Users/ikatkov/Obsidian/Default/inbox/ and asks to clean it up.
---

# Obsidian Inbox Skill

Processes unsorted notes in `/Users/ikatkov/Obsidian/Default/inbox/` into properly-formatted notes in the correct subfolder.

## When to invoke

- User drops a raw `.md` file in `/Users/ikatkov/Obsidian/Default/inbox/` (containing a URL, pasted text, optionally images) and asks to process it.
- User says any of: "sort my inbox", "file this", "clean up the new note", "process inbox".
- User explicitly invokes via `/obsidian-inbox` or `Skill` tool.

If multiple unsorted files exist, ask which one (or "all").

## Workflow

### 1. Read the vault entry point

Read `/Users/ikatkov/Obsidian/Default/inbox/CONVENTIONS.md` first. It's the source of truth for the workflow, shared rules (image-filename uniqueness, frontmatter dates, language preservation), and the table of subfolders → convention docs. The skill instructions you're reading now are the trigger / driver; the vault file is the data.

### 2. Locate the unsorted note

`ls /Users/ikatkov/Obsidian/Default/inbox/*.md` — any `.md` files at the root of `inbox/` (not inside a subfolder) are unsorted. Also list any loose images (`.webp`, `.png`, `.jpg`) at the root in case they belong to the note.

### 3. Read the raw note + classify

Read the raw note. Apply the classification heuristics from `inbox/CONVENTIONS.md`:

| Signals                                                                         | Folder    |
| ------------------------------------------------------------------------------- | --------- |
| Title with year in parens, IMDb URL, director / cinematographer mentioned       | `movies/` |
| Goodreads URL, author dominant, pages / publisher                               | `books/`  |
| Instagram reel + "poses" / "позы" + numbered figure references                  | `poses/`  |
| Instagram reel + place names / route / map / restaurants / "road trip"          | `travel/` |
| Instagram reel / blog / GitHub URL describing a tool / technique / workflow     | `ideas/`  |

If none fit, ask the user whether to create a new subfolder; if yes, also generate a new `conventions.md` for it using the existing ones as a template.

### 4. Read the matching conventions

Read `/Users/ikatkov/Obsidian/Default/inbox/<folder>/conventions.md`. It contains the exact frontmatter shape, body sections, image widths, and tag rules you must follow — do not invent.

### 5. Gather any external info needed

- **Movies**: fetch IMDb (title, year, director, cinematographer, country, genre). If the raw note already has these, skip.
- **Books**: fetch Goodreads (rating, ratings_count, pages, blurb). Required.
- **Poses / travel / ideas**: if the source is an Instagram reel and the raw note doesn't already include stills, use `yt-dlp` (for reels) or `instagram-gallery-download` (for `/p/` posts) skills to pull media. For poses, follow the frame-selection rule in `poses/conventions.md` (darker graded final-pose frames, not demo/motion frames with numbered badges).

### 6. Process images

For every image that will end up in the new note:

1. Convert to `.webp` if not already: `magick input.jpg -quality 85 output.webp`. Delete the original.
2. Choose a **vault-globally-unique filename**. Prefix with a category slug or note slug — never use generic `cover.webp` / `poster.webp` / `screenshot.webp`. The exact naming pattern is in the matching `conventions.md` (e.g. movies use `<film-slug>.webp`, travel uses `<region-slug>-NN.webp`).
3. Verify uniqueness: `find /Users/ikatkov/Obsidian/Default -name "<new-filename>"` should return zero matches.
4. Move into `<folder>/attachments/<note-slug>/`.

### 7. Generate the final note

Write the new `.md` file directly into `<folder>/`, following the matching `conventions.md` precisely:

- Frontmatter shape per the convention (date created/modified to current time in `Month Dth YYYY, h:mm:ss am/pm` format).
- Image embeds with the correct width (`|200`).
- Tag taxonomy from that folder's convention. Do not invent new top-level namespaces. No `inbox/*` tags, no year-as-tag.
- Body structure (sections, headings) exactly as the convention specifies.
- Language: keep source language for `title:`, `summary:`, and body.

### 8. Clean up

- Delete the original raw `.md` from `inbox/` root **only after confirming with the user** that the new note looks right.
- Delete any temp / original-format images.
- If a new subfolder was created, ensure its `conventions.md` is in place and the row in `inbox/CONVENTIONS.md` is updated.

## Failure modes to avoid

- **Generic image filenames.** This is the single biggest pitfall — Obsidian wikilinks collide across the whole vault by filename alone. Always prefix.
- **Inventing new tags.** Use the namespaces in the folder's `conventions.md`. If you genuinely need a new tag, surface it to the user before writing.
- **Translating Russian titles / summaries.** Russian source → Russian text. Don't be helpful by Englishifying.
- **Skipping Goodreads enrichment for books.** Required step, not optional.
- **Deleting the raw inbox file before the user has eyeballed the result.** Always confirm.

## References

- Vault entry point: `/Users/ikatkov/Obsidian/Default/inbox/CONVENTIONS.md`
- Per-folder conventions:
  - `inbox/movies/conventions.md`
  - `inbox/books/conventions.md`
  - `inbox/ideas/conventions.md`
  - `inbox/poses/conventions.md`
  - `inbox/travel/conventions.md`
