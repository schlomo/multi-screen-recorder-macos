# App icon sources

Source assets for the app icon and the project's images.

| File | What it is |
|---|---|
| `app-icon.svg` | The app icon source: a vector drawing, 300 units wide, layers tile, displays (back, middle, front with stand) and dot; the viewBox is widened to 372.82 units so the tile is 824 px of a 1024 px canvas, the margin of the macOS icon grid |
| `app-icon.png` | 1024 x 1024 PNG with alpha, derived from `app-icon.svg`; committed, because CI does not render it. `scripts/build-app` builds `AppIcon.icns` from it |
| `msr-icon-sizes.svg` | Reference sheet of the drawing at several sizes |
| `app-icon-fancy.jpeg` | Glossy 2048 x 2048 artwork from Gemini (Nano Banana); the image for the root `README.md` and the homepage |
| `app-icon-flat.jpeg` | The flat 2048 x 2048 Gemini artwork, same composition as the SVG; kept for reference |

## Colours

Also for the homepage.

| Name | Value |
|---|---|
| Graphite | `#1E2330` |
| Cool white | `#E9EEF7` |
| Red | `#FF3B30` |

## Regenerating `app-icon.png`

After changing `app-icon.svg`, run `scripts/render-app-icon` (needs
`rsvg-convert` from librsvg, `brew install librsvg`) and commit the PNG.
