#!/usr/bin/env python3
"""Video frame OCR using either a local multimodal LLM endpoint or Tesseract.

This script is intentionally self-contained so the video-feed-ocr skill does not
rely on scripts from other skills.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_ENDPOINT = "http://192.168.1.161:1234/v1/chat/completions"
DEFAULT_MODELS_ENDPOINT = "http://192.168.1.161:1234/api/v1/models"
DEFAULT_LOAD_ENDPOINT = "http://192.168.1.161:1234/api/v1/models/load"
HARDCODED_MODEL = "qwen/qwen3-vl-4b"
HARDCODED_CONTEXT_LENGTH = 32768
DEFAULT_TIMEOUT = 120
DEFAULT_LANG = "eng"
DEFAULT_PSM = 6
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


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, type=Path, help="Input video path")
    p.add_argument("--output-dir", required=True, type=Path, help="Output directory")
    p.add_argument("--fps", type=float, default=1.0, help="Frames per second to sample")
    p.add_argument(
        "--interval",
        type=float,
        help="Sample one frame every N seconds (mutually exclusive with --fps)",
    )
    p.add_argument("--frame-limit", type=int, default=0, help="Stop after N frames (0=all)")
    p.add_argument("--pattern", help="Optional regex filter written to ocr_hits.txt")
    p.add_argument("--fast", action="store_true", help="Use Tesseract OCR instead of LLM")
    p.add_argument("--lang", default=DEFAULT_LANG, help="Tesseract language (fast mode)")
    p.add_argument("--psm", type=int, default=DEFAULT_PSM, help="Tesseract PSM (fast mode)")
    p.add_argument(
        "--task-prompt",
        help="Optional OCR instruction prompt; defaults to built-in prompt",
    )
    p.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT,
        help="Request timeout seconds per frame",
    )
    return p.parse_args()


def require_cmd(name: str) -> None:
    if subprocess.run(["which", name], capture_output=True).returncode != 0:
        raise RuntimeError(f"Missing required command: {name}")


def mime_for(path: Path) -> str:
    mt, _ = mimetypes.guess_type(str(path))
    return mt or "application/octet-stream"


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("utf-8")


def post_json(endpoint: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
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
        raise RuntimeError(f"VLM HTTP {e.code}: {msg}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"VLM connection failed: {e}") from e


def get_json(endpoint: str, timeout: int) -> dict[str, Any] | list[Any]:
    req = urllib.request.Request(endpoint, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        msg = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"VLM HTTP {e.code}: {msg}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"VLM connection failed: {e}") from e


def _models_from_response(resp: dict[str, Any] | list[Any]) -> list[dict[str, Any]]:
    if isinstance(resp, list):
        return [m for m in resp if isinstance(m, dict)]
    if isinstance(resp, dict):
        data = resp.get("data")
        if isinstance(data, list):
            return [m for m in data if isinstance(m, dict)]
        models = resp.get("models")
        if isinstance(models, list):
            return [m for m in models if isinstance(m, dict)]
    return []


def _is_loaded(model_entry: dict[str, Any]) -> bool:
    if model_entry.get("loaded") is True:
        return True
    for key in ("state", "status"):
        value = model_entry.get(key)
        if isinstance(value, str) and value.lower() in {"loaded", "ready", "active"}:
            return True
    return False


def _loaded_context_length(model_entry: dict[str, Any]) -> int | None:
    for key in ("loaded_context_length", "context_length", "n_ctx"):
        value = model_entry.get(key)
        if isinstance(value, int):
            return value
    return None


def needs_context_reload(timeout: int) -> bool:
    resp = get_json(DEFAULT_MODELS_ENDPOINT, timeout)
    models = _models_from_response(resp)

    for model in models:
        if model.get("id") != HARDCODED_MODEL:
            continue
        if not _is_loaded(model):
            return True
        current_ctx = _loaded_context_length(model)
        if current_ctx == HARDCODED_CONTEXT_LENGTH:
            return False
        return True

    return True


def reload_model_with_large_context(timeout: int) -> dict[str, Any]:
    payload = {"model": HARDCODED_MODEL, "context_length": HARDCODED_CONTEXT_LENGTH}
    return post_json(endpoint=DEFAULT_LOAD_ENDPOINT, payload=payload, timeout=timeout)


def choice_text(outer: dict[str, Any]) -> str:
    return outer.get("choices", [{}])[0].get("message", {}).get("content", "")


def run_ocr_llm(
    *,
    image: Path,
    task_prompt: str,
    timeout: int,
) -> tuple[str, dict[str, Any]]:
    content: list[dict[str, Any]] = [
        {"type": "text", "text": task_prompt},
        {
            "type": "image_url",
            "image_url": {"url": f"data:{mime_for(image)};base64,{b64(image)}"},
        },
    ]
    payload = {
        "model": HARDCODED_MODEL,
        "temperature": 0,
        "messages": [{"role": "user", "content": content}],
        "response_format": {"type": "text"},
    }
    outer = post_json(endpoint=DEFAULT_ENDPOINT, payload=payload, timeout=timeout)
    return choice_text(outer).strip(), outer


def run_ocr_tesseract(*, image: Path, lang: str, psm: int, timeout: int) -> str:
    cmd = ["tesseract", str(image), "stdout", "-l", lang, "--psm", str(psm)]
    try:
        proc = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"tesseract timeout after {timeout}s") from e
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip()
        raise RuntimeError(stderr or "tesseract failed") from e
    return proc.stdout.strip()


def extract_frames(input_video: Path, frames_dir: Path, fps: float, interval: float | None) -> None:
    frames_dir.mkdir(parents=True, exist_ok=True)
    if interval is not None:
        vf = f"fps=1/{interval}"
    else:
        vf = f"fps={fps}"

    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(input_video),
        "-vf",
        vf,
        str(frames_dir / "frame_%05d.png"),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    args = parse_args()

    if args.interval is not None and args.fps != 1.0:
        raise SystemExit("Use either --fps or --interval (not both)")

    if not args.input.is_file():
        raise SystemExit(f"Input file not found: {args.input}")

    require_cmd("ffmpeg")
    if args.fast:
        require_cmd("tesseract")

    out_dir = args.output_dir
    if str(out_dir).startswith("/tmp/"):
        out_dir = Path("/private") / out_dir.relative_to("/")

    frames_dir = out_dir / "frames"
    work_dir = out_dir / "llm_work"
    text_dir = out_dir / "frame_text"
    raw_out = out_dir / "ocr_raw.txt"
    hits_out = out_dir / "ocr_hits.txt"

    out_dir.mkdir(parents=True, exist_ok=True)
    work_dir.mkdir(parents=True, exist_ok=True)
    text_dir.mkdir(parents=True, exist_ok=True)
    raw_out.write_text("")

    if not args.fast:
        # LM Studio context window is fixed at model load time.
        if needs_context_reload(args.timeout):
            reload_model_with_large_context(args.timeout)
        else:
            print(
                f"Model already loaded with context_length={HARDCODED_CONTEXT_LENGTH}; skipping reload."
            )

    extract_frames(args.input, frames_dir, args.fps, args.interval)

    frames = sorted(frames_dir.glob("frame_*.png"))
    if not frames:
        raise SystemExit("No frames were extracted. Check input and sampling options.")

    prompt = args.task_prompt or DEFAULT_OCR_PROMPT
    processed = 0

    with raw_out.open("a", encoding="utf-8") as raw_f:
        for frame in frames:
            processed += 1
            bn = frame.name
            frame_txt = text_dir / f"{frame.stem}.txt"
            frame_json = work_dir / f"ocr_{frame.stem}_response.json"

            try:
                if args.fast:
                    text = run_ocr_tesseract(
                        image=frame,
                        lang=args.lang,
                        psm=args.psm,
                        timeout=args.timeout,
                    )
                else:
                    text, outer = run_ocr_llm(
                        image=frame,
                        task_prompt=prompt,
                        timeout=args.timeout,
                    )
                    frame_json.write_text(
                        json.dumps(outer, ensure_ascii=False, indent=2),
                        encoding="utf-8",
                    )
            except Exception as exc:  # noqa: BLE001
                print(f"Warning: OCR failed for {bn}: {exc}", file=sys.stderr)
                continue

            frame_txt.write_text(text, encoding="utf-8")

            if text.strip():
                for line in text.splitlines():
                    raw_f.write(f"{bn}:{line}\n")

            if args.frame_limit and processed >= args.frame_limit:
                break

    if args.pattern:
        pattern = re.compile(args.pattern, re.IGNORECASE)
        matches: list[str] = []
        for i, line in enumerate(raw_out.read_text(encoding="utf-8").splitlines(), start=1):
            if pattern.search(line):
                matches.append(f"{i}:{line}")
        hits_out.write_text("\n".join(matches) + ("\n" if matches else ""), encoding="utf-8")

    print(f"Frames directory: {frames_dir}")
    print(f"Raw OCR output:  {raw_out}")
    if args.pattern:
        print(f"Filtered hits:   {hits_out}")
    print(f"Engine:          {'tesseract (fast)' if args.fast else 'llm'}")
    print(f"LLM work dir:    {work_dir}")
    print(f"Processed frames: {processed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
