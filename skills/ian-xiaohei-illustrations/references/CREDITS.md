# Credits

This skill is an adaptation of the **Ian Xiaohei Illustrations** skill created by Ian, repackaged for the open `SKILL.md` format.

- Original project: <https://github.com/helloianneo/ian-xiaohei-illustrations>
- English adaptation this was derived from: <https://github.com/tojileon/ian-xiaohei-illustrations-en>
- Author: Ian — <https://github.com/helloianneo> · <https://x.com/ianneo_ai> · <https://www.ianneo.xyz>

Licensed under the MIT License, Copyright (c) 2026 Ian.

The recurring character "Xiaohei" and the bundled calibration images in `assets/examples/` are Ian's work, included as style-calibration samples. Please keep attribution to Ian when redistributing.

## Changes in this repackage

- Restructured into the `skills/<name>/SKILL.md` + `references/` layout.
- Corrected the image-generation assumption: only **Codex** generates images out of the box via its built-in `image_gen` tool. On every other agent (Claude Code, etc.) the skill prints the finished image prompt to the screen and asks the user to copy-paste it into ChatGPT to generate the picture.
