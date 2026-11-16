---
paths:
  - "homepage/**"
---

# Homepage: how agents check it

The homepage itself is described in `homepage/README.md`; these are the
checks an agent runs on it.

- **Phone widths without a phone.** Load the built page in an `iframe`
  320 to 430 px wide and compare `document.documentElement.scrollWidth`
  with the frame's `innerWidth`: equal means nothing scrolls sideways.
  Headless Chrome makes no window narrower than about 500 px, and its
  screenshots of such a page can come out cropped, so the measurement is
  the check, not the picture.
- **The PR's preview.** Every PR that changes `homepage/` gets a
  Cloudflare preview; its URLs are in the "Workers Builds" check run of
  the PR's head commit
  (`gh api repos/{owner}/{repo}/commits/<sha>/check-runs`).
- **Served URLs without following redirects.** Check them with
  `curl -sI`, never with `-L`: Cloudflare answers some paths (one with
  `@`, for example) with a redirect, which a check that follows
  redirects never shows.
