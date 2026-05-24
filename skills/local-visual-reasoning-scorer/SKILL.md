---
name: local-visual-reasoning-scorer
description: Run local multimodal visual reasoning, OCR and image scoring with local LLM models. Use only on macOS hosts where a local OpenAI-compatible visual LLM endpoint is already running and reachable. Use for image to text (OCR), ranking image candidates, selecting best frames/crops, detecting blurry or cut-off diagrams, and local-only visual QA workflows. Do not use on non-macOS systems or when the local visual LLM endpoint is unavailable.
---

# Local OCR and Visual Reasoning Scorer

## Overview

Use this skill for local OCR, image comparison, and image scoring tasks through local VLM models on macOS systems with a running local visual LLM endpoint.

Primary use cases:

- image-to-text conversion (OCR)
- score/rank multiple images for quality or task fit
- pick the best frame/crop for diagrams and screenshots
- avoid image-order confusion via overlaid candidate IDs
- keep visual reasoning local to your LM Studio endpoint

## Script

Use `scripts/local_visual_llm.py`.

Compatibility alias: `scripts/qwen_crop_rank.py` points to the same implementation.

## Execution Context

Before using this skill, verify the host is macOS and the configured local visual LLM endpoint is reachable:

```bash
test "$(uname -s)" = "Darwin"
curl -fsS http://192.168.1.161:1234/v1/models
```

If either check fails, do not use this skill. Tell the user that local visual reasoning requires macOS and a running local OpenAI-compatible visual LLM endpoint.

Run the scripts in an environment that can reach the local LLM endpoint. Restricted agent sandboxes may block local network access even when the endpoint works in a normal terminal session.

## Modes

### 1) `ocr`

Use when you need text extraction from one image.

```bash
python3 scripts/local_visual_llm.py ocr \
  --image /path/a.png \
  --output /path/output.txt
```

Default OCR prompt (used when `--task-prompt` is omitted):

```text
Extract all text exactly as seen.
Keep reading order.
Keep line breaks.
Do not paraphrase.
Do not translate.
If unsure add (?).
If unreadable write [illegible].

Use:
Paragraphs for normal text.
Bullets for obvious lists.
Tables only if clearly a table.

Return Markdown only.
```

You can override with a custom OCR prompt:

```bash
python3 scripts/local_visual_llm.py ocr \
  --image /path/a.png \
  --task-prompt "Extract only table text, preserve line breaks" \
  --output /path/output.txt
```

Behavior:

- prints JSON summary to stdout (includes extracted `text`)
- writes raw model response JSON to `--work-dir`
- writes plain OCR text to `--output` when provided

### 2) `image-score`

Use when you already have candidate image files.

```bash
python3 scripts/local_visual_llm.py image-score \
  --image /path/a.png \
  --image /path/b.png \
  --task-prompt "Pick the sharpest and most complete diagram" \
  --save-best /path/best.png
```

### 3) `crop-rank`

Use when candidates should be generated from frame + crop combinations.

```bash
python3 scripts/local_visual_llm.py crop-rank \
  --frame-dir analysis/ocr/frames \
  --frame-ids 19 20 21 22 23 \
  --crop 720x440+0+400 \
  --crop 720x450+0+390 \
  --task-prompt "Select best Parallel pattern crop with full diagram and no blur" \
  --save-best notes/assets/agentic-patterns/pattern-02-parallel.png
```

## Workflow

1. Use `ocr` for text extraction tasks.
2. Use `image-score` or `crop-rank` for selection/ranking tasks.
3. Provide a concrete `--task-prompt` with explicit criteria where needed.
4. Review JSON summary (`best_id`, `scores`, `reason`) for scoring modes.
5. Rerun with better candidates or prompt constraints if needed.

## Important Options

- `--endpoint`: local LM Studio chat endpoint (default `http://192.168.1.161:1234/v1/chat/completions`)
- `--model`: local model id (default `qwen/qwen3-vl-4b`)
- `--task-prompt`: scoring objective for ranking modes; optional custom OCR instruction for `ocr`
- `--save-best`: optional output path for selected winner (`image-score`, `crop-rank`)
- `--output`: optional output text path for OCR mode
- `--work-dir`: response log directory
- `--timeout`: request timeout in seconds

## Notes

- Ranking modes overlay stable IDs (`C01`, `C02`, ...) on each candidate to reduce multimodal image shuffle errors.
- Ranking modes expect model JSON and perform robust JSON extraction from textual output.
- OCR mode returns text directly and does not require ImageMagick overlays.
- If the execution environment blocks local LAN access, rerun in an environment with access to the local visual LLM endpoint.
