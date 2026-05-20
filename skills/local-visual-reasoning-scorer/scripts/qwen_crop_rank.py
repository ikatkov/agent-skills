#!/usr/bin/env python3
"""Local LM Studio visual reasoning, OCR, and image scoring utility.

Supports three modes:
- ocr: extract text from a single image
- crop-rank: generate crop candidates from frames, then pick the best
- image-score: score/select the best from explicit image files
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DEFAULT_ENDPOINT = "http://192.168.1.161:1234/v1/chat/completions"
DEFAULT_MODEL = "qwen/qwen3-vl-4b"
DEFAULT_OCR_PROMPT = """Extract all text exactly as seen.
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

Return Markdown only."""


@dataclass
class Candidate:
    cid: str
    label: str
    raw_path: Path
    labeled_path: Path
    meta: dict[str, Any]


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def mime_for(path: Path) -> str:
    mt, _ = mimetypes.guess_type(str(path))
    return mt or "application/octet-stream"


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("utf-8")


def extract_json(text: str) -> dict[str, Any]:
    text = (text or "").strip()
    try:
        v = json.loads(text)
        if isinstance(v, dict):
            return v
    except json.JSONDecodeError:
        pass
    i, j = text.find("{"), text.rfind("}")
    if i >= 0 and j > i:
        v = json.loads(text[i : j + 1])
        if isinstance(v, dict):
            return v
    raise ValueError("Model response did not contain a JSON object.")


def add_overlay(src: Path, dst: Path, text: str) -> None:
    run(
        [
            "magick",
            str(src),
            "-gravity",
            "northwest",
            "-fill",
            "white",
            "-undercolor",
            "#000000AA",
            "-pointsize",
            "22",
            "-annotate",
            "+8+8",
            text,
            str(dst),
        ]
    )


def build_crop_candidates(
    frame_dir: Path, frame_ids: list[int], crops: list[str], out_dir: Path
) -> list[Candidate]:
    out_dir.mkdir(parents=True, exist_ok=True)
    out: list[Candidate] = []
    idx = 1
    for fid in frame_ids:
        src = frame_dir / f"frame_{fid:05d}.png"
        if not src.exists():
            raise FileNotFoundError(f"Frame not found: {src}")
        for crop in crops:
            cid = f"C{idx:02d}"
            raw = out_dir / f"{cid}_f{fid:05d}_{crop.replace('+', '_')}.png"
            labeled = out_dir / f"{cid}_labeled.png"
            run(["magick", str(src), "-crop", crop, "+repage", str(raw)])
            add_overlay(raw, labeled, f"{cid} | frame={fid:05d} | crop={crop}")
            out.append(
                Candidate(
                    cid=cid,
                    label=f"frame={fid:05d},crop={crop}",
                    raw_path=raw,
                    labeled_path=labeled,
                    meta={"frame_id": fid, "crop": crop},
                )
            )
            idx += 1
    return out


def build_image_candidates(images: list[Path], out_dir: Path) -> list[Candidate]:
    out_dir.mkdir(parents=True, exist_ok=True)
    out: list[Candidate] = []
    for idx, img in enumerate(images, start=1):
        if not img.exists():
            raise FileNotFoundError(f"Image not found: {img}")
        cid = f"C{idx:02d}"
        labeled = out_dir / f"{cid}_labeled{img.suffix.lower() or '.png'}"
        add_overlay(img, labeled, f"{cid} | {img.name}")
        out.append(
            Candidate(
                cid=cid,
                label=img.name,
                raw_path=img,
                labeled_path=labeled,
                meta={"image": str(img)},
            )
        )
    return out


def post_chat(endpoint: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"LM Studio HTTP {e.code}: {msg}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"LM Studio connection failed: {e}") from e


def choice_text(outer: dict[str, Any]) -> str:
    return outer.get("choices", [{}])[0].get("message", {}).get("content", "")


def call_vlm(
    endpoint: str,
    model: str,
    task_prompt: str,
    candidates: list[Candidate],
    timeout: int,
) -> dict[str, Any]:
    prompt = (
        "You are doing local visual reasoning and image scoring.\n"
        f"Task: {task_prompt}\n\n"
        "Instructions:\n"
        "1) Compare all candidate images carefully.\n"
        "2) Select the best candidate id.\n"
        "3) Score each relevant candidate from 0-100.\n"
        "4) Keep explanation short and concrete.\n\n"
        "Return strict JSON only:\n"
        "{\n"
        '  "best_id": "Cxx",\n'
        '  "scores": [{"id":"Cxx","score":0-100,"reason":"short"}],\n'
        '  "reason": "why best"\n'
        "}\n"
    )

    content: list[dict[str, Any]] = [{"type": "text", "text": prompt}]
    for c in candidates:
        content.append({"type": "text", "text": f"Candidate {c.cid}: {c.label}"})
        content.append(
            {
                "type": "image_url",
                "image_url": {
                    "url": f"data:{mime_for(c.labeled_path)};base64,{b64(c.labeled_path)}"
                },
            }
        )

    payload = {
        "model": model,
        "temperature": 0.1,
        "messages": [{"role": "user", "content": content}],
        "response_format": {"type": "text"},
    }
    outer = post_chat(endpoint=endpoint, payload=payload, timeout=timeout)
    return {"outer": outer, "parsed": extract_json(choice_text(outer))}


def call_ocr(
    endpoint: str,
    model: str,
    task_prompt: str,
    image: Path,
    timeout: int,
) -> dict[str, Any]:
    content: list[dict[str, Any]] = [
        {"type": "text", "text": task_prompt},
        {
            "type": "image_url",
            "image_url": {"url": f"data:{mime_for(image)};base64,{b64(image)}"},
        },
    ]

    payload = {
        "model": model,
        "temperature": 0,
        "messages": [{"role": "user", "content": content}],
        "response_format": {"type": "text"},
    }
    outer = post_chat(endpoint=endpoint, payload=payload, timeout=timeout)
    text = choice_text(outer).strip()
    return {"outer": outer, "text": text}


def add_base_flags(p: argparse.ArgumentParser, *, task_prompt_required: bool) -> None:
    p.add_argument("--endpoint", default=DEFAULT_ENDPOINT)
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--task-prompt", required=task_prompt_required)
    p.add_argument("--work-dir", type=Path, default=Path("analysis/local-visual-score"))
    p.add_argument("--timeout", type=int, default=120)


def add_score_flags(p: argparse.ArgumentParser) -> None:
    p.add_argument("--save-best", type=Path)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="mode", required=True)

    ocr = sub.add_parser("ocr", help="Extract text from a single image")
    ocr.add_argument("--image", type=Path, required=True)
    ocr.add_argument("--output", type=Path, help="Optional path for extracted OCR text")
    add_base_flags(ocr, task_prompt_required=False)

    crop = sub.add_parser("crop-rank", help="Generate crop candidates from frames and rank")
    crop.add_argument("--frame-dir", type=Path, required=True)
    crop.add_argument("--frame-ids", type=int, nargs="+", required=True)
    crop.add_argument("--crop", action="append", required=True)
    add_base_flags(crop, task_prompt_required=True)
    add_score_flags(crop)

    img = sub.add_parser("image-score", help="Score/rank explicit image files")
    img.add_argument("--image", action="append", type=Path, required=True)
    add_base_flags(img, task_prompt_required=True)
    add_score_flags(img)

    return p.parse_args()


def main() -> int:
    args = parse_args()
    args.work_dir.mkdir(parents=True, exist_ok=True)

    if args.mode == "ocr":
        if not args.image.exists():
            raise FileNotFoundError(f"Image not found: {args.image}")

        task_prompt = args.task_prompt or DEFAULT_OCR_PROMPT
        result = call_ocr(
            endpoint=args.endpoint,
            model=args.model,
            task_prompt=task_prompt,
            image=args.image,
            timeout=args.timeout,
        )

        key = args.image.stem.replace(" ", "_")
        response_path = args.work_dir / f"ocr_{key}_response.json"
        response_path.write_text(json.dumps(result["outer"], ensure_ascii=False, indent=2))

        text = result["text"]
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(text)

        summary: dict[str, Any] = {
            "mode": "ocr",
            "image": str(args.image),
            "output_file": str(args.output) if args.output else None,
            "response_file": str(response_path),
            "task_prompt": task_prompt,
            "text": text,
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0

    with tempfile.TemporaryDirectory(prefix="local_visual_score_") as td:
        tmp = Path(td)
        if args.mode == "crop-rank":
            candidates = build_crop_candidates(args.frame_dir, args.frame_ids, args.crop, tmp)
        else:
            candidates = build_image_candidates(args.image, tmp)

        result = call_vlm(
            endpoint=args.endpoint,
            model=args.model,
            task_prompt=args.task_prompt,
            candidates=candidates,
            timeout=args.timeout,
        )

        key = args.task_prompt.lower().replace(" ", "_")
        response_path = args.work_dir / f"{key}_response.json"
        response_path.write_text(json.dumps(result["outer"], ensure_ascii=False, indent=2))

        parsed = result["parsed"]
        best_id = parsed.get("best_id")
        if not isinstance(best_id, str):
            raise RuntimeError(f"Invalid best_id in model output: {parsed}")

        chosen = next((c for c in candidates if c.cid == best_id), None)
        if chosen is None:
            raise RuntimeError(f"Model selected unknown candidate '{best_id}'.")

        if args.save_best:
            args.save_best.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(chosen.raw_path, args.save_best)

        summary = {
            "mode": args.mode,
            "best_id": chosen.cid,
            "best_label": chosen.label,
            "best_meta": chosen.meta,
            "saved_to": str(args.save_best) if args.save_best else None,
            "reason": parsed.get("reason", ""),
            "scores": parsed.get("scores", []),
            "response_file": str(response_path),
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
