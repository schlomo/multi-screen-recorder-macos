# Multi Screen Recorder homepage

The homepage at <https://multiscreenrecorder.schapiro.org/>: a small
[Hugo](https://gohugo.io/) site deployed to Cloudflare Workers static assets by
Cloudflare Workers Builds. One page, in English: what the app is, the
requirements, the download link, screenshots of its two windows and the links
to the tester guide, the problem report form and the repository.

## Editing

- **The page:** `layouts/home.html`; its texts and links come from `[params]` in
  `hugo.toml` (the description is the root `README.md`'s opening paragraph).
  The download link goes to the latest release, never to a file: the release
  asset's name contains the version.
- **404 page:** `content/404.md`
- **robots.txt:** `static/robots.txt`; **headers:** `static/_headers`
  ([format](https://developers.cloudflare.com/workers/static-assets/headers/))
- **Page `<head>`** (title, description, link previews, icons):
  `layouts/_partials/head.html`
- **Styles:** `assets/css/style.css` (plain CSS with native nesting, system
  fonts; inlined into each page)
- **Colours:** `[params.colors]` in `hugo.toml`, the only place colours are
  defined
- **Header image:** the app icon artwork `../assets/icon/app-icon-fancy.jpeg`,
  mounted by `[module]` in `hugo.toml` (never copied here) and resized by
  Hugo to a 256 px WebP in `layouts/baseof.html`. Changing that file
  triggers no homepage build (it is outside the watch path); the next
  homepage change picks it up.
- **Screenshots:** the start and status windows, `assets/images/*.png` as
  taken with macOS's screenshot tool, placed in `layouts/home.html` and shown
  by `layouts/_partials/screenshot.html` as WebP at the window's size in
  points and never wider than the page. A screenshot taken on a Retina
  screen has 2 pixels per point; rename it to end in `-2x.png` (not macOS's
  `@2x`, which Cloudflare redirects). Any other has 1. To update one,
  replace the file, and rename it (in `home.html` too) if its pixels per
  point changed.
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
are `noindex`).

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
