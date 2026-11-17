# Multi Screen Recorder homepage

The homepage at <https://multiscreenrecorder.schapiro.org/>: a small
[Hugo](https://gohugo.io/) site deployed to Cloudflare Workers static assets by
Cloudflare Workers Builds. One page, in English: what the app is, the
download link, a collage of three screenshots showing how it is used, the
features, the links to the tester guide, the problem report form and the
repository, and the requirements.

## Editing

- **The page:** `layouts/home.html`; its texts and links come from `[params]` in
  `hugo.toml` (the description is the root `README.md`'s opening paragraph).
  On a screen 64rem wide or more (wider than a phone held sideways) the
  header, the features and the last three sections use the page's width of
  up to 76rem; running text stays at most 44rem wide.
- **Features:** the root `README.md`'s "What it does" list, read at build
  time (mounted by `[module]` in `hugo.toml`); edit it there. Like the icon
  artwork, a change there triggers no homepage build; the next homepage
  change picks it up.
  The download link goes to the latest release, never to a file: the release
  asset's name contains the version.
- **404 page:** `content/404.md`
- **robots.txt:** `static/robots.txt`; **headers:** `static/_headers`
  ([format](https://developers.cloudflare.com/workers/static-assets/headers/))
- **Page `<head>`** (title, description, link previews, icons):
  `layouts/_partials/head.html`
- **Styles:** `assets/css/style.css` (plain CSS with native nesting, system
  fonts; inlined into each page)
- **Colours:** `[params.colors]` in `hugo.toml`, and `[params.colors-dark]`
  for a browser in dark mode, the only place colours are defined; both need
  the same names (the build stops otherwise). `layouts/_partials/palette.html`
  turns them into CSS custom properties.
- **Header image:** the app icon artwork's tile,
  `../assets/icon/app-icon-fancy-tile.png`, transparent outside it (cut
  out of `app-icon-fancy.jpeg` by `scripts/render-app-icon`, so it shows no
  square on any background), mounted by `[module]` in `hugo.toml` (never
  copied here) and resized by Hugo to a 336 px WebP in
  `layouts/baseof.html`. The link preview image below is drawn from
  `app-icon-fancy.jpeg` itself. Changing either file triggers no
  homepage build (they are outside the watch path); the next homepage
  change picks them up.
- **Screenshots:** the collage under the download button, drawn by
  `layouts/_partials/collage.html` as one SVG picture from three PNGs in
  `assets/images/`: `app-window.png` (the start window), `status-window.png`
  (the status window while recording) and `recording-folder.png` (the
  recording folder in Finder, list view). The layout comes from their
  sizes: the app window on the left, the other two stacked on the right,
  together as tall as it. A click opens the picture full size in a new tab
  (`images/collage.svg`). Below it, three numbered steps say what the
  pictures show; they are in `layouts/home.html`.
- **Updating the screenshots:**
  1. Make the windows show what the page should show: the start window
     with several screens and audio sources, the status window during a
     recording, the recording folder's Finder window in list view.
  2. Take each with macOS's screenshot tool: Shift-Command-4, then Space,
     then Option-click the window (Option leaves out the shadow; the
     collage draws its own).
  3. Save them over the three files above, under the same names. Their
     pixel density and size do not matter.
  4. Preview with `hugo server` (below) and check that the arrows still
     start beside Start and Stop and end at the next window. They point at
     fractions of each screenshot (`$startY`, `$stopY` and the others in
     `collage.html`); only a window whose layout moved those buttons needs
     a new fraction.
- **Link preview image** (Open Graph, `og:image`): 1200 x 630, drawn by Hugo at
  build time in `layouts/_partials/link-preview-image.html` from the icon
  artwork, the site's name and the tagline, on the `artwork` colour; the
  `<meta>` tags are in `layouts/_partials/head.html`.
- **Favicons:** `static/favicon*` and `static/apple-touch-icon.png`, rendered
  from `assets/icon/app-icon.svg` by `scripts/render-app-icon`; never edit them
  by hand.

Templates: `layouts/baseof.html` wraps every page (head, header image and name,
footer); `layouts/home.html` renders the home page; `layouts/page.html` renders
every other page from `content/`.

The footer links to the owner's legal notice and privacy policy at
<https://schapiro.org/impressum/>.

## Local development

Install Hugo (`brew install hugo`), then run `hugo server` in this folder for a
live-reloading preview on <http://localhost:1313>. `./build.sh` builds into
`public/` (`./build.sh -p` for an indexable production build; all other builds
are `noindex`). How agents check the site (phone widths, the preview, served
URLs) is in
[docs/principles/platform-notes/static-sites.md](../docs/principles/platform-notes/static-sites.md).

## Deployment

Cloudflare Workers Builds runs `./build.sh` and deploys `public/` as Workers
static assets. [`wrangler.jsonc`](wrangler.jsonc) is the source of truth for
the deploy: Worker name, custom domain and 404 handling. Only `main` gets an
indexable production build. A push that changes only `homepage/` makes no app
release (`.github/workflows/ci.yml`).

### Cloudflare dashboard settings

The Workers project `multiscreenrecorder-homepage` is connected to this
repository by the owner. These settings can't live in this repo (as the owner
set them, 2026-11-16):

- **Git access:** the Cloudflare Workers and Pages GitHub app must have
  access to this repository (GitHub, Settings, Applications); without it
  Cloudflare shows "This project is disconnected from your Git account"
  and builds nothing
- **Branch control:** production branch `main`, builds for non-production
  branches on; previews stay on the version command below (the old preview
  model, as for schapiro.org), not "Worker Previews"
- **Build command:** `./build.sh`
- **Deploy command:** `npx wrangler deploy`
- **Version command:** `npx wrangler versions upload`
  (uploads a preview version; it never touches production)
- **Root directory:** `/homepage`
- **Build watch paths:** include `homepage/**`, exclude none, so changes
  outside the homepage build nothing
- **API token:** "multiscreenrecorder-homepage build token"
- **Variable:** `HUGO_VERSION` = `0.170.0`. Cloudflare's build image installs
  this Hugo version; bump it here when you upgrade Hugo locally.
