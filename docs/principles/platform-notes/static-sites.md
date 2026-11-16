# Platform notes: static sites

How an agent checks a static site, here the homepage: Hugo in
`homepage/`, served by Cloudflare Workers static assets
(`homepage/README.md` describes the site itself).

- **Phone widths are measured, not looked at.** A page fits a phone
  when `document.documentElement.scrollWidth` equals the viewport's
  `innerWidth`. Headless Chrome makes no window narrower than 500 px
  (*observed live, 2026-11-16*, Chrome 157, `--headless=new`), and its
  screenshots of a page loaded that narrow came out cropped, so the
  page is loaded in an `iframe` of the phone's width and the two
  numbers are read from the DOM. The check needs `python3`, `curl` and
  Chrome on the `PATH` as `chrome`. On a Mac that is a two-line script
  named `chrome` in a folder on the `PATH`; a symbolic link does not
  work, as Chrome then cannot find its own files (*observed live,
  2026-11-16*):

  ```sh
  #!/bin/sh
  exec "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "$@"
  ```

  From `homepage/`, after `./build.sh`, for 320 px (repeat for 375
  and 430):

  ```sh
  (
    set -euo pipefail
    for tool in chrome python3 curl; do
      command -v "$tool" >/dev/null || { echo "phone check: $tool is not on the PATH" >&2; exit 1; }
    done
    cat > public/phone-check.html <<'EOF'
  <!doctype html><iframe id=f src="/" style="width:320px;height:900px;border:0"></iframe><pre id=out></pre>
  <script>f.onload=()=>{out.textContent=`innerWidth=${f.contentWindow.innerWidth} scrollWidth=${f.contentDocument.documentElement.scrollWidth}`}</script>
  EOF
    python3 -m http.server 8765 -d public >/dev/null 2>&1 & server=$!
    trap 'kill $server; rm -f public/phone-check.html' EXIT
    curl -sf --retry 10 --retry-connrefused -o /dev/null http://localhost:8765/phone-check.html
    chrome --headless=new --virtual-time-budget=5000 --dump-dom http://localhost:8765/phone-check.html | grep -o 'innerWidth=[0-9]* scrollWidth=[0-9]*'
  )
  ```

  Equal numbers mean nothing scrolls sideways (the command run as
  written, 2026-11-16: `innerWidth=320 scrollWidth=320`).
- **A PR's preview.** Every push to a PR that changes `homepage/` gets
  a Cloudflare preview; its URLs are the "Preview URL" and "Preview
  Alias URL" in the summary of the "Workers Builds" check run of the
  pushed commit (*observed live, 2026-11-16*):

  ```sh
  gh api repos/{owner}/{repo}/commits/<sha>/check-runs --jq '.check_runs[] | select(.name | test("Workers Builds")) | .output.summary'
  ```

- **Served URLs are checked without following redirects:**
  `curl -sI <url>`, never with `-L`. Cloudflare answers a path with
  `@` with a 307 to its percent-encoded form (*observed live,
  2026-11-16*), which a check that follows redirects reports as a
  200.
