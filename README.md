# Agentic Skills Collection

This repository contains my own skills designed to expand the capabilities of AI coding assistants

## Compatibility & Invocation

These skills follow the universal **SKILL.md** format and work with any AI coding assistant that supports agentic skills.

| Tool            | Type | Invocation Example                | Path              |
| :-------------- | :--- | :-------------------------------- | :---------------- |
| **Claude Code** | CLI  | `>> /skill-name help me...`       | `.claude/skills/` |
| **Gemini CLI**  | CLI  | `(User Prompt) Use skill-name...` | `.gemini/skills/` |
| **Antigravity** | IDE  | `(Agent Mode) Use skill...`       | `.agent/skills/`  |
| **Cursor**      | IDE  | `@skill-name (in Chat)`           | `.cursor/skills/` |

---

## How to Use

1. **Clone the repository** to your agent's skill directory:
   ```bash
   git clone https://github.com/ikatkov/agent-skills.git .agent/skills
   ```

2. **Invoke a skill** by name in your chat or CLI:
   > "Use the **media_archiver** skill to archive https://example.com/videos"

## Installation

To use these skills with your favorite AI assistant, simply point it to the directory where you cloned this repository. Most tools look for skills in `.agent/skills/` or similar hidden directories in your project root.

