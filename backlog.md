# Backlog

## Next session starts here

The v0 design is agreed (2026-11-12, D17–D33) and written down in
`docs/design/recorder.md` and `docs/design/delivery.md`. v0 arrives as
two PRs (D18).

The skeleton and pipeline PR (#1) is built, reviewed in three rounds
and publishes a signed snapshot release. Until it is merged, what is
left is under "In flight": the owner's check on the Mac and the merge.
Next for an architect session once it is merged: get the owner's
ruling on the default microphone (first open question in
`docs/design/recorder.md`), then brief the recorder PR; the app icon PR
can run beside it.

## In flight

- **Skeleton and pipeline PR** (D18), branch `v0-skeleton-and-pipeline`:
  the Swift package, the app window with the ready check, `msr list`,
  `check`, `settings` and `version`, the scripts and the pipeline, the
  README's installation and developer setup.
  It also carries the decisions made while it was built: the window's
  tables of what will be recorded (D33), the frame size rule (D30), one
  audio file per source with guide tracks in the display files (D31,
  design only), signing in a job of its own (D29), and the scripts with
  logic in Python (D32).
  - The developer setup is done on the owner's Mac (2026-11-12): Xcode
    selected, the signing certificate, the repository secret.
  - The owner's check on the Mac: install the snapshot release, "Open
    Anyway", start the app from Finder, grant both permissions; after a
    further push, install that snapshot release over the first: both
    permissions are still granted (D5). Also note whether macOS 26
    re-asks for the screen recording permission after some weeks.
    Things to look at on the way: a settings file written by an early
    snapshot has the key `readyCheckHours` and is refused until "Reset
    to defaults"; the two tables and the total line in the window;
    whether coming back to the app with screen recording denied makes
    macOS prompt again (the ready check runs on every activation).

## Queued

1. **Toolchain catch-up** (D28): the pipeline builds with Xcode 26.6,
   Swift 6.3 and Python 3.15, the newest on GitHub's generally
   available runner image (D32 for Python), while the owner's Mac has
   Xcode 27.2. Move the pipeline and the Swift tools version up as soon
   as a runner image with Xcode 27 is generally available.
2. **Recorder PR** (D18): the recording core, `msr record`, Start and
   Stop in the app, a display file per display and an audio file per
   source with guide tracks (D31), a new display file when the frame
   size changes (D30), timecode in every file (D21, D31), mono tracks
   per channel (D22), SDR with the colour space tagged (D24),
   `scripts/acceptance/`. The system audio stream needs a display to
   attach to and must move when that display disappears.
   Its brief must cover what the reviews of PR #1 found for it:
   - The open questions in `docs/design/recorder.md` are answered
     first: the default microphone changing during a recording (the
     owner rules), whether Apple's file writer puts a timecode track
     into an audio-only file, clock drift between an audio device and
     the tick grid, two audio inputs with the same name, device names a
     file name cannot hold, the gain of the "Microphones" guide mix.
   - A display needs a stable identity in `DisplayInfo`; the listing has
     none yet.
   - The app quits when its last window closes; Start closes the
     window, so that must change.
   - The ready check does not run while a recording runs, activation
     included.
   - The ready check probes are free functions: they need a seam for
     tests, and their file access moves off the main thread.
   - The recording manifest is written with `Codable`, not with the
     settings file's hand-written JSON writer.
   - A display mode change can arrive as a disconnect and a reconnect;
     short-lived modes need a settle time, or they make many short
     files.
3. **Audio after v0** (D12, D18), each its own PR: the audio mode all
   inputs; AGC, with its own design, its column in the window's Audio
   table and the HDMI test.
4. **v1 gate:** acceptance tests on the owner's Mac (M3 Pro, macOS 26):
   - Timing by content: record a full-screen clock showing
     milliseconds; across a still period of at least 60 s followed by a
     change, each sampled frame shows the time of its timestamp within
     one frame.
   - `ffprobe`: r_frame_rate = avg_frame_rate = 30/1 and nb_frames close
     to duration × 30 for every display file; each audio input channel
     on its own track in its audio file; the two guide tracks in every
     display file; the timecode of every display file and audio file
     matches its start.
   - One hour, two displays plus microphone: CPU load and file size per
     hour; calibrate the encoder quality, the disk estimate and the
     keyframe interval.
   - Audio drift: a click recorded at the start and after one hour, by
     a USB microphone and by a separate recorder, stays within one
     frame. If it does not, drift correction gets its own design.
   - Mid-recording: plug in and remove a display, change its
     resolution, toggle mirroring, plug and unplug a USB microphone,
     close and open the lid; the recording continues and every file
     stays readable. A frame size change leaves a gap of under one
     second in that display's files and none in the audio files.
   - AGC on: HDMI playback keeps its level.
   - DaVinci Resolve 21.1 on a 30 fps timeline: plays at 30 fps, places
     display files and audio files by timecode (unproven for an
     audio-only file, D31), and Auto Align Clips by waveform matches a
     microphone's audio file to a separate recording.
   - Other players: the files open in QuickTime Player and, checked
     once by the owner, in Kdenlive; how Kdenlive places the files
     decides whether the joining command below is needed.
   - A snapshot release installed over an earlier one keeps both
     permissions, with the app started from Finder (D5).
5. **App icon**, its own PR after PR #1 is merged; until then the app
   has the default icon. The owner chose the drawing (2026-11-12):
   three displays fanned in depth on a graphite tile, one red record
   dot on the front display; graphite `#1E2330`, cool white `#E9EEF7`,
   red `#FF3B30`, the same three colours for the homepage. Flat vector
   master in layers (tile, displays, dot) for the macOS 26 icon format,
   a classic `.icns` if a plain package build cannot compile that
   format, and a small-size drawing with two displays and a larger dot
   below 32 px.
6. **Homepage** (D7): the branch name and how changes reach it
   (architect); the DNS entry for `multiscreenrecorder.schapiro.org`
   (owner).

## Deliberately deferred

- **Developer ID signing and notarization** (D5). Deferred because the
  Apple Developer Program costs €99 a year and the owner can work with
  a self-signed build. Revisit when users beyond the owner need to
  install it without "Open Anyway". It then needs an approval step
  before the signing jobs (D23, D29).
- **A command that joins a recording's display files and audio files**
  into ready-to-play files without re-encoding, driven by the recording
  manifest (D31). Deferred because an editor that reads timecode needs
  none. Revisit when the Kdenlive check fails or the owner wants files
  that play with full sound as they are.
- **Settings migration.** None exists: an unknown key stops with an
  error, and nothing is released yet (D27). Revisit before the first
  change to a settings key after a release `v0.<N>.0` that people use.
- **A snapshot release left behind** by a PR closed with a merge
  conflict (GitHub may not run the removal then; inferred from its
  documentation, never seen). Deferred because the leftover is deleted
  by hand in a minute. Revisit when one appears.
- **Interface languages other than English** (D13). Revisit when users
  ask for one.
- **A `dynamicRange` setting** to record an HDR display as HDR (D24).
  Revisit when the owner records content whose HDR highlights matter.
- **Rust**, also as a core under a Swift shell (D17). Revisit for a
  Linux or Windows version, or for encoder or container code of our
  own.
- **The command line driving the running app**, so that a terminal
  needs no permissions of its own (D19). Revisit when the owner scripts
  recordings from a terminal they don't want to grant screen recording
  to.

## Done (recent)

- 2026-11-12: v0 design agreed (D17–D24); it settled the former queued
  items "v0 design", "build and release pipeline" and "test strategy".
- 2026-11-12: project setup with the starter (D1–D16).
