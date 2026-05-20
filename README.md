# Agent Skills

[![skills.sh](https://skills.sh/b/ikatkov/agent-skills)](https://skills.sh/ikatkov/agent-skills)

Personal AI agent skills packaged for the open `SKILL.md` format and installable with the `skills` CLI.

## Install

Install all skills:

```bash
npx skills add ikatkov/agent-skills
```

List available skills:

```bash
npx skills add ikatkov/agent-skills --list
```

Install one skill:

```bash
npx skills add ikatkov/agent-skills --skill yt-dlp
```

Install globally for Codex:

```bash
npx skills add ikatkov/agent-skills -g -a codex
```

## Skills

| Skill | Use |
| --- | --- |
| `conventional-commits` | Write conventional commit messages and changelog-friendly commit history. |
| `instagram-gallery-download` | Download Instagram post/carousel media with `gallery-dl`. |
| `local-visual-reasoning-scorer` | Run local OCR, image comparison, and visual reasoning workflows. |
| `media-archiver` | Convert a web page into an offline-ready local video gallery. |
| `obsidian-markdown` | Create and edit Obsidian Flavored Markdown. |
| `parakeet-mlx-transcribe` | Transcribe audio/video locally with `parakeet-mlx`. |
| `video-feed-ocr` | Extract visible text from sampled video frames. |
| `yt-dlp` | Download videos or extract audio/subtitles with `yt-dlp`. |

## Structure

Skills live under the standard `skills/` directory:

```text
skills/
  skill-name/
    SKILL.md
    references/  # optional
    scripts/     # optional
    examples/    # optional
```

Each `SKILL.md` has YAML frontmatter with `name` and `description`, followed by the instructions an agent should load when the skill is activated.
