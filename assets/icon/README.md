# App icon sources

Read-only source assets for the app icon and the project's images.

| File | What it is |
|---|---|
| `app-icon-flat.jpeg` | The app icon source: 2048 x 2048 drawing from Gemini (Nano Banana) of a graphite tile with three displays and a red dot, no gloss, on an off-white background |
| `app-icon-fancy.jpeg` | The glossy variant, 2048 x 2048, from the same source; the image for the root `README.md` and the homepage |
| `app-icon.png` | 1024 x 1024 PNG with alpha, made once from `app-icon-flat.jpeg`; `scripts/build-app` builds `AppIcon.icns` from it |
| `msr-icon-master.svg`, `msr-icon-sizes.svg` | An earlier vector redraw (300 x 300 units; layers tile, displays, dot), kept for reference only |

## Colours

Also for the homepage.

| Name | Value |
|---|---|
| Graphite | `#1E2330` |
| Cool white | `#E9EEF7` |
| Red | `#FF3B30` |

## How `app-icon.png` was made

From `app-icon-flat.jpeg` with a throwaway Swift script (CoreGraphics and
ImageIO), not kept in the repository:

1. Measure the tile: the bounding box of the dark pixels (red, green and
   blue summing below 330) is x 216 to 1831, y 219 to 1832 in the 2048 x 2048
   image.
2. Crop to that box, 3 px smaller on every side so the anti-aliased edge,
   which still blends the off-white background, is left out.
3. Scale the crop to 824 x 824 px (high interpolation quality) and centre it
   on a transparent 1024 x 1024 canvas, which leaves the 100 px margin of
   the macOS icon grid.
4. Clip to a rounded rectangle of corner radius 185 px on the 824 px tile,
   so everything outside it, including the source's corners and soft shadow,
   is transparent.
5. Write a PNG.

Redo it the same way if the flat image changes.
