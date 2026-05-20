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

Install all skills to all detected agents without prompts:

```bash
npx skills add ikatkov/agent-skills --all
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

## Creating Skills

Each skill is a directory containing a `SKILL.md` file with YAML frontmatter:

```markdown
---
name: my-skill
description: What this skill does and when to use it.
---

# My Skill

Instructions for the agent to follow when this skill is activated.
```

Rules:

- Use lowercase, hyphenated names.
- Keep the directory name and frontmatter `name` the same.
- Keep skill-specific helper files inside that skill directory.
- Put larger reference material in `references/` and link to it from `SKILL.md`.
- Do not add a root-level `SKILL.md`; `skills/` is the canonical discovery path for this repository.

## Validation

Check that the CLI can discover every skill:

```bash
npx --yes skills add . --list
```

Check the published GitHub shorthand after pushing:

```bash
npx --yes skills add ikatkov/agent-skills --list
```

## Related Links

- [skills CLI](https://github.com/vercel-labs/skills)
- [skills.sh directory](https://skills.sh)
- [Agent Skills specification](https://agentskills.io)
