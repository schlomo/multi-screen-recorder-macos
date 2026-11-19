# Delivery: pipeline, versions, signing

## What this covers

How a change becomes something a person can install: the scripts, the
pipeline that wires them, version numbers, signing, the homepage's
delivery, and the one-time developer setup. What the app does is in [recorder.md](recorder.md).

## The decision

**Scripts hold the behaviour; the pipeline only wires them** (thin CI).
Each script but the CI-only ones (`scripts/ci-import-signing-certificate`,
`scripts/ci-install-end-to-end-tools`) runs the same on a developer's
Mac and in CI. Five are Python (D32): `scripts/version`, `scripts/unpack-app`,
`scripts/sign-app`, `scripts/smoke-test` and
`scripts/publish-snapshot-release`; the rest are bash glue around a few
commands. The Python scripts use the standard library only, so nothing
is installed, and need Python 3.15 or later, the `python3` on the
`PATH` of the `macos-26` arm64 runner image (its software list in
[actions/runner-images](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md),
image 20261102, lists Python 3.15.2); each stops on an older one with
an error naming that minimum. The minimum follows the runner image
when it moves.

The scripts that take arguments (`scripts/test`, `scripts/version`,
`scripts/unpack-app`, `scripts/install-app`, `scripts/end-to-end-test`)
print how to use them with `--help` or `-h`.

| Script | Does |
|---|---|
| `scripts/test` | Compiles the Python scripts (`python3 -I -m py_compile`), then runs the unit tests and the tests that run `msr` and the scripts as commands; passes its arguments to `swift test`; needs `cc` too, which builds the stand-in program of the `scripts/install-app` tests |
| `scripts/version` | Prints the version of the current checkout, or with `--build-date` its date as `YYYY-MM-DD`; stops on a shallow clone |
| `scripts/build-app` | Compiles `msr`, assembles the app bundle in `build/` (with `Contents/Resources/AppIcon.icns`, built at build time from the committed `assets/icon/app-icon.png` by `sips` and `iconutil`, both required up front; it stops if the PNG is missing or the iconset is not the ten expected files; the `.icns` is never committed), signs it ad hoc with the real signing's options, and archives it as `build/msr-app.tar` |
| `scripts/render-app-icon` | Renders the derived images in `assets/icon/`: `app-icon.png` (1024 x 1024, transparent outside the tile) from `app-icon.svg` with `rsvg-convert` (librsvg), the 256 px `app-icon-fancy-256.jpeg` for the README with `sips`, and `app-icon-fancy-tile.png` (the artwork's tile, transparent outside it) for the homepage's header with `magick` (ImageMagick); all three tools required up front. Run by hand after changing a source and commit the images; CI never renders (no `rsvg-convert` on the runner) and uses the committed PNG |
| `scripts/smoke-test` | Checks the bundle names its icon file (`CFBundleIconFile`) and holds an icon that is 1024 px wide (`sips`), and that its build date (`MSRBuildDate`) is its version's date, then runs the bundled `msr` with a scratch `HOME`: version (also through a symbolic link), settings (which writes no file), a settings flag that saves it, a settings file with an unknown key (never refused) and exit 64; nothing that needs a permission, a screen or a microphone |
| `scripts/unpack-app` | Unpacks the app archive into an empty `build/` with the `data` filter of Python's `tarfile`, rooted at the bundle folder, which refuses absolute paths, links pointing out of the bundle and special files; before writing anything the script itself refuses an archive that is not a plain tar, a member named twice, a member outside the bundle or with a `..` component (the build writes none), a bundle that is not a folder and a member below a symbolic link of the archive; a member that cannot be extracted stops it, and it removes what it wrote when it stops |
| `scripts/sign-app` | Checks the bundle's version, commit and identifier, re-signs it, checks the signature, identifier, hardened runtime and entitlements, and zips it into `build/` |
| `scripts/install-app` | Installs the app into `/Applications` from a local build, the latest release (`--release`), a PR's snapshot release (`--snapshot <n>`) or a zip; see "Installing the app on the developer's Mac" below |
| `scripts/end-to-end-test` | Builds the end-to-end tests' driver (`msr-end-to-end`, never in the bundle) and runs it against `build/Multi Screen Recorder.app`: records with `msr record` while it adds a virtual screen and plays a tone into BlackHole, examines the recording folders, and restores the Mac; `restore` puts the Mac back after a killed run. Needs `ffmpeg`, `ffprobe` and BlackHole 2ch, and both permissions for the program running it ([end-to-end-tests.md](end-to-end-tests.md)) |
| `scripts/ci-import-signing-certificate` | CI only: puts the certificate from the secret into a temporary keychain |
| `scripts/ci-install-end-to-end-tools` | CI only: downloads ffmpeg and ffprobe (static builds) and BlackHole 2ch at fixed versions, checks each against its SHA-256, puts ffmpeg on the `PATH` of the later steps, installs BlackHole and waits until Core Audio lists it |
| `scripts/publish-snapshot-release` | Creates or replaces a PR's snapshot release; removes it once the PR is closed (a marked head commit needs an unmarked empty commit first, see [Work branches](../principles/ai-working-process.md#work-branches)) |
| `scripts/remove-snapshot-release` | Removes a closed PR's snapshot release (see [Work branches](../principles/ai-working-process.md#work-branches) for a marked head commit) |
| `scripts/publish-release` | Publishes the release for a merge to `main` |

**Pipeline** (`.github/workflows/ci.yml`, GitHub Actions on a hosted
macOS runner for Apple silicon; free for a public repository), the
build and the signing in jobs of their own so the key never meets
compiled code (D29), and the end-to-end tests in a third (D63):

| Job | Holds | Does |
|---|---|---|
| `test-and-build` | the checkout, read access; no secret, no token | `scripts/test`, `scripts/build-app`, `scripts/smoke-test`; uploads `build/msr-app.tar` as a workflow artifact (kept 1 day) |
| `end-to-end-test` | the checkout, read access; no secret, no token | downloads the artifact, `scripts/unpack-app`, `scripts/ci-install-end-to-end-tools`, `scripts/end-to-end-test` with its scratch folder in `$RUNNER_TEMP/end-to-end`; the runner image grants both permissions. When it fails, it uploads that folder (the kept scenario folders, the restore file if left, the driver's log `run.log`) as the workflow artifact `end-to-end-scratch`, kept 14 days |
| `snapshot-release`, `release` (the signing jobs) | the checkout, write access, the signing secret in the import step only, the token in the publish step only | downloads the artifact, `scripts/unpack-app`, `scripts/ci-import-signing-certificate`, `scripts/sign-app`, then `scripts/publish-snapshot-release` or `scripts/publish-release` |

| When | What runs |
|---|---|
| Every push to a PR without the skip-ci marker | `test-and-build`, then `end-to-end-test`, then `snapshot-release` |
| A PR is closed (not skipped only if its head commit carries no skip-ci marker, see [Work branches](../principles/ai-working-process.md#work-branches)) | `remove-snapshot-release` |
| A push to `main` that changes more than Markdown files and the homepage (`homepage/`) | `test-and-build`, then `end-to-end-test`, then `release` |
| A PR from a fork or from Dependabot | `test-and-build`, then `end-to-end-test`: tested, built, smoke-tested and end-to-end tested, never signed or published |

Three things cross from `test-and-build` into a signing job, and the
signing job refuses each as a carrier of code:

- **A cache:** the signing jobs restore none.
- **The artifact:** data only. `scripts/unpack-app` unpacks it into an
  empty `build/` with the checks above, relying on no tar's defaults
  (Python's `tarfile`, `python3` from the `PATH`), and nothing from it
  is ever executed; `scripts/sign-app` reads the bundle with `codesign`
  and Python's `plistlib` only.
- **Scripts:** a signing job runs the scripts of its own checkout of
  the same commit, never ones from the artifact.

The design rests on one named assumption: every job on a GitHub-hosted
runner gets a fresh virtual machine that is destroyed after the job
("When the job begins, GitHub automatically provisions a new VM for
that job. When the job has finished, the VM is automatically
decommissioned.",
[Using GitHub-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners);
single-CPU runners are containers on a shared VM, and none is used
here). A self-hosted runner, or a single-CPU one, would break it.

The artifact is a tar archive uploaded unzipped, because the artifact
zip keeps no file permissions, so `msr` would lose its executable bit
([upload-artifact, "Permission Loss"](https://github.com/actions/upload-artifact#permission-loss)).

**Snapshot release:** one GitHub pre-release per PR, tag `pr-<number>`,
replaced on every push without the skip-ci marker, titled `Snapshot PR #<n>: <version>`. A
pre-release rather than a draft, which only collaborators can see and
which has no stable download link. It is published only while the PR
is open and its head is the commit built; a run for a superseded push
publishes nothing and succeeds. A run for a closed PR (it does not run if the head commit carries the
skip-ci marker, see [Work branches](../principles/ai-working-process.md#work-branches)) publishes nothing,
removes the PR's snapshot release if one is left, and succeeds: GitHub
keeps one job waiting per concurrency group and cancels it when another
is queued, so a snapshot run queued after the close can replace the
waiting `remove-snapshot-release`
([GitHub: control the concurrency of workflows and jobs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)).

**Release:** releases are signed and published one at a time, each
waiting in turn (`queue: max` on the `release` job's concurrency group,
up to 100 waiting), so every push to `main` that changes more than
Markdown files and the homepage gets its release. They wait in the order their builds
finish, not the order of the pushes (see "Accepted risks").

`test-and-build` and `end-to-end-test` stop after 20 minutes (a run of
`test-and-build` takes about 2), so a hanging test fails the job
instead of holding a runner for GitHub's six hours. The signing jobs
wait for `end-to-end-test` too, so nothing that failed it is signed or
published (D63).

**Versions** (D42) carry the committer date of HEAD in UTC, DATE as
YYYYMMDD, and the number of commits on `main`, N:

| Build | Version |
|---|---|
| Release from `main` | `0.<DATE>.<N>`, tag `v0.<DATE>.<N>` |
| Snapshot of PR n | `0.<DATE>.<N+1>-pr<n>+<commit>` |
| Local build | `0.<DATE>.<N+1>-dev+<commit>` |

A local build with uncommitted changes to tracked files gets `.dirty`
after the commit (`+<commit>.dirty`); untracked files do not count.
Only a local build can be dirty: a release or a snapshot of such a
checkout stops in `scripts/version`, and `scripts/sign-app` accepts
`.dirty` only on a local build.
N grows with every commit on `main`, including Markdown-only ones that
publish nothing, so release numbers can skip but never repeat. The
version is computed once, by `scripts/version` in `scripts/build-app`,
and written into the bundle's `Info.plist` (`MSRVersion`, `MSRCommit`,
and `MSRBuildDate`, the version's own date as `scripts/version
--build-date` prints it, `2026-11-16`, for the banner of `msr check`
and `msr record`);
every later script reads it from there as data, so a push to `main`
between the build job and the signing job cannot change it. The
bundle's short version is the numeric part; `msr version` and the About
window show the full string. 1.0 comes when the owner declares v1.

**Signing** (D5, D23, D28, D29). `scripts/sign-app` re-signs with the identity
named in `SIGNING_IDENTITY` (default `Multi Screen Recorder Signing`)
and never sees a secret: `codesign` reads the key from the keychain and
matches the name as a substring of the certificate's name, so the
certificate in use, `Multi Screen Recorder Signing (Schlomo)`, is found
by the default. `SIGNING_IDENTITY=-` signs ad hoc, for a local check
only. On a developer's Mac the key is in the login keychain; in CI,
`scripts/ci-import-signing-certificate` imports the repository secret
`SIGNING_CERTIFICATE_P12` (base64 of a `.p12` exported without a
password) into a temporary keychain, the key non-extractable, in a
signing job that never compiles (D29). It is the one place that reads
the secret, because macOS has no tool that reads a certificate from the
environment itself (D28). A missing secret or identity stops with an
error. Before the key is used, `scripts/sign-app` stops on any miss
among: the bundle is a folder; its `Info.plist` names the commit that
is checked out (`MSRCommit`), the identifier
`org.schapiro.multiscreenrecorder`, and a version (`MSRVersion`) of
the form for this build: with `PR_NUMBER` the snapshot form for exactly
that PR and commit, with `RELEASE_BUILD=true` the release form
`0.<DATE>.<N>` with N the number of commits up to `HEAD` (the release job
checks out the full history for it; the snapshot job needs only the
commit), otherwise the local form. After signing it stops on any
miss among: `codesign --verify --deep --strict`; the signed identifier;
the hardened runtime flag; the entitlements equal to
`Resources/msr.entitlements` (audio input). The hardened
runtime is on, with the audio-input entitlement, so behaviour does not
change when Developer ID signing arrives. `scripts/build-app` already
signs ad hoc with the same options, so the smoke-tested bundle and the
published one differ in their signature only.

**Toolchain** (D17, D28): the pipeline uses the latest Xcode and Swift
that GitHub's generally available macOS runner image offers (today
Xcode 26.6 with Swift 6.3, so the package's tools version is 6.3), not
a preview image; revisited when a newer runner image is generally
available. A developer's Mac may run a newer Xcode; the package must
still build with the runner's. Dependabot proposes updates of the
GitHub Actions and Swift packages in use.

## Homepage

The homepage is a Hugo site in `homepage/` on `main` (D53), built and
served by Cloudflare Workers Builds at
`multiscreenrecorder.schapiro.org`, apart from this pipeline: the
push trigger ignores `homepage/**`, so a push to `main` that changes
only the homepage makes no release; the pull request trigger has no
such filter, so a PR's snapshot release is made as for any PR. Cloudflare
builds every push that changes `homepage/` (production from `main`,
indexable; a preview otherwise, `noindex`), by its build watch path
`homepage/**`. Cloudflare checks out the whole repository and builds
in the root directory `/homepage`; the header image is mounted from
`assets/icon/`, outside that directory (the first Cloudflare build,
of `4862371` on 2026-11-16, succeeded with it). `homepage/wrangler.jsonc`
holds the deploy; the dashboard settings that cannot live in the
repository, and connecting the Worker, are the owner's
([homepage/README.md](../../homepage/README.md)). Its cost: Cloudflare
Workers' free tier for static assets [ASSUMED: the owner's Cloudflare
account and plan were not checked].

## Developer setup, once

1. Xcode, with its licence accepted and selected:
   `sudo xcodebuild -license accept` and
   `sudo xcode-select -s /Applications/Xcode.app`. The Command Line
   Tools alone build the app but cannot run the tests.
2. Python 3.15 or later as `python3` on the `PATH`, for the scripts
   (the one macOS ships is older), such as from Homebrew:
   `brew install python@3.15`.
3. The signing certificate, in Keychain Access › Certificate Assistant ›
   Create a Certificate…: a name containing `Multi Screen Recorder
   Signing`, such as `Multi Screen Recorder Signing (<your name>)`;
   identity type Self-Signed Root, certificate type Code Signing, "Let
   me override defaults" ticked, validity 3650 days (the default is one
   year, and a new certificate means granting both permissions again),
   the rest unchanged, in the login keychain.
4. For the end-to-end tests: `brew install ffmpeg` and
   `brew install --cask blackhole-2ch` (an administrator's password, once).
5. For the pipeline, by the repository owner only: export the
   certificate from My Certificates as `.p12` with an empty password,
   then

   ```
   base64 -i msr-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 --repo schlomo/multi-screen-recorder-macos
   rm msr-signing.p12
   ```

## Installing the app on the developer's Mac

`scripts/install-app` replaces `/Applications/Multi Screen Recorder.app`
(`INSTALL_FOLDER` names another folder, which the tests use):

- `scripts/install-app` builds (`scripts/build-app`), signs
  (`scripts/sign-app`, so with `SIGNING_IDENTITY` or the default
  certificate) and installs the zip `scripts/sign-app` prints.
- `scripts/install-app --release` downloads the latest release's zip
  with `gh release download` (gh reads its own credentials) and
  installs it.
- `scripts/install-app --snapshot <n>` does the same for the snapshot
  release of PR `<n>` (tag `pr-<n>`), to try a PR before it is merged.
- `scripts/install-app <zip>` installs that zip.

Installing is the same for all four: unpack the zip into a temporary
folder, verify the signature (`codesign --verify --deep --strict`),
copy the app next to the installed one, remove the quarantine attribute
from the copy recursively and check that no file still carries it, then
replace the installed app (the old one is renamed aside to
`.Multi Screen Recorder.app.old` and deleted only once the new one is in
place; if the move fails it is put back), and print the installed
version. An `.old` app left by an install that stopped makes it refuse
until a person has checked it. The script refuses, before changing anything, while
the installed app's `msr` runs (the app, or `msr record` started by
any path or symbolic link): it asks `lsof -a -t -d txt` for the
processes that have that very file open as their program, which is by
the file's identity, not by the name a process was started with.

The installed app keeps the Screen & System Audio Recording and
Microphone permissions because every build is signed with the same
certificate (D5); a build signed ad hoc (`SIGNING_IDENTITY=-`) loses
them. It needs no "Open Anyway" because the quarantine
attribute is removed. The tests run the script with a zip argument on
small stand-in bundles; the modes without an argument and `--release`
build, sign and download, so no test runs them.

## Why

- A self-signed certificate that stays the same gives every build the
  same signature, which is what lets macOS keep the two permissions
  across updates (D5); unverified until one snapshot release is
  installed over another.
- Counting commits needs no tag bookkeeping and cannot go backwards.
- Keeping the secret out of the build and sign scripts means the tested
  procedure is the shipped one, on a Mac and in CI alike.
- Ordering steps inside one job does not keep the key from code that
  ran earlier in it: `swift build` runs dependency manifests, plugins
  and macros, which can leave a process, a `PATH` shim or an edited
  script behind. A job of its own on a fresh virtual machine does
  (D29).

## Accepted risks

- A PR's pipeline run executes the branch's code with the signing
  secret before a human has reviewed it. Accepted (D23): a
  self-signed certificate matters only on Macs that granted this app
  its permissions. Developer ID signing, when it comes, needs an
  approval step before the signing job.
- Narrowed (D28, D29): the key lives only in a signing job, which
  compiles nothing and executes nothing from the artifact, on a fresh
  virtual machine, imported non-extractable. What remains:
  - A poisoned build is still signed: code that a dependency, a plugin
    or a macro slips into `msr` during `test-and-build` reaches the
    signed app. The defence is reviewing dependency bumps and keeping
    versions pinned (`Package.resolved`, actions by commit).
  - Whoever can push a branch to this repository can change the
    signing scripts and so use the key. PRs from forks and from
    Dependabot get no secret.
  - The smoke-tested bundle and the published one differ in their
    signature only; the published one is checked statically, not run.
- Two pushes to `main` whose builds finish in the other order are
  released in that order: the older version is created last and may
  then be marked the latest release, which the README sends people to.
  UNVERIFIED either way: `gh release create --help` gives the default
  as "automatic based on date and version", which may keep the newer
  version the latest. Accepted in PR #4 because one person merges, rarely two
  within a build's two minutes, and `gh release edit <tag> --latest`
  fixes it in a minute. Revisit when it happens, or when several
  people merge.

## Rejected

- **An Xcode project, XcodeGen or Tuist:** see recorder.md.
- **A draft release as the snapshot:** invisible to non-collaborators.
- **Workflow artifacts as the snapshot:** they need a GitHub login and
  expire.
- **A password on the `.p12`:** `security import` takes it only on the
  command line. If importing a password-less `.p12` fails on the
  runner, the fallback is the key and certificate as PEM.

## Open questions

None.
