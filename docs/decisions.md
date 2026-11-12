# Decisions

The project's decisions, one dated entry each. Every decision in force in
[architecture.md](architecture.md) cites its entry here; every ruling
and every principle change gets one too (see "Changing a principle" in
[principles/ai-working-process.md](principles/ai-working-process.md)).
Append-only: an entry is written after a human's yes, in the same
change as what it records. Entries are numbered D1, D2, … in order and
dated. An entry is never deleted: a superseded one stays, marked with
the entry that superseded it.

A deliberate omission (something left out of the system or the docs
on purpose) is a decision too: its entry gives the reason, so a later
session doesn't add it back as a fix, and any count or list that would
include it says so ("four of five, see D<n>").

An entry is lean: the decision, one line of why, what it replaces, and
links to its evidence (the PR, the design doc, the commit). The
evidence stays where it lives; an entry carries no incident narrative,
no measurements and no list of what was carried out. A decision that
needs more room gets a design doc, linked. A ruling's entry quotes the
human's words in its Context and marks any elaboration as the
architect's reading.

## Format

```markdown
## D<n>: <title> (<YYYY-MM-DD>)

- **Status:** in force | superseded (in whole or in part) by D<m>
- **Context:** why it was needed, one or two sentences; for a ruling,
  the human's words, quoted.
- **Decision:** what was chosen; replaces D<m>, in whole or in part,
  where it does.
- **Consequences:** what gets harder, what is hard to undo.
- **Evidence:** links to the PR, the design doc, the commit.
```

## D1: An independent product, written from scratch (2026-11-12)

- **Status:** in force
- **Context:** The owner started from a fork of
  `UBA-PSI/psi-screencapture-macos` (MIT, Dominik Herrmann, PSI chair,
  University of Bamberg) and decided to "disconnect from upstream and
  continue independently, using the existing content only as
  reference", in a new repository.
- **Decision:** Multi Screen Recorder is its own product: a clean
  implementation in `schlomo/multi-screen-recorder-macos`, bundle ID
  `org.schapiro.multiscreenrecorder`. The former upstream's code is a
  reference only; the README points to it and credits its author.
  Out of scope: editing features, cloud upload, camera capture.
- **Consequences:** Nothing is merged from or contributed back to the
  former upstream (D16). Any code that is derived rather than rewritten
  keeps its MIT notice.
- **Evidence:** the setup commit.

## D2: Licence GPLv3 (2026-11-12)

- **Status:** in force
- **Context:** The owner chose GPLv3 for the new repository.
- **Decision:** The project is licensed under the GNU GPL version 3
  (`LICENSE`, the text from gnu.org).
- **Consequences:** The MIT-licensed reference code is compatible, so
  even a derived part could ship under GPLv3 with its MIT notice kept.
  Code here cannot flow back into an MIT project without the owner
  dual-licensing it.
- **Evidence:** the setup commit.

## D3: GitHub, trunk `main`, squash merges (2026-11-12)

- **Status:** in force
- **Context:** A single owner; "everything comes in squashed".
- **Decision:** The code lives on GitHub; `main` is the trunk; pull
  requests are merged as one squash commit; a branch catches up by
  merging `main` in. The setup commit was pushed straight to `main`,
  because an empty repository has no trunk to open a PR against; it is
  the only direct push.
- **Consequences:** `main` gets one commit per change; the individual
  work-in-progress commits of a branch are not kept there.
- **Evidence:** the setup commit.

## D4: Every PR yields a snapshot release, every merge a release (2026-11-12)

- **Status:** in force
- **Context:** The owner asked to "auto build from main to GH release as
  much as is possible", "releases from main via PRs", and "PR builds
  must build an artifact that users can easily install".
- **Decision:** Each PR build publishes a snapshot release that can be
  installed on a Mac; each merge to `main` publishes a GitHub release.
  Version numbers are counted from the git history and stay 0.x until
  the owner declares v1. Tests gate both.
- **Consequences:** Every merge is a release, so the tests are the only
  gate before users get a binary. The exact version format and whether
  a snapshot release is a pre-release or a draft release are left to
  the first architect session (`backlog.md`).
- **Evidence:** the setup commit.

## D5: Signed with one self-signed certificate; no Developer ID yet (2026-11-12)

- **Status:** in force
- **Context:** The owner has no Apple Developer Program membership yet
  and "will get it if worth it"; free signing is how the project starts.
- **Decision:** One self-signed code-signing certificate, created once
  and kept as a GitHub secret, signs every build, so the signature stays
  the same from build to build.
- **Consequences:** The aim is that the Screen & System Audio Recording
  and Microphone permissions survive updates; that is unverified until
  the first snapshot release is installed over another (`backlog.md`).
  A downloaded build needs "Open Anyway" in System Settings once, which
  novices may not manage; Developer ID signing and notarization are
  deliberately deferred (`backlog.md`).
- **Evidence:** the setup commit.

## D6: Work tracked in `backlog.md`, outside reports in GitHub Issues (2026-11-12)

- **Status:** in force
- **Context:** One owner, no tracker; "external users should open issues
  as needed".
- **Decision:** Planned work lives in `backlog.md`. GitHub Issues are the
  intake for outside users; the architect triages them into
  `backlog.md`.
- **Consequences:** `backlog.md` stays the one place that says what is
  next; an issue is not planned work until it is in it.
- **Evidence:** the setup commit.

## D7: Environments: the user's Mac and a homepage (2026-11-12)

- **Status:** in force
- **Context:** The app runs locally; the owner wants
  `multiscreenrecorder.schapiro.org` as its homepage, "built from a
  separate branch in the same repo".
- **Decision:** The software runs only on the user's Mac; there is no
  server. The homepage is served by GitHub Pages from a separate branch
  of this repository, at `multiscreenrecorder.schapiro.org`.
- **Consequences:** The homepage branch is a second long-lived branch;
  its name, how changes reach it, and the DNS entry are open
  (`backlog.md`).
- **Evidence:** the setup commit.

## D8: Agents push work branches and open draft PRs (2026-11-12)

- **Status:** in force
- **Context:** Setup's write-level question; the owner chose the
  default.
- **Decision:** Agents push their own work branches and open draft PRs;
  only the owner merges.
- **Consequences:** An agent sees its own CI results and fixes them
  before review; nothing reaches `main` without the owner.
- **Evidence:** the setup commit.

## D9: AI-written commits and PRs say so (2026-11-12)

- **Status:** in force
- **Context:** The owner asked for AI attribution.
- **Decision:** `attribution` stays unset in `.claude/settings.json`, so
  Claude Code names the model as co-author on each commit and adds a
  generated-with line to each PR description.
- **Consequences:** It is a default, not an enforced policy: a personal
  instruction can override it; only managed settings or a CI check on
  commit trailers would enforce it.
- **Evidence:** the setup commit.

## D10: macOS 26 and later, Apple silicon only (2026-11-12)

- **Status:** in force
- **Context:** "Aiming for most modern macOS (26ff) and ARM64 only, no
  legacy."
- **Decision:** The app targets macOS 26 and later on Apple silicon
  (arm64). The owner's test Mac is an M3 Pro with macOS 26.
- **Consequences:** No Intel or older-macOS builds, and no
  compatibility code for them; macOS 26 APIs may be used freely.
- **Evidence:** the setup commit.

## D11: Constant 30 fps video with a chosen recording resolution (2026-11-12)

- **Status:** superseded in part by D30 (a display whose size changes
  mid-file)
- **Context:** Recordings are edited in DaVinci Resolve on 30 fps
  timelines, which needs a constant frame rate; a recorder tested by the
  owner stamped new screen content up to 76 s early after a still
  period, which only comparing content against a camera revealed.
- **Decision:** Video is written at a constant 30 fps on the host
  clock: every 1/30 s the latest complete frame is appended, so a frame
  is shown at the time it was captured. Encoding uses the hardware
  encoder, with the keyframe interval set in seconds. The recording
  resolution is a maximum box: Native, 4K (3840×2160), 1440p
  (2560×1440), 1200p (1920×1200), 1080p (1920×1080, the default) or 720p
  (1280×720). A display file's frame size is fixed when it starts: the
  display's size, shrunk to fit the box with its proportions kept,
  never enlarged. A display that grows mid-file is shrunk into that
  frame; one that shrinks or changes shape is centred with black
  borders. Neither starts a new file.
- **Consequences:** Timing must be verified by content, not by
  timestamps (the v1 gate in `backlog.md`). A still screen costs little
  space only if the encoder settings allow it, to be measured.
- **Evidence:** the setup commit.

## D12: Audio sources as separate tracks; a file keeps the tracks it started with (2026-11-12)

- **Status:** superseded in part by D31 (the layout of the audio in the
  display files, the silence padding, the audio file for a late source;
  the audio mode and the switches stand)
- **Context:** Each display file must sync on its own by waveform with
  a separate speaker recording, so it needs the audio. Audio sources
  come and go like displays, and a file writer cannot add a track once
  the file has started (AVAssetWriter).
- **Decision:** The audio mode is none, the default microphone, or all
  audio inputs; system audio and automatic gain control (AGC) are
  separate switches. Each source is its own track in every display
  file. A file keeps the tracks present when it started: a source that
  disappears is padded with silence; a source that appears mid-file is
  written to its own audio file, on the same clock, and joins the
  display files at their next new file. Output devices are never
  changed, so playback keeps going, for example over HDMI.
- **Consequences:** A late source lives in a separate audio file until
  the next new file. AGC can duck or echo-cancel other audio, so it is
  tested against HDMI playback before it ships (`backlog.md`).
- **Evidence:** the setup commit.

## D13: One recorder core, an app and a full command line (2026-11-12)

- **Status:** in force
- **Context:** "One button minimal GUI … start app → approve last
  settings or configure → start recording → click dock icon to end
  recording", and a "full CLI for everything for scripting".
- **Decision:** One recorder core with two front ends. The app opens a
  small window showing the last settings, to approve or change, and a
  Start button; while recording it shows a Dock icon with a badge;
  clicking the Dock icon asks "Stop recording?", then finalizes the
  files and reveals them in Finder. The command line offers everything
  the app does. Both read one settings file in readable JSON;
  command-line flags override it for that run. On first start the
  defaults are: default microphone, system audio on, AGC off, 1080p,
  output to `~/Movies/Multi Screen Recorder/`. The interface is English
  only.
- **Consequences:** Every feature exists in both front ends, which keeps
  the hardware acceptance tests scriptable.
- **Evidence:** the setup commit.

## D14: Safeguards against losing a recording (2026-11-12)

- **Status:** in force; extended by D31's change to audio files (the
  architect's reading: the restart of a failing stream and the recovery
  after a full disk apply to an audio file as to a display file)
- **Context:** "Focus on reliability and preventing data loss, and
  minimal gaps on screen changes."
- **Decision:** Before Start, a ready check confirms both permissions,
  the chosen sources, and free disk space for a configurable number of
  hours. While recording, low disk space is warned about; if the disk
  is full the recorder keeps retrying and never discards what is
  written. Files are written in short fragments so they stay readable
  after a crash; on the next launch, files that were not finalized are
  reported. The Mac is kept awake while recording. A display that
  appears or disappears, or a stream that fails, affects only its own
  file, with as small a gap as possible.
- **Consequences:** The fragment length and the gap on a restarted
  stream are set and measured by the first design.
- **Evidence:** the setup commit.

## D15: No network access (2026-11-12)

- **Status:** in force
- **Context:** The owner chose no network, with an About dialog
  "pointing to GH issues as feedback mechanism".
- **Decision:** The app makes no network connections: no telemetry, no
  update check, no upload. The About dialog links to the GitHub Issues
  page, which opens in the user's browser.
- **Consequences:** Recordings never leave the Mac, which keeps data
  protection simple; users learn of updates from the homepage or
  GitHub.
- **Evidence:** the setup commit.

## D16: No contributions to the former upstream (2026-11-12)

- **Status:** in force
- **Context:** An earlier plan split the work into opt-in, upstreamable
  PRs and a draft issue for the former upstream. D1 and D2 replace that
  plan.
- **Decision:** Deliberate omission: no upstreamable PR structure, no
  opt-in flags for upstream compatibility (constant frame rate is
  always on), and no issue to the former upstream.
- **Consequences:** A later session should not reintroduce
  upstream-compatibility flags as a fix.
- **Evidence:** the setup commit.

## D17: Swift, always the latest toolchain (2026-11-12)

- **Status:** superseded in part by D28 (which toolchain the pipeline
  uses)
- **Context:** Asked "is swift the right tool here? Or better rust?",
  with "only AI will develop here, with human supervision and partial
  review", the owner ruled: "yes to latest swift, and we always aim for
  latest with rather fast upgrades. dependabot for patches".
- **Decision:** The product is written in Swift, in the Swift 6
  language mode with strict concurrency checking and warnings treated
  as errors. The toolchain is the latest released Swift and Xcode,
  upgraded soon after each release. Dependabot proposes dependency
  updates. The architect's reading: Dependabot covers the GitHub
  Actions and Swift packages in use; a toolchain upgrade is a change of
  its own.
- **Consequences:** Rust is set aside, also as a core under a Swift
  shell; revisit only for a Linux or Windows version or for encoder or
  container code of our own (`backlog.md`).
- **Evidence:** [design/recorder.md](design/recorder.md).

## D18: v0 in two PRs, with three audio features after it (2026-11-12)

- **Status:** in force; superseded in part by D31 (the audio file for a
  late audio source is no longer a feature of its own: every audio
  source has its own audio file)
- **Context:** Whether one self-signed certificate keeps the
  permissions across updates (D5) decides whether the delivery model
  works at all, and is cheapest to learn before the recorder exists.
  The owner agreed to the split and the scope ("A–F").
- **Decision:** v0 arrives as two PRs: first the skeleton and pipeline
  (the app window with the ready check, `msr list`, `check`, `settings`
  and `version`, signing, snapshot release and release), then the
  recorder. v0 records with the audio mode none or default microphone,
  plus system audio. The audio mode all inputs, the audio file for a
  late audio source, and AGC follow in later PRs; D12 stays in force.
  Replaces the "one longer-lived PR" plan in `backlog.md`.
- **Consequences:** Until then a source that appears mid-recording
  joins only at the next new display file.
- **Evidence:** [design/recorder.md](design/recorder.md).

## D19: The command line is the app's executable; flags mirror the settings (2026-11-12)

- **Status:** in force
- **Context:** The draft's flags and settings keys used different words
  for one thing. The owner: "yes, needs to be self-explanatory for
  human and AI".
- **Decision:** The app's executable `msr` is the command line: with
  arguments it runs headless, without it is the app. Commands: `list`,
  `check`, `record`, `settings`, `version`. Every settings key has a
  flag of the same name in kebab case, with the same values. A key
  exists only once its feature does. Low disk space is shown by a Dock
  badge and a bouncing Dock icon, not a notification.
- **Consequences:** Started from a terminal, macOS attributes the
  permissions to the terminal app. Usage errors exit 64 (Swift Argument
  Parser).
- **Evidence:** [design/recorder.md](design/recorder.md).

## D20: Recording folder, recording manifest, parallel recordings (2026-11-12)

- **Status:** in force
- **Context:** On two recorders at once the owner ruled: "should
  prevent multiple invoications on same folder, nice if we can support
  multiple parallel recordings that don't conflict".
- **Decision:** Each recording has its own recording folder, named by
  its local start time; each display file's name starts with its own
  date and time. One recording manifest, `recording.json`, replaces the
  reference implementation's JSON file beside each display file. A
  recording claims its folder by creating it and refuses if it exists;
  recordings into different folders may run in parallel, each with its
  own crash marker. The app runs one recording at a time.
- **Consequences:** File names are unique outside their folder and sort
  by time.
- **Evidence:** [design/recorder.md](design/recorder.md).

## D21: HEVC in .mov, no dropped tick, timecode in every display file (2026-11-12)

- **Status:** in force; refined by D31 (audio files carry the timecode
  track too; display files carry guide tracks, not the audio tracks)
- **Context:** The draft skipped a tick the encoder could not take,
  which breaks the constant frame rate (D11). The owner agreed to never
  dropping one and added: "we need to write timecode into the files as
  resolve can read them unless this is super hard". Output "must work
  on free too (and other editor apps)"; the owner checks once with
  Kdenlive.
- **Decision:** Display files are HEVC 8-bit in `.mov` with AAC audio,
  written in fragments of 2 s, with a keyframe every 2 s; both values
  are data. Every tick is written; a late one keeps its timestamp and
  is counted. Each display file carries a time-of-day timecode track at
  30 fps. Apple's `SCRecordingOutput` is not used.
- **Consequences:** If timecode cannot be combined with fragmented
  writing, that goes back to the owner rather than being dropped.
  Whether HDR displays are recorded as HDR is open (`backlog.md`).
- **Evidence:** [design/recorder.md](design/recorder.md).

## D22: Every audio input channel is its own mono track (2026-11-12)

- **Status:** in force; refined by D31 (the channels stay separate
  mono tracks, now in the audio input's audio file)
- **Context:** The owner: "all channals stay separate, whatever comes.
  Imagine somebody plugging in a USB wireless mic reseiver with 2
  people on L/R".
- **Decision:** Each channel of an audio input is written as its own
  mono track, named by device and channel; nothing is mixed down. The
  architect's reading: system audio, a stereo mix by nature, stays one
  stereo track.
- **Consequences:** An input with many channels adds that many tracks
  to every display file. Refines D12's "each source is its own track".
- **Evidence:** [design/recorder.md](design/recorder.md).

## D23: Pipeline: pre-release per PR, versions count commits, the build never sees the secret (2026-11-12)

- **Status:** superseded in part by D29 (which script signs, and in
  which job)
- **Context:** D4 left the version format and the kind of snapshot
  release open. The owner agreed to the proposals, to "use filters" so
  that documentation pushed to `main` publishes nothing, and to
  accepting that a PR's pipeline run sees the signing secret before
  review.
- **Decision:** A snapshot release is a GitHub pre-release per PR, tag
  `pr-<number>`, replaced on every push and removed when the PR closes.
  A release is `v0.<N>.0`, N being the number of commits on `main`. A
  push to `main` that changes only Markdown files publishes nothing.
  The build script signs with an identity by name and never handles the
  secret; one CI-only script imports it into a temporary keychain. PRs
  from forks and from Dependabot are tested but get no snapshot
  release.
- **Consequences:** Release numbers can skip. Developer ID signing,
  when it comes, needs an approval step before the signing job.
- **Evidence:** [design/delivery.md](design/delivery.md).

## D24: Displays are recorded in SDR (2026-11-12)

- **Status:** in force
- **Context:** The owner asked "what about HDR? maybe we should use
  what the display does and leave the conversion to the editor?" and,
  after the architect recommended SDR for v0, ruled: "OK, stay with
  SDR."
- **Decision:** Every display is recorded in SDR (HEVC 8-bit), also one
  in HDR mode; the colour space is tagged. Closes the question D21 left
  open. The architect's reading: a `dynamicRange` setting is not
  planned; it is deferred (`backlog.md`).
- **Consequences:** True HDR highlights are tone-mapped by macOS before
  they are recorded.
- **Evidence:** [design/recorder.md](design/recorder.md).

## D25: Details the design left open, as built in PR #1 (2026-11-12)

- **Status:** in force; choice 3 superseded by D28
- **Context:** PR #1 listed seven choices where the design was silent.
  The owner: "confirm all but 2 - why not accept any output folder? 7 -
  I guess for portrait screens we rotate the dimensions, no?" and,
  after the architect explained that only relative paths are rejected,
  "ok, keep 2 as is, I didn't realize you meant a config item".
- **Decision:** The seven choices stand as built, except the seventh:
  (1) a key missing from the settings file takes its default; (2) the
  output folder must start with `/` or `~`, and the two number settings
  must be greater than 0; (3) a settings file that cannot be used makes
  every command exit 1; (4) `msr version` prints the full version and
  the commit, from the Info.plist keys `MSRVersion` and `MSRCommit`;
  (5) the settings file is found through `HOME`; (6) the disk estimate
  follows its rule, scaled by each frame's pixel count, so the design's
  example reads 3.7 GB, not 4.0 GB; (7) the recording resolution box
  rotates for a portrait display. The architect's reading of the
  owner's question on portrait displays, turned into the rule: a
  display taller than wide uses the box turned upright, so 2160×3840 at
  1080p records 1080×1920, not 606×1080.
- **Consequences:** The architect's reading: a portrait display file is
  as sharp as a landscape one at the same recording resolution, and
  larger than before.
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/recorder.md](design/recorder.md) "Build state".

## D26: The window says what Start records; About shows the purpose (2026-11-12)

- **Status:** superseded in part by D33 (the summary lines of what
  Start records)
- **Context:** The owner: "about dialoge should not mention previous
  art but the short purpose text", "the main screen should briefly
  explain what it is actually doing", "the ready check should be
  collapsed if all green".
- **Decision:** The About window shows the version, the licence, the
  short purpose text and the GitHub Issues link, without the credit to
  the former upstream; the main window explains what Start records; an
  all-green ready check is collapsed. The architect's reading: the
  purpose text is the README's opening paragraph, one string in the
  code; the credit stays in the README (D1), and no earlier entry put
  it in the About window, so none is superseded. The explanation is two
  or three lines at the top of the window, built from the current
  settings and devices and tested: every display, the audio sources,
  where the files go, and that recording continues when displays or
  audio sources change. All green shows one line, "Ready to record",
  that expands on click; any red item shows the list expanded with its
  fix.
- **Consequences:** The window's text follows the settings and devices
  and is tested like the rest of `RecorderLogic`.
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/recorder.md](design/recorder.md) "The app".

## D27: The setting `readyCheckHours` is named `requiredRecordingHours` (2026-11-12)

- **Status:** in force
- **Context:** The owner asked "what are these? "readyCheckHours": 2,
  "lowDiskWarningMinutes": 20" and ruled "confirmed, rename to
  requiredRecordingHours".
- **Decision:** The settings key is `requiredRecordingHours`, its flag
  `--required-recording-hours`. The architect's reading: nothing is
  released, so there is no migration and no alias.
- **Consequences:** A settings file written by an earlier snapshot
  release with `readyCheckHours` stops with "unknown key"; the app
  offers "Reset to defaults".
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/recorder.md](design/recorder.md) "Settings file".

## D28: Rulings on the adversarial review of PR #1 (2026-11-12)

- **Status:** superseded in part by D29 (point 5: the key imported
  "only after compilation" in the same job)
- **Context:** The architect put seven recommendations from the
  adversarial review of PR #1 to the owner, who answered "Accept all
  seven".
- **Decision:** The architect's wording of what was accepted:
  (1) `msr` started through a symbolic link re-executes itself at its
  fully resolved real path with the same arguments, so it finds its app
  bundle. (2) The ready check has an "Output folder" item before "Free
  disk space": it creates the folder with its parents if missing and
  writes and deletes a probe file in it; free disk space is measured on
  the folder itself and left out when the folder fails. (3) The app
  re-runs the ready check when it becomes active and on "Check again";
  with the Microphone permission granted and no microphone, the
  permission item passes and the "Audio" item alone fails, with "no
  microphone". (4) Toolchain: the pipeline uses the latest Xcode and
  Swift that GitHub's generally available macOS runner image offers
  (today Xcode 26.6, Swift 6.3), not a preview image; revisited when a
  newer runner image is generally available. This narrows D17's
  "latest released" wording and replaces it in part. (5) Credentials:
  `scripts/ci-import-signing-certificate` is the one place that reads
  the signing certificate from the environment and puts it into a
  keychain, because macOS has no tool that reads a certificate from the
  environment itself; this is a ruling on how "Credentials are pure
  injection" applies here, not a change of the principle; no other
  code touches the secret; the key is imported non-extractable and only
  after compilation has finished, with building (`scripts/build-app`)
  and signing (`scripts/sign-app`) split for it. (6) The architecture
  doc and the backlog were edited on this work branch once, because
  design and build arrive together; the rule itself is unchanged.
  (7) The scripts are tested from the Swift test suite
  (`scripts/version` in scratch git repositories, and it stops on a
  shallow clone), and a settings file that cannot be used makes every
  command that reads the settings exit 78 (`EX_CONFIG`), so `msr check`
  exiting 1 means only "not ready"; this replaces D25's choice 3.
- **Consequences:** The package's tools version follows the runner
  image, not the newest Xcode on a developer's Mac. A branch's scripts
  still run while the key is in the CI keychain (D23's accepted risk,
  narrowed).
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/delivery.md](design/delivery.md),
  [design/recorder.md](design/recorder.md).

## D29: Build and sign in separate jobs, with a smoke test in the build (2026-11-12)

- **Status:** in force
- **Context:** Code that runs during `swift build` (dependency
  manifests, plugins, macros) can leave a process, a `PATH` shim or an
  edited script behind for a later step of the same job, so ordering
  steps in one job does not keep the key away from it. The owner: "then
  maybe build and sign must happen in separate jobs with artifact
  passing to ensure that key is in clean environment? And how to
  prevent builder from seeing that variable (map only into signer?)",
  then "confirmed, two-job design", then "ok, go with two jobs and
  smoke test in build."
- **Decision:** A job without any secret or token tests, builds the
  app (signed ad hoc with the real options), smoke-tests the bundled
  `msr` and uploads the app as a tar archive; the signing jobs
  (`snapshot-release`, `release`) download it, unpack it, import the
  certificate with the secret mapped into that one step, re-sign,
  check the signature statically and publish with the token mapped
  into that one step. Forks and Dependabot get the first job only.
  The architect's reading: the unit tests, the build and the smoke
  test share the one job `test-and-build` (one runner start fewer);
  the signing jobs refuse the three things that cross between jobs: no
  cache is restored; the artifact is data, unpacked into an empty
  folder with a path check, never executed; scripts come from the
  job's own checkout. Replaces D28's "only after compilation" in part,
  and D23's signing by the build script.
- **Consequences:** Rests on GitHub giving every hosted job a fresh
  virtual machine; a self-hosted runner would break it. A poisoned
  build is still signed, and whoever can push a branch can change the
  signing scripts (accepted risks in the design).
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/delivery.md](design/delivery.md).

## D30: A new display file when the frame size changes (2026-11-12)

- **Status:** in force
- **Context:** D11 kept a display file's frame size when the display
  changed mid-file, shrinking or centring the picture. The owner:
  "native means that we start with the current resolution and if it
  changes then we scale into it, right? and new displays get recorded
  at their native resolution on first contact? Or native means always
  restart recording on resolution change? I think the latter is more
  correct to meet the expectations. In any case, a resolution change
  carries a small visual flicker / glitch so a <1s gap in recording
  might be OK, too" and, to the rule the architect then proposed, "yes,
  confirm frame size, shape rule and restart on shape change, good
  thinking".
- **Decision:** The architect's wording, confirmed by the owner: the
  frame size is the display's pixel size fitted into the recording
  resolution box, the box turning with a portrait display. While a
  display's frame size stays the same, its file continues,
  whatever else changed about the display. When the frame size
  changes, the display's current file ends and a new file starts at
  the new frame size, like after a reconnect. At `native` every
  pixel-size change is such a change; at `1080p` 3840×2160 to 5120×2880
  is not, 3440×1440 to 1920×1080 is. Replaces D11's shrinking and
  centring of a display that changes mid-file.
- **Consequences:** A gap of under one second in that display's files
  at the change, also in the guide tracks inside them, while the other
  displays' files continue; a display that flaps between modes makes
  many short files, each valid.
- **Evidence:** [design/recorder.md](design/recorder.md) "Frame size".

## D31: One file per source, with guide tracks in the display files (2026-11-12)

- **Status:** in force
- **Context:** Every display file carried every audio source, padded
  with silence, with a separate file for a source that arrived late
  (D12). The owner: "suggest alternatives to writing all audio streams
  to all display files. In theory, with timecode embedded everywhere we
  could just write single files per display and audio device and let
  the editing software puzzle it together (or ffmpeg?)", then "B but
  microphones and system audio are not mixed together but stay in
  separate tracks", then "reading 1".
- **Decision:** The architect's wording of the reading the owner chose:
  one file per source, all on the shared t0 and tick grid. A display
  file holds the display's video and its timecode. Each recorded audio
  input gets its own audio file, a `.mov` with AAC-LC at 48 kHz and one
  mono track per channel at 128 kbit/s; system audio gets its own, one
  stereo track at 192 kbit/s; both carry the same time-of-day timecode
  track. Every display file also carries guide tracks for playback and
  waveform sync only: "Microphones", one mono mix of the recorded
  microphone channels at 64 kbit/s, unless the audio mode is `none`, and
  "System audio", stereo at 96 kbit/s, unless system audio is off; the
  two are never mixed, the rates are data, and a missing source is
  silence in its guide track. An audio input that appears starts its
  audio file then, one that disappears ends it; an audio file is never
  padded with silence, and a display event never touches it. The files
  sit beside the display files as `<date time> Microphone - <device
  name>.mov` and `<date time> System audio.mov`; the manifest lists them
  like display files, with the events `audio input connected` and
  `audio input disconnected`. Replaces D12 in part (every source in
  every display file, the silence padding, the audio file for a late
  source); refines D22.
- **Consequences:** An editor places several files per recording by
  timecode; whether DaVinci Resolve reads the timecode of an audio-only
  `.mov`, and how Kdenlive places the files, is unproven until the
  owner's first real recording. A command that joins the files without
  re-encoding is deferred (`backlog.md`).
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/recorder.md](design/recorder.md) "Audio".

## D32: Scripts in Python where that reads better than bash (2026-11-12)

- **Status:** in force
- **Context:** The owner: "accept python and convert build scripts to
  modern python where that improves readability over bash hacks
  (modern = latest present in default CI image to avoid python
  installation) with Pathlib and other modern lingo".
- **Decision:** Python is accepted, also in the signing jobs. The
  architect's reading of "where that improves readability":
  `scripts/version`, `scripts/unpack-app` (which absorbs
  `Tools/unpack_app.py`), `scripts/sign-app`, `scripts/smoke-test` and
  `scripts/publish-snapshot-release` are Python; `scripts/test`,
  `scripts/build-app`, `scripts/ci-import-signing-certificate`,
  `scripts/publish-release` and `scripts/remove-snapshot-release` stay
  bash. The minimum is the `python3` on the `PATH` of the default
  `macos-26` arm64 runner image, read from its software list in
  `actions/runner-images` (3.15 today); each script stops on an older
  one with an error naming the minimum. Standard library only, so
  nothing is installed.
- **Consequences:** A developer's Mac needs that Python as `python3`;
  the one macOS ships is older. The minimum follows the runner image.
  The architect's reading: as nothing is installed, the Python platform
  note's `uv` and `pytest` do not apply here; the Swift suite keeps
  testing the scripts as commands.
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/delivery.md](design/delivery.md).

## D33: The window shows displays and audio as tables with GB per hour (2026-11-12)

- **Status:** in force
- **Context:** The owner: "this is actually useful information, the
  start dialoge should nicely show that IMHO", then "so I think a table
  makes sense for the display info with: display, physical res, logical
  res, GB/h and audio similar device, channel count, AGC (future), GB/h
  and then the total GB/h as sum below that." and "confirmed, go with
  these adjustments".
- **Decision:** "What will be recorded" is two tables and a total line.
  Displays: Display (number and name), Looks like, Drawn at, Records
  at, GB/h. Audio: one row per audio input (the default one marked) and
  one for system audio, with Channels (a number, or "stereo") and GB/h;
  a source not recorded is dimmed and shows "not recorded". Below,
  "Total <x> GB/h. <hours> hours need <y> GB, <z> GB free.", without
  the free part when the free space is unknown. The architect's
  reading: "Looks like" and "Drawn at" instead of logical and physical
  resolution, because with a HiDPI mode on an ordinary panel the larger
  size is not the panel's; an added "Records at" column; no AGC column
  until AGC exists; audio counted in the disk estimate, which the ready
  check uses too. Replaces D26 in part (the summary lines).
- **Consequences:** The disk estimate counts every file a recording
  writes, guide tracks and audio files included, so the ready check
  asks for a little more space than before.
- **Evidence:** [PR #1](https://github.com/schlomo/multi-screen-recorder-macos/pull/1),
  [design/recorder.md](design/recorder.md) "The app".
