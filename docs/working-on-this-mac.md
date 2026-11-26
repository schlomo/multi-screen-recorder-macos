# Working on this Mac

The long bodies that `AGENTS.md` keeps as headlines: how agents write to
the remote, the pipeline, the environments, running the tests and the
facts that bite. Read the section a task touches; the rules that bind
every agent stay in `AGENTS.md`.

## Project setup details

- **Agent writes:** push work branches and open draft PRs, and mark a
  PR the agent opened ready once it is fully reviewed (D39). Copilot's
  review is an optional extra (D43): a repository ruleset is configured
  to request one review of each draft PR (not observed on PRs #6 to #8;
  whether it fires is the owner's to check), nobody waits for it, and
  its absence never blocks marking a PR ready; one that has arrived is
  handled by the session that owns the PR like the adversarial
  review's findings.
  Standing go-ahead for those optional Copilot reviews, billed as AI
  credits to the PR's author, the owner's GitHub account. How: the
  architect skill's `references/operating-rules.md`, "Copilot's review".

- **Pipeline:** GitHub Actions, `.github/workflows/ci.yml`, wiring the
  scripts in `scripts/` on hosted Apple-silicon macOS runners: job
  `test-and-build` tests, builds and smoke-tests without any secret;
  after it one of two separate signing jobs signs and publishes, for every push to a
  PR without the skip-ci marker the PR's snapshot release (a pre-release tagged `pr-<n>`), for a
  push to `main` that changes more than Markdown files and the homepage
  (`homepage/`) a release `v0.<DATE>.<N>`, so a homepage-only push makes
  no release; a closed PR's snapshot release is removed (a head commit
  with the skip-ci marker first needs an unmarked empty commit, see
  "Work branches"). PRs from
  forks and Dependabot are tested, built, smoke-tested and end-to-end
  tested, never signed or published. Signing needs the repository secret
  `SIGNING_CERTIFICATE_P12` ([delivery.md](docs/design/delivery.md)).
  Who may register pipelines and edit branch policies: the repository
  owner.

- **Environments:** the user's Mac; the homepage, a Hugo site in
  `homepage/` on `main`, built and served by Cloudflare Workers Builds
  at `multiscreenrecorder.schapiro.org` (D53); connecting the Worker to
  the repository is the owner's ([homepage/README.md](homepage/README.md)).

## Running the tests

`scripts/test` compiles the Python scripts, then runs the tests (Swift
Testing, `swift test`), including those that run `msr settings`,
`msr version`, `msr timeline` and the scripts as commands; `scripts/build-app` builds the app in `build/` (signed ad
hoc), `scripts/smoke-test` runs the bundled `msr` safely, and
`scripts/sign-app` re-signs and zips it (`SIGNING_IDENTITY=-` signs ad
hoc, for a local check only), and `scripts/install-app` installs it (see
below). The end-to-end tests are a manual step, not in the pipeline
(D67): `scripts/end-to-end-setup` builds a tart VM once (needs `tart`
and `packer` on the `PATH`), and `scripts/end-to-end-test
--scratch-folder <folder>` builds the app and the driver, runs the
driver in a throwaway clone of that VM (it records with the built app
while it adds a virtual screen and plays a tone into BlackHole, then
examines the recording folders and takes a screenshot of the app's
window) and copies its scratch folder back; its exit status is the
driver's
([end-to-end-tests.md](docs/design/end-to-end-tests.md)); with
`--release` or `--snapshot <n>` it runs that published app instead of
the built one. They need an idle Mac: another VM, video editing, a
virus scan or a backup running can make them fail. Before a PR
that touches the recorder or the end-to-end driver is marked ready,
the architect runs `scripts/end-to-end-test` on the PR's head and
records the commit and the result in the PR description. The
homepage's screenshots come from a published app's run, as a
homepage-only follow-up that `scripts/update-homepage-screenshots
--release` (or `--snapshot <n>`) commits, pushes and, for a release,
opens as a draft PR (D72); `--this-mac` takes them on the owner's Mac
instead and only copies them into the checkout (D82).

## Facts that bite

- Building and testing need macOS 26 or later on Apple silicon with
  Xcode 26 or later; CI has Xcode 26.6 (Swift 6.3), and the package
  must build there ([delivery.md](docs/design/delivery.md)). A Linux
  container (such as a cloud agent session) can edit and review but not
  build or run anything. Say UNVERIFIED for any change not built and
  run on a Mac or by CI.
- The Command Line Tools alone build the package but cannot run the
  tests: Swift Testing needs Xcode, selected and with its licence
  accepted (`scripts/test` checks this first).
- Six scripts are Python, standard library only, and need Python 3.15
  or later as `python3` on the `PATH` (the runner image's; macOS ships
  an older one); see [delivery.md](docs/design/delivery.md).
- `msr` without arguments starts the app, and the app, `msr check` and
  `msr record` run the ready check, which requests any never-asked
  permission and captures one frame of a screen (not at the recording
  resolution None without the system audio), so macOS shows a
  prompt on the person's screen, and
  creates the output folder if it is missing; `msr record` and Start
  in the app record the screens and, by default, every real camera,
  asking for the Camera permission if never asked (D74); `msr list`
  reads the devices. An agent
  runs these on the owner's Mac only to test the roadmap's work, or
  through `scripts/update-homepage-screenshots --this-mac` to take the
  homepage's screenshots, which records the owner's real screens,
  cameras and microphones, the owner told before each such run (D82);
  the tests run into its
  own scratch folder (`--output-folder`) with `HOME` set to a scratch
  folder too, so the owner's settings and last-recording notice are
  never overwritten or faked (the permissions do not depend on `HOME`;
  the settings fall back to their defaults), deleting the recordings once
  checked and never changing settings or permissions (D48); before an agent starts a recording, opens a camera or plays a sound on the owner's Mac, the session running or briefing that test tells the owner, once before the test's first run (D56); on anyone else's Mac, never unasked. On start the app also reads
  `~/Library/Logs/DiagnosticReports`, may show the crash report dialog
  or the notice of the last recording's problems and open the browser
  and Finder, and may write `state.json` and a text copy under
  `~/Library/Application Support/Multi Screen Recorder`; at Stop the app
  and `msr record` write the last recording into `state.json` (`HOME`
  decides where).
  `msr version`, `msr timeline` (it writes only the folder's timeline
  file), `msr settings` (it writes the settings file only with
  a settings flag; `HOME` decides where) and the tests are
  safe; the tests read the Mac's audio device and camera lists, which
  show no prompt, and open no camera.
- `scripts/install-app` replaces the installed app in `/Applications`,
  so an agent runs it against `/Applications` only with the owner's
  go-ahead for that install (to hand over a try-out build), and never
  while the owner records.
- Real capture needs the Screen & System Audio Recording, Microphone
  and, for a camera, Camera permissions, granted by a person on the Mac (in the
  end-to-end VM, by `scripts/end-to-end-setup`, which writes them into
  its TCC database). Capture behaviour is verified on the owner's Mac
  (the v1 gate in `backlog.md`) and by the end-to-end tests in that VM
  (D67). They run nowhere else: GitHub's hosted runner stalls its own
  video encoder at a virtual screen's mode switch
  ([end-to-end-tests.md](docs/design/end-to-end-tests.md), "Why the
  VM"). The VM has no camera. A run records and plays sound inside the
  VM only, never on the Mac; the VM takes about 30 GB of its disk.
