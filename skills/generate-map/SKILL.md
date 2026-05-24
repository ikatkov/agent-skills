---
name: generate-map
description: Turn free-form text mentioning geographical landmarks (parks, restaurants, museums, viewpoints, monuments, neighborhoods, trails, etc.) into a rich GeoJSON FeatureCollection and a clickable geojson.io URL the user can open to see all the places on a map. Use this skill whenever the user pastes a list, itinerary, travel guide, blog excerpt, recommendation thread, or any text that names multiple real-world places and wants to "see them on a map", "make a map", "plot these", "get a map link", "geojson", "geojson.io", or anything similar — even if they don't explicitly use the word "map". Also use it when the user provides a single curated trip and wants a shareable visualization.
---

# generate-map

Turn unstructured text that names real-world places into a richly-annotated map link.

## What this skill produces

A single message containing:
1. The geojson.io URL (clickable, opens straight to the map with markers)
2. A short summary of how many landmarks were plotted and any that couldn't be located

The GeoJSON itself is embedded in the URL — no file is saved unless the user asks.

## Output Feature schema

Each landmark becomes one Point Feature with this exact shape:

```json
{
  "type": "Feature",
  "properties": {
    "name": "Oakland Temple Hill Gardens",
    "description": "Serene temple gardens in the Oakland Hills with manicured blooms, reflecting pools, and sweeping Bay views. Best in spring evenings for golden light and cherry blossoms.",
    "address": "4770 Lincoln Ave, Oakland, CA",
    "hours": "Open daily: ~9 AM – 9 PM",
    "best_time": "Spring evenings for golden light + cherry blossoms",
    "maps_url": "https://www.google.com/maps/search/?api=1&query=Oakland%20Temple%20Hill%20Gardens%204770%20Lincoln%20Ave%20Oakland%20CA",
    "directions_url": "https://www.google.com/maps/dir/?api=1&destination=Oakland%20Temple%20Hill%20Gardens%204770%20Lincoln%20Ave%20Oakland%20CA",
    "reviews_url": "https://www.google.com/maps/search/?api=1&query=Oakland%20Temple%20Hill%20Gardens%204770%20Lincoln%20Ave%20Oakland%20CA",
    "marker-color": "#e377c2",
    "marker-size": "medium",
    "marker-symbol": "garden"
  },
  "geometry": {
    "type": "Point",
    "coordinates": [-122.1866, 37.8079]
  }
}
```

GeoJSON coordinates are **[longitude, latitude]** — easy to flip, double-check.

## Workflow

### 1. Extract landmark names

Read the input and pull out every distinct real-world place the user is asking about. Don't include vague references ("a coffee shop downtown") — only nameable, geocodable places. If the text already gives a clear list, use it as-is. If it's prose, extract the proper nouns.

If the input has city/region context (e.g. "my Oakland day trip"), keep that context — it improves geocoding accuracy and disambiguates common names.

### 2. Geocode each landmark

Use `scripts/geocode.py` to look up coordinates and address via OpenStreetMap Nominatim. The script handles user-agent headers, the 1 req/sec rate limit, and returns `[lng, lat, display_name]` for each query.

```bash
python scripts/geocode.py "Oakland Temple Hill Gardens, Oakland, CA" "Lake Merritt, Oakland, CA"
```

Output is JSON to stdout, one object per query. Pass each landmark with whatever city/region context you have — "Lake Merritt" alone is ambiguous, "Lake Merritt, Oakland, CA" is not.

If a landmark can't be geocoded, note it and continue — don't fail the whole batch. Report which ones failed at the end.

### 3. Enrich each landmark via web search

For each successfully-geocoded landmark, use WebSearch (or WebFetch on a likely page) to ground the metadata fields. You're looking for:
- A 1–2 sentence evocative `description` (what makes this place worth visiting; sensory or experiential)
- `hours` (operating hours if applicable; "Open 24/7" for parks/viewpoints; "N/A" for natural features)
- `best_time` (when it's most worth visiting — golden hour, season, weekday vs. weekend)

Don't fabricate hours. If a quick search doesn't surface them, write "Hours unknown — check before visiting" rather than inventing. The description and best_time can lean on general knowledge if web search doesn't return useful results.

### 4. Pick marker styling

Infer the landmark category from name, address, and what the search returned. Map category → marker symbol + color. Use the [Maki icon set](https://labs.mapbox.com/maki-icons/) — geojson.io renders these.

Common mappings:

| Category | marker-symbol | marker-color |
|---|---|---|
| Garden, park, botanical | `garden` or `park` | `#2ca02c` (green) |
| Restaurant, cafe | `restaurant` or `cafe` | `#ff7f0e` (orange) |
| Museum, gallery | `museum` or `art-gallery` | `#1f77b4` (blue) |
| Viewpoint, overlook | `viewpoint` | `#9467bd` (purple) |
| Monument, landmark | `monument` | `#8c564b` (brown) |
| Beach | `beach` | `#17becf` (teal) |
| Mountain, peak | `mountain` | `#7f7f7f` (gray) |
| Religious site | `religious-jewish`/`religious-christian`/`religious-muslim` | `#e377c2` (pink) |
| Bar, nightlife | `bar` | `#d62728` (red) |
| Shop, market | `shop` | `#bcbd22` (olive) |
| Trail, hiking | `triangle` | `#2ca02c` (green) |
| Default / unknown | `marker` | `#7f7f7f` (gray) |

If the input has a natural grouping (e.g. "morning stops" vs "afternoon stops", or "must-see" vs "optional"), use color to encode that grouping instead of category — it's usually more useful for the map's reader. Mention which encoding you chose in the summary.

`marker-size` is `medium` by default. Use `large` for headline stops if the user implies a hierarchy.

### 5. Build the URL

Use `scripts/build_map_url.py` — it takes a FeatureCollection JSON on stdin and prints the geojson.io URL. It URL-encodes the JSON and prepends `https://geojson.io/#data=data:application/json,`.

```bash
echo '<feature-collection-json>' | python scripts/build_map_url.py
```

If the resulting URL is over ~6000 characters, geojson.io may struggle in some browsers. The script warns on stderr if you hit that. For very large maps (20+ landmarks with long descriptions), consider trimming descriptions or splitting into multiple maps — and tell the user what you did.

### 6. Present to the user

Reply with:
- The URL on its own line so it's clickable
- A 1–2 line summary: how many landmarks, any that failed to geocode, what the marker color encoding represents
- **Don't** dump the full GeoJSON in chat unless asked. It's already in the URL.

## Why each piece matters

- **Web-searching every landmark** is slow but it's the difference between a map with rich, trustworthy hover-cards and a map with hallucinated hours that mislead the user when they actually try to visit. The user explicitly chose this tradeoff.
- **Including city/region context in geocoding queries** prevents Nominatim from picking the wrong "Lake Merritt" — there are multiple places with most landmark names in the world.
- **Maki icons specifically** because that's what geojson.io's renderer recognizes; arbitrary symbol names just become default pins.
- **[lng, lat] order** is the GeoJSON spec. Almost everyone gets this wrong on first try because Google Maps shows lat/lng. Re-check after building.

## What not to do

- Don't save a `.geojson` file unless the user explicitly asks. The URL is the deliverable.
- Don't include landmarks you couldn't geocode as Features with `[0, 0]` coordinates — that drops a marker in the Atlantic. List them in the summary as "couldn't locate" instead.
- Don't fabricate operating hours, prices, or addresses. "Unknown" is fine.
- Don't add fields beyond the schema above. geojson.io ignores unknown fields but they bloat the URL.
