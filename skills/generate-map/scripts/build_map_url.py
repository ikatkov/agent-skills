#!/usr/bin/env python3
"""Encode a GeoJSON FeatureCollection (read from stdin) into a geojson.io URL.

Usage:
    cat fc.json | python build_map_url.py
    python build_map_url.py < fc.json

Prints the URL to stdout. If the URL is over 6000 chars, prints a warning to
stderr (some browsers/servers truncate long URLs in the address bar).
"""
import json
import sys
import urllib.parse

URL_PREFIX = "https://geojson.io/#data=data:application/json,"
LONG_URL_THRESHOLD = 6000


def main() -> int:
    raw = sys.stdin.read()
    try:
        fc = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"error: stdin is not valid JSON: {e}", file=sys.stderr)
        return 2

    if fc.get("type") != "FeatureCollection":
        print("error: input must be a FeatureCollection", file=sys.stderr)
        return 2

    compact = json.dumps(fc, ensure_ascii=False, separators=(",", ":"))
    encoded = urllib.parse.quote(compact, safe="")
    url = URL_PREFIX + encoded

    if len(url) > LONG_URL_THRESHOLD:
        print(
            f"warning: URL is {len(url)} chars (>{LONG_URL_THRESHOLD}); "
            "may be truncated by some browsers. Consider trimming descriptions.",
            file=sys.stderr,
        )

    print(url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
