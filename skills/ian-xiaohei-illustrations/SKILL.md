---
name: ian-xiaohei-illustrations
description: Generate Ian-style English article illustrations. Use for user requests that need weird, clean, hand-drawn body images, article illustrations, shot lists, or edit/remove-title tasks for English articles, posts, blogs, Notion docs, workflows, methods, structures, states, metaphors, or viewpoints. Default to the Xiaohei IP, pure white hand-drawn look, sparse red/orange/blue annotations, and a clean but imaginative visual style. Do not use for generic illustration, PPT, commercial brand art, children's cartoons, or non-Xiaohei image requests unless the user explicitly asks for Ian/Xiaohei style.
---

# Ian Xiaohei Weird Article Illustrations

Adapted from Ian's original skill (MIT). See `references/CREDITS.md`.

## Core Position

Design 16:9 horizontal article illustrations for English-language content. The goal is not commercial illustration, PPT infographic design, or cute cartoon art. Turn the article's key judgments, workflows, structures, states, or metaphors into a clean, weird, creative hand-drawn explainer that reads clearly without looking like a manual.

If the user asks for generic illustration, PPT or slide graphics, commercial brand art, children's cartoons, or non-Xiaohei images, do not force this style. Use this skill only if the user explicitly asks for Ian/Xiaohei style or accepts that direction.

Unless the user explicitly asks for another language, all handwritten annotations and labels on the image should be in English.

Default visual IP: Xiaohei, a black solid creature with white dot eyes, thin legs, a blank expression, and a serious but absurd attitude. Xiaohei must participate in the core action of the image, not stand at the side as decoration.

## Image Generation Capability

This skill designs the illustration and writes the final image prompt. Whether it can also render the pixels depends on the host agent:

- **Codex** has a built-in image tool (`image_gen`) and can generate images out of the box. In Codex, generate each image directly.
- **Every other agent (Claude Code, etc.) cannot generate images.** Do not attempt to call an image tool, fabricate a rendered file, or claim an image was produced. Instead, print the finished image prompt to the screen inside a copy-friendly code block and tell the user to paste it into ChatGPT (or another image model with GPT-Image / DALL·E) to generate the picture.

Decide this once, at the start of a `generate` request, and follow that path for every image. When in doubt about whether the host has a real image tool, assume it does not and use the copy-paste path.

## Reference Files

Read only the files required for the selected mode:

- `references/style-dna.md`: style DNA, colors, text, and bans.
- `references/xiaohei-ip.md`: Xiaohei's appearance, personality, action pool, and bans.
- `references/composition-patterns.md`: structure types, original metaphor rules, and repetition rules.
- `references/prompt-template.md`: single-image prompt template and copy-paste handoff.
- `references/qa-checklist.md`: generation checks and iteration rules.
- `assets/examples/`: low-frequency style calibration only. Do not copy these examples' compositions, objects, or labels.

Mode loading matrix:

- `plan_only`: read `references/composition-patterns.md`; read `references/style-dna.md` and `references/xiaohei-ip.md` only if the requested style or character behavior is unclear.
- `generate`: read `references/style-dna.md`, `references/xiaohei-ip.md`, `references/composition-patterns.md`, `references/prompt-template.md`, and `references/qa-checklist.md` before the first image.
- `edit`: read `references/prompt-template.md` and `references/qa-checklist.md`; read `references/xiaohei-ip.md` only for Xiaohei-involvement revisions.
- `save`: use the save rules in this file; read `references/qa-checklist.md` only if the generated files still need visual QA.
- `assets/examples/`: do not open by default. Open examples only when the user asks for style calibration, comparison, or a specific old case.

## Operating Modes

Choose exactly one mode from the user's request before acting:

- `plan_only`: the user asks to plan, analyze, design a shot list, or says not to generate yet.
- `generate`: the user asks to generate, produce, make, create, or design and generate images.
- `edit`: the user provides an image and asks to remove a title, fix wrong text, increase Xiaohei involvement, or revise the existing image.
- `save`: the user asks to organize, rename, export, or copy already-generated images into the workspace.

If a request combines modes, run them in this order: `plan_only` shot list -> `generate` images -> `edit` fixes -> `save` deliverables. Do not ask for confirmation between modes unless the user requested approval checkpoints.

## Workflow

### 1. Digest the Article

Read the user-provided article, link, Notion page, Markdown file, or screenshot. Extract:

- the core idea
- the paragraphs that create a cognitive turn
- the parts that are worth visualizing
- the parts that should remain text only

Do not average the coverage. Prefer cognitive anchor points such as the core judgment, two breakpoints, an input/output loop, a split path, a before/after contrast, a one-item-many-uses pattern, a handoff path, common pitfalls, or a character-state change.

### 2. Output a Shot List First

In `plan_only` mode, output only the shot list and do not generate or emit final image prompts. For each image, state:

- where it goes in the article
- the image topic
- the core meaning
- the structure type
- what Xiaohei is doing
- suggested elements
- suggested English labels

Default to 4-8 images. For short articles, 1-3 images may be enough. For long articles, do not casually exceed 9. Keep it lean; do not turn the article into an illustrated book.

### 3. Produce One Image at a Time

In `generate` mode, do not wait for confirmation. If the user does not give an image count, produce 3 images by default. Derive a compact image spec for every planned image. Handle each image separately; do not combine multiple images into one grid or collage.

Before the first image, if the host allows a short text response, show a compact spec table with these columns:

- `#`
- `placement`
- `core idea`
- `structure type`
- `Xiaohei action`
- `labels`

Keep the table short. It is a generation contract, not a discussion gate.

Each image should explain only one core structure. The prompt must include:

- 16:9 horizontal English article illustration
- pure white background
- black hand-drawn line art
- sparse red/orange/blue handwritten English annotations
- lots of empty white space
- Xiaohei as the core action subject
- no PPT look, no commercial illustration, no childish cuteness, no complex architecture, and no top-left type title

Then, per the **Image Generation Capability** decision:

- **On Codex:** call the built-in `image_gen` once per image using the assembled prompt.
- **On any other agent:** do not call an image tool. Print the full image prompt for each image in its own fenced code block (using the template in `references/prompt-template.md`), then tell the user: paste this prompt into ChatGPT to generate the image. If generating several images, output one numbered prompt block per image so each is easy to copy separately.

Do not copy old cases. The examples only show line density, whitespace, color restraint, and Xiaohei participation. Do not reuse known compositions such as conveyor-belt breakpoints, Xiaohei pulling a decision lever, Xiaohei as a funnel, Xiaohei cutting a fish, Xiaohei pulling a handoff path, Xiaohei pulling three information layers, the three-Xiaohei bridge/door/megaphone scene, the phrase toolbox, or the common-pitfall sign. Re-invent a strange but coherent metaphor from the current article each time.

### 4. Edit Existing Images

In `edit` mode, preserve the existing composition unless the user explicitly asks for a redesign. Use `references/prompt-template.md` for title-removal and Xiaohei-involvement prompts.

Editing an existing image requires an image tool. On Codex, apply the edit directly. On any other agent, print the edit prompt in a code block and tell the user to paste it into ChatGPT along with the original image.

For title or wrong-text removal:

- remove only the target text and its underline or local mark
- preserve characters, labels, paths, line style, aspect ratio, and quality
- do not add new text or objects

For Xiaohei-involvement revisions:

- keep the same core meaning
- make Xiaohei the action subject
- simplify labels before regenerating if text quality was the problem

### 5. Check and Iterate

After an image exists, check `references/qa-checklist.md`. If any of the following happen, regenerate or edit:

- Xiaohei is only decorative
- the frame is too full
- it looks too much like a flowchart or PPT
- there are too many labels or too much text
- a top-left title appears
- the style feels too cute, childish, or stiff
- the background is not clean white

On Codex, run QA against the images you generated and iterate directly. On other agents, you cannot see the ChatGPT output, so state the QA checklist the user should apply and offer to revise the prompt if a result misses a check.

Before the final handoff on Codex, produce a compact QA manifest for each generated or edited image. Include pass/fail notes for aspect ratio, white background, Xiaohei core action, label count/readability, no title, no old-case reuse, and saved path.

### 6. Save the Deliverable

`save` mode applies when local image files actually exist (Codex generation, or images the user has downloaded from ChatGPT and provided). Copy final PNGs under the current workspace root, not inside the installed skill bundle, unless the user explicitly gives a different destination. Use:

```text
<workspace-root>/assets/<article-slug>-illustrations/
```

If there is no detectable workspace root, ask for a destination before saving. If the user provides a destination folder, save there and preserve the same `<article-slug>-illustrations/` child folder pattern unless they asked for exact filenames.

Create `<article-slug>` from the article title or user-provided topic:

- lowercase ASCII
- replace spaces and punctuation with hyphens
- collapse repeated hyphens
- trim leading and trailing hyphens
- if no useful title exists, use `xiaohei-illustrations`

Use sequential names:

```text
01-topic-name.png
02-topic-name.png
```

For each topic name, use the same slug rules and keep it under 50 characters. If a target filename already exists, do not overwrite it unless the user explicitly asked for replacement. Instead append `-v2`, `-v3`, and so on.

Keep the original generated file. In the handoff, report absolute filesystem paths for saved files. If no local image files exist (for example, prompts were handed off for ChatGPT and the user has not returned the results), say there is nothing to save yet and explain that saving resumes once the user provides the generated PNGs.

## Output Format

Keep the pre-generation response short and precise.

On Codex, the post-generation handoff should include:

- how many images were generated
- what each image is for
- the QA manifest for each image
- where each file is saved
- which images are the most reliable and which are optional

On other agents, the handoff is the set of copy-ready prompt blocks plus a one-line instruction to paste each into ChatGPT, and a short note on what to check in the result.

Do not write long theory about the style; let the prompts and images do the work.
