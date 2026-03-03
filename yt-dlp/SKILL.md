---
name: yt-dlp
description: Download videos from YouTube, Instagram Reels, Tiktok, Twitter, and thousands of other sites using yt-dlp. Supports format selection, quality control, metadata embedding, and cookie authentication. Use when the user provides a video URL and wants to download it, extract audio (MP3), download subtitles, or select video quality. Triggers on phrases like "download video", "yt-dlp", "YouTube", "instagram reel", "instagram reels", "tiktok", "extract audio". Do not use for Instagram post/gallery URLs matching instagram.com/p/<code>/; route those to the instagram-gallery-download skill.
---

# yt-dlp Video Downloader

Download videos from thousands of websites using yt-dlp.

## Routing Rule

1. If URL matches `https://www.instagram.com/p/<code>/`, route to `instagram-gallery-download` skill.
2. If URL matches `https://www.instagram.com/reel/<code>/` or `https://www.instagram.com/reels/<code>/`, continue with this `yt-dlp` skill.
3. For non-Instagram supported sites, continue with this `yt-dlp` skill.

## Quick Start

### Basic Download (Best Quality)

```bash
yt-dlp -P "~/Downloads/yt-dlp" "VIDEO_URL"
```

### YouTube Download (Recommended - with cookies)

YouTube often blocks direct downloads with 403 errors. Always use browser cookies for YouTube:

```bash
yt-dlp -P "~/Downloads/yt-dlp" --cookies-from-browser chrome "YOUTUBE_URL"
```

Supported browsers: `chrome`, `firefox`, `safari`, `edge`, `brave`, `opera`

### Download with Custom Output Path

```bash
yt-dlp -P "/path/to/save" -o "%(title)s.%(ext)s" "VIDEO_URL"
```

## Common Tasks

### 1. Download Video (Default - Best Quality)

```bash
yt-dlp -P "~/Downloads/yt-dlp" "VIDEO_URL"
```

### 2. Extract Audio Only (MP3)

```bash
yt-dlp -P "~/Downloads/yt-dlp" -x --audio-format mp3 "VIDEO_URL"
```

### 3. Download with Subtitles

```bash
yt-dlp -P "~/Downloads/yt-dlp" --write-subs --sub-langs all "VIDEO_URL"
```

### 4. Download Specific Quality

**720p:**
```bash
yt-dlp -P "~/Downloads/yt-dlp" -f "bestvideo[height<=720]+bestaudio/best[height<=720]" "VIDEO_URL"
```

**1080p:**
```bash
yt-dlp -P "~/Downloads/yt-dlp" -f "bestvideo[height<=1080]+bestaudio/best[height<=1080]" "VIDEO_URL"
```

**Best available:**
```bash
yt-dlp -P "~/Downloads/yt-dlp" -f "bestvideo+bestaudio/best" "VIDEO_URL"
```

### 5. List Available Formats (Before Download)

```bash
yt-dlp -F "VIDEO_URL"
```

Then download specific format by ID:
```bash
yt-dlp -P "~/Downloads/yt-dlp" -f FORMAT_ID "VIDEO_URL"
```

### 6. Download Playlist

```bash
# Download entire playlist
yt-dlp -P "~/Downloads/yt-dlp" -o "%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s" "PLAYLIST_URL"

# Download specific range (e.g., items 1-5)
yt-dlp -P "~/Downloads/yt-dlp" -I 1:5 "PLAYLIST_URL"
```

### 7. Download with Thumbnail

```bash
yt-dlp -P "~/Downloads/yt-dlp" --write-thumbnail "VIDEO_URL"
```

## Workflow

When user provides a video URL:

1. **Identify the platform and route first**:
   - Instagram post/gallery URL (`/p/`) → **Use `instagram-gallery-download` skill**
   - Instagram reel/reels URL (`/reel/`, `/reels/`) → Continue with `yt-dlp`
   - YouTube/YouTube Music → **Always use `--cookies-from-browser chrome`**
   - Other sites → Try without cookies first

2. **Ask what they want** (if not specified):
   - Just download the video?
   - Extract audio only?
   - Need subtitles?
   - Specific quality?

3. **Construct the command** based on requirements

4. **Execute the download** using Shell tool with `required_permissions: ["all", "network"]`

5. **Handle errors**:
   - 403 Forbidden → Retry with `--cookies-from-browser`
   - Connection issues → yt-dlp auto-resumes, just retry
   - Format unavailable → Use `-F` to list formats, then select

6. **Report the result** - file location and any errors

## Execution Context

Always run this skill in escalation permission mode.

## Example Interaction

User: "Download https://www.instagram.com/p/ABC123xyz/"

Response:
Route to `instagram-gallery-download` skill (do not use `yt-dlp` for `/p/` URLs).

User: "Download https://www.instagram.com/reel/DVAl1aaDVTn/?igsh=NjZiM2M3MzIxNA=="

Response:
```bash
# Instagram reel - use yt-dlp
yt-dlp -P "~/Downloads/yt-dlp" --cookies-from-browser chrome "https://www.instagram.com/reel/DVAl1aaDVTn/?igsh=NjZiM2M3MzIxNA=="
```

User: "Help me download this video https://www.youtube.com/watch?v=xxx"

Response:
```bash
# YouTube - use cookies to avoid 403 errors
yt-dlp -P "~/Downloads/yt-dlp" --cookies-from-browser chrome "https://www.youtube.com/watch?v=xxx"
```

User: "Download the audio of this video https://www.bilibili.com/video/xxx"

Response:
```bash
# Bilibili - extracting audio as MP3
yt-dlp -P "~/Downloads/yt-dlp" -x --audio-format mp3 "https://www.bilibili.com/video/xxx"
```

User: "Download this Twitter video https://twitter.com/xxx/status/123"

Response:
```bash
# Twitter/X - direct download usually works
yt-dlp -P "~/Downloads/yt-dlp" "https://twitter.com/xxx/status/123"
```

## Supported Sites

yt-dlp supports thousands of sites including:
- Instagram
- YouTube, YouTube Music
- Twitter/X
- TikTok
- Vimeo
- Twitch
- And many more...

Full list: https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md

## Troubleshooting

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| HTTP 403 Forbidden | YouTube blocks unauthenticated requests | Use `--cookies-from-browser chrome` |
| Video unavailable | Geo-restricted or private | Use cookies or VPN |
| Download interrupted | Network issues | Retry - yt-dlp auto-resumes |
| Format not available | Requested format doesn't exist | Use `-F` to list formats |

### Error: "yt-dlp: command not found"
```bash
pip install yt-dlp
```

### Error: "ffmpeg not found" (for audio extraction)
```bash
brew install ffmpeg  # macOS
```

### Error: HTTP 403 Forbidden (YouTube)

This is the most common YouTube error. **Always use cookies for YouTube:**

```bash
# Recommended approach for YouTube
yt-dlp -P "~/Downloads/yt-dlp" --cookies-from-browser chrome "YOUTUBE_URL"
```

Supported browsers: `chrome`, `firefox`, `safari`, `edge`, `brave`, `opera`

### Error: Video unavailable or geo-restricted
```bash
# Try with cookies from browser
yt-dlp --cookies-from-browser chrome "VIDEO_URL"

# Or use a specific format
yt-dlp -F "VIDEO_URL"  # List formats first
yt-dlp -f FORMAT_ID "VIDEO_URL"
```

### Error: Download keeps failing
```bash
# Update yt-dlp to latest version
pip install -U yt-dlp

# Force IPv4 (sometimes helps with connection issues)
yt-dlp -4 "VIDEO_URL"
```

### Full list if CLI options

```bash
yt-dlp --help
```

### Best Practices

1. **YouTube downloads**: Always use `--cookies-from-browser chrome`
2. **Large files**: yt-dlp auto-resumes, just retry if interrupted
3. **Keep yt-dlp updated**: `pip install -U yt-dlp`
4. **Check formats first**: Use `-F` before downloading if unsure
