# App icon and artwork

| File | What it is |
|---|---|
| `app-icon.svg` | The app icon source: a vector drawing, 300 units wide, layers tile, screens (back, middle, front with stand) and dot; the viewBox is widened to 372.82 units so the tile is 824 px of a 1024 px canvas, the margin of the macOS icon grid |
| `app-icon.png` | 1024 x 1024 PNG with alpha, derived from `app-icon.svg`; committed, because CI does not render it. `scripts/build-app` builds `AppIcon.icns` from it |
| `app-icon-fancy.jpeg` | Artwork: glossy 2048 x 2048 image from Gemini (Nano Banana), for the root `README.md` and the homepage's header, which mounts it (`homepage/hugo.toml`, `[module]`) and has Hugo resize it to a 256 px WebP at build time |
| `app-icon-fancy-256.jpeg` | 256 px rendition of the fancy artwork, derived, which the root `README.md` shows |
| `app-icon-fancy-tile.png` | 1024 x 1024 PNG with alpha: the fancy artwork's tile cut out of its light background, derived, which the homepage's header shows (it mounts it, `homepage/hugo.toml`, `[module]`) |
| `app-icon-flat.jpeg` | Artwork: the flat 2048 x 2048 Gemini image, the same composition as the SVG; kept for reference |
| `msr-icon-sizes.svg` | A snapshot of the drawing at five sizes; it is not kept in step with `app-icon.svg` |

## Colours

The project palette (the owner's choice of 2026-11-12), meant for the homepage as well.

| Name | Value |
|---|---|
| Graphite | `#1E2330` |
| Cool white | `#E9EEF7` |
| Red | `#FF3B30` |

The SVG uses its own colours, none of them in the palette: back screen `#415070`, middle screen `#6E7CA0`, front screen `#E6EBF7`, stand `#D5DAE6`. The palette's cool white `#E9EEF7` is not used in the SVG.

## Regenerating the derived images

Run `scripts/render-app-icon` (needs `rsvg-convert` from librsvg,
`brew install librsvg`, and `magick` from ImageMagick, `brew install
imagemagick`; `sips` is part of macOS) after editing
`app-icon.svg` or `app-icon-fancy.jpeg`, and commit the derived images:
the two here and the homepage's favicons in `homepage/static/`
(`favicon.svg`, a copy of `app-icon.svg`, and the PNGs and the `.ico`
rendered from it).

Known limitation: CI cannot re-render the SVG (no `rsvg-convert` on the
runner), so nothing checks that `app-icon.png` still matches
`app-icon.svg`; `scripts/build-app` uses the committed PNG as it is.
