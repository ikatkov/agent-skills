#!/usr/bin/env python3
"""Batch geocode landmark queries via OpenStreetMap Nominatim.

Usage:
    python geocode.py "Lake Merritt, Oakland, CA" "Mission Dolores Park, San Francisco"

Prints one JSON object per line to stdout:
    {"query": "...", "lng": -122.x, "lat": 37.x, "display_name": "...", "address": "..."}
or, on failure:
    {"query": "...", "error": "no result"}

Respects Nominatim's 1 req/sec rate limit and sets a descriptive User-Agent
(required by their usage policy). Uses only Python stdlib — no pip install.
"""
import json
import sys
import time
import urllib.parse
import urllib.request

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
USER_AGENT = "claude-skill-generate-map/0.1 (one-off geocoding for personal map building)"
RATE_LIMIT_SECONDS = 1.1


def geocode(query: str) -> dict:
    params = {"q": query, "format": "json", "limit": 1, "addressdetails": 1}
    url = f"{NOMINATIM_URL}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        return {"query": query, "error": f"request failed: {e}"}

    if not data:
        return {"query": query, "error": "no result"}

    hit = data[0]
    addr = hit.get("address", {})
    parts = [
        addr.get("house_number"),
        addr.get("road"),
        addr.get("city") or addr.get("town") or addr.get("village"),
        addr.get("state"),
    ]
    short_address = ", ".join(p for p in parts if p)
    return {
        "query": query,
        "lng": float(hit["lon"]),
        "lat": float(hit["lat"]),
        "display_name": hit.get("display_name", ""),
        "address": short_address or hit.get("display_name", ""),
    }


def main(queries: list[str]) -> int:
    for i, q in enumerate(queries):
        if i > 0:
            time.sleep(RATE_LIMIT_SECONDS)
        result = geocode(q)
        print(json.dumps(result, ensure_ascii=False))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: geocode.py <query> [<query> ...]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
