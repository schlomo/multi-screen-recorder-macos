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

- **Status:** in force
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

- **Status:** in force
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

- **Status:** in force
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
