# AGENTS.md

Guidance for AI coding agents working on this skill collection.

## Project Overview

This repository publishes personal agent skills through `skills.sh`.

Install command:

```bash
npx skills add ikatkov/agent-skills
```

## Repository Structure

```text
skills/
  skill-name/
    SKILL.md
    references/  # optional supporting docs
    scripts/     # optional helper scripts
    examples/    # optional examples or templates
```

Do not add a root-level `SKILL.md`. The repository intentionally uses `skills/` as the canonical discovery path so the `skills` CLI lists all skills normally.

## Commands

| Command | Purpose |
| --- | --- |
| `npx --yes skills add . --list` | Verify local skill discovery. |
| `npx --yes skills add ikatkov/agent-skills --list` | Verify the published GitHub shorthand after pushing. |
| `git diff --check` | Check for whitespace errors before committing. |

## Skill Authoring Rules

- Skill directories use lowercase hyphenated names.
- Frontmatter `name` must match the directory name.
- Frontmatter must include string `name` and `description` fields.
- Keep skill-specific files inside the skill directory.
- Use `references/` for detailed docs that should be loaded only when needed.
- Use `scripts/` for repeatable helper commands rather than embedding long scripts in `SKILL.md`.
- Keep `SKILL.md` focused on when to use the skill and the workflow the agent should follow.

## Before Finishing

Run:

```bash
npx --yes skills add . --list
git diff --check
```

If the change is already pushed or is intended for immediate publication, also run:

```bash
npx --yes skills add ikatkov/agent-skills --list
```
