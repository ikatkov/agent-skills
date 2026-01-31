---
name: media_archiver
description: Converts a web page into an offline-ready video gallery, downloading assets and linking local media.
---

# Media Archive UI Generator

This skill helps you convert a standard web page into a self-contained, offline-capable video gallery. It is useful for archiving projects where you want to keep the UI visuals but serve local video content.

## Workflow
### 1. Open target page
- **Goal**: Ensure local browser can open the target page
- **Action**:
  - Ensure that prompt contains target URL, if not ask user for it
  - Open the target page in the browser
  - Create ./web directory.
  - Create ./web/images directory.
  - You modify files only within ./web directory
 
### 2. Asset Localization
- **Goal**: Make an offline copy of the target page with local assets
- **Action**:
  - Understand how ./example/index.html and ./example/style.css are structured
  - Scan the target page in the browser to understand the visual layout. You must keep all the text content verbatim from the target page. No omissions or replacements. 
  - All images must be be present on the target page. No omissions or replacements.
  - **Inventory**: List all local video files first. This will be your "source of truth" to match images and titles against.
  - Create a local copy of the target page ./web/index.html, use ./example/style.css instead of original CSS styles
  - Download all images (thumbnails) ./index.html needs to ./web/images. 
  - Make ./web/index.html references to local resources in ./web/images
  - **Parsing Strategy**:
    - For small projects (< 20 items), it is often faster to manually identify and download images than to write a complex parser.
    - If parsing `srcset`, allow for fallbacks. If a `.webp` URL 404s, try the `.jpg` version.
  - **Naming**: Rename downloaded images to match their corresponding video filenames (e.g., if video is `yoga-flow.mp4`, save image as `yoga-flow.jpg`). This makes linking easier.
  - Do not install any software or dependencies. Do not create and run python scripts. 

### 3. Remove External Dependencies
- **Goal**: Maximize speed and privacy, remove reliance on external CDNs.
- **Action**:
  - Remove `<link>` tags for external fonts (e.g., Google Fonts, Adobe Fonts).
  - Update CSS `--font-family` variables to use generic system fonts (e.g., `sans-serif`, `-apple-system`, `Inter`, `BlinkMacSystemFont`).

### 4. Connect Local Media
- **Goal**: Make the gallery functional.
- **Action**:
  - Locate local video files (e.g., `.mp4`, `.mkv`) in the project directory.
  - Match video files to the UI cards/episodes in the HTML based on order or naming convention.
  - Update anchor tags (`<a href="...">`) to link directly to the local video files.

### 5. Premium UI Polish
- **Goal**: Create a high-quality "Netflix-style" browsing experience.
- **Action**:
  - **Dark Mode**: Ensure the background is dark (e.g., `#000` or `#1c1c1e`) and text is light/white.
  - **Play Overlays**: Add CSS to display a "Play" button (▶) icon over thumbnails on hover.
  - **Micro-interactions**: Add hover scaling (`transform: scale(1.02)`) and brightness effects to thumbnails to indicate interactivity.

## Common CSS Patterns to Use

### Play Button Overlay
```css
.card-image-container {
    position: relative;
    overflow: hidden;
}

/* Play Button Icon */
.card-image-container::after {
    content: "▶";
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 44px;
    height: 44px;
    background: rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(4px);
    border-radius: 50%;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
    opacity: 0;
    transition: opacity 0.2s ease, transform 0.2s ease;
    padding-left: 3px; /* Optical centering */
}

/* Hover State */
.card:hover .card-image-container::after {
    opacity: 1;
    transform: translate(-50%, -50%) scale(1.1);
}

/* Image Dimming */
.card img {
    transition: filter 0.2s ease;
}


.card:hover img {
    filter: brightness(0.7);
}
```

## Examples

For a complete reference implementation, check the `examples/` directory:

- **[index.html](./examples/index.html)**: A full example of the HTML structure with local image paths and video links.
- **[style.css](./examples/style.css)**: The complete CSS including dark mode variables, responsive grid, and the interactive play button overlay.
