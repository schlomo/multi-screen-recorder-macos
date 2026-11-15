# Backlog

## Next session starts here

The v0 design is agreed (2026-11-12, D17–D33) and written down in
`docs/design/recorder.md` and `docs/design/delivery.md`. The skeleton
and pipeline PR (#1) is merged (2026-11-14), and the end-to-end test
design is agreed (D37). Agents now mark the PRs they open ready once
fully reviewed, Copilot's review of the draft included (D39,
`AGENTS.md` "Agent writes").

Next, waiting for the owner:

- **Crash reports.** The owner, 2026-11-14: "I think some sort of
  simple crash management would be good now in a subsequent PR as I
  want to go on now." Earlier, 2026-11-13: "maybe we do crash log
  submission via email instead, more private", and “I think that the
  "send to apple" dialogue is useless”. The architect's proposal,
  put to the owner in the session: on the next start after `msr`
  crashed, a dialog offers to send the macOS crash report and the
  app's own log by email, composed in the person's mail app, so
  nothing is sent without them and the app opens no network
  connection; Apple's dialog stays (removing it needs a crash catcher
  in the process or a supervising process, deferred). Email as a
  feedback channel would supersede D15 in part (feedback goes to
  GitHub Issues) and touch the intake line of `AGENTS.md`. The
  architect also proposes that this PR fixes the crash that came back
  ("In flight"), and with it a finding of Copilot's review of PR #1
  that touches the same code: a refresh queued for the window outlives
  a newer device notice, so after a menu closes the devices are read
  once too early and once more after they settle (the newest result
  still wins); a refresh number, like the ready check's, fixes it. It
  has no test yet: the window's refresh gets its tests with the probes'
  seam in the recorder PR (queued item 2), which then pin it; until
  then the owner's re-test in the app checks it. Waits for: the
  owner's sign-off, the address the reports go to, and whether this PR
  comes before the steps below or later (the architect read "now in a
  subsequent PR" as the next PR; the owner is asked).
- Then the steps below; the app icon PR can run beside them.

### Owner's rulings of 2026-11-13 (D34)

Recorded in `docs/decisions.md` as D34; nothing of it is built. In
order, the next architect session:

1. Talks AGC through with the owner: what it does and whether it is on
   in auto mode (open in D34; the owner's meaning: "turning up input
   volume till before it clips and keeping it there"). Facts for that
   talk: the input volume of a device is one value for all apps, and
   not every audio input has one that can be set.
2. Writes the design text for auto mode and for reading a settings
   file without refusing it, and gets it signed off. It must settle
   what D34 leaves open: with auto mode off, how audio inputs are
   chosen and what becomes of the audio mode; when
   `settings.json.previous` is written and overwritten, and whether a
   command that only reads rewrites the settings file. The glossary
   gains "auto mode" and "looks like".
3. Done 2026-11-14: the end-to-end test design is agreed (D37). Two
   of its experiments have run: a virtual display is captured on the
   owner's Mac, and a new stream on a virtual display that came back
   delivers the other display's picture, which the recorder design
   must deal with.
4. Briefs the recorder PR (queued item 2) with the first end-to-end
   tests.

## In flight

- **Open from PR #1** (merged 2026-11-14), checked on the owner's Mac
  with the snapshot release the owner named: "So I'm checking the PR1
  release snapshot from GH 43ec12f".
  - Seen: "looks good with regard to dynamic updates of the tables
    when I change screen or mic."
  - The second crash came back: "I was able to provoke another crash
    when I opened the resolution drop down and switched HiDPI mode.
    The table did update and then it crashed". `EXC_CRASH (SIGABRT)`,
    an exception in `-[NSWindow(NSDisplayCycle) _postWindowNeedsLayout]`
    from `-[NSWindow(NSConstraintBasedLayoutInternal) layoutIfNeeded]`,
    during menu tracking. D36 point 3 (the window sized by its
    content's preferred size, the check's result held while a menu is
    open) did not stop it. That the table changed with the menu open
    speaks against the assumption that menu tracking leaves the main
    run loop's default mode, or the change came from the display
    itself; which part of the table changed is not known. The other
    order (switch HiDPI, then click a popup menu at once) was not
    reported.
  - Still to report: the first crash's re-test (unplug the default
    microphone with the window open, wait, "Check again", plug it in
    again); whether both permissions were kept when the snapshot was
    installed over the earlier one (D5); a settings file written by an
    early snapshot, with the key `readyCheckHours`, is refused until
    "Reset to defaults"; `msr version` through a symbolic link; whether coming
    back to the app with screen recording denied makes macOS prompt
    again; whether macOS 26 re-asks for the screen recording
    permission after some weeks; whether the tables stay unchanged
    while the folder chooser is open or a control is dragged, and
    change when it closes (the same holding as for menus, which
    failed).
  - Each crash gets its entry in `docs/troubleshooting.md` once its fix
    is verified.
  - The merged branches `v0-skeleton-and-pipeline`,
    `end-to-end-tests-design`, `bring-end-to-end-design-to-main` and
    `copilot-review-fixes` are still on the remote; deleting them is
    the owner's (the "Delete branch" button on each merged PR).

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
   per channel (D22), SDR with the colour space tagged (D24). The
   system audio stream needs a display to
   attach to and must move when that display disappears.
   Its brief must cover what the reviews of PR #1 found for it:
   - This PR also builds auto mode with its setting `auto`, the
     settings file that is read and never refused, and following a
     change of the default microphone (D34). Before any brief, the
     owner signs off the design text for the first two.
     The first end-to-end tests (item 5) are designed with it.
   - The open questions in `docs/design/recorder.md` are answered
     first: the default microphone changing during a recording (ruled:
     the recording follows it, D34), whether Apple's file writer puts a timecode track
     into an audio-only file, clock drift between an audio device and
     the tick grid, two audio inputs with the same name, device names a
     file name cannot hold, the gain of the "Microphones" guide mix.
   - A display needs a stable identity in `DisplayInfo`; the listing has
     none yet.
   - What the end-to-end tests need from the recorder design and what
     research found for it (a macOS fault that delivers another
     display's picture after a reconnect, seen on the owner's Mac; who holds the
     permissions when `msr` is started from a terminal): the sections
     "What the recorder design must provide", "Permissions" and
     "What research found for the recorder" of
     `docs/design/end-to-end-tests.md`, unverified unless marked as
     tried.
   - The app quits when its last window closes; Start closes the
     window, so that must change.
   - Before microphones are captured with an `AVCaptureSession`, an
     experiment shows that unplugging a microphone does not crash the
     process, during capture and after capture sessions that were
     opened and closed (the app crashed in PR #1's ready check, which
     opened one for a moment on every run; D36).
   - The ready check does not run while a recording runs, activation
     included.
   - The ready check probes are free functions: they need a seam for
     tests, and their file access moves off the main thread. With the
     seam, the window's refresh on device changes gets tests (one check
     per burst, nothing applied while a menu is open); it has none yet.
     One check per burst includes the fix of Copilot's finding on a
     refresh that outlives a newer device notice ("Next session starts
     here").
   - From the review of PR #1's crash fixes: `audioInputsToJudge`
     says with a `switch`, not with `try?` and `?? []`, that audio
     inputs that cannot be read do not matter with the audio mode
     `none`, and its comment says what it returns; the unreachable
     `case .gone` in `audioInputs(devices:…)` goes.
   - The recording manifest is written with `Codable`, not with the
     settings file's hand-written JSON writer.
   - A display mode change can arrive as a disconnect and a reconnect;
     short-lived modes need a settle time, or they make many short
     files.
   - Small findings left from the last review of PR #1, to fix with it:
     the manifest has no event for a display that connects, though it
     has one for an audio input; the glossary's "Audio file" does not
     name the channel count change that ends one; `scripts/unpack-app`
     compares member names case-sensitively on a case-insensitive file
     system (nothing leaves the bundle, but its claim about symbolic
     links is then not literally true); an `Info.plist` with a
     malformed date still gives a Python traceback instead of a
     message (it stops either way); `scripts/sign-app` says "the 1
     commits".
3. **Audio after v0** (D12, D18): AGC, in its own PR, with its own
   design, its column in the window's Audio table and the HDMI test.
   What AGC does is open (D34). Recording all audio inputs is no
   longer here: auto mode brings it (D34).
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
5. **Automated end-to-end tests on the owner's Mac** (D34). The
   agreed design (D37) is
   [docs/design/end-to-end-tests.md](docs/design/end-to-end-tests.md):
   tests by error class, what the recorder design must
   provide for them, the experiments that settle its unknowns, and its
   open questions. It is agreed with D35's rulings (D37). Nothing
   of it is built; of the experiments, the first two have run. The
   tests are started by a person, never unasked by an agent.
6. **App icon**, its own PR; until then the app has the default
   icon. The owner chose the drawing (2026-11-12):
   three displays fanned in depth on a graphite tile, one red record
   dot on the front display; graphite `#1E2330`, cool white `#E9EEF7`,
   red `#FF3B30`, the same three colours for the homepage. Flat vector
   master in layers (tile, displays, dot) for the macOS 26 icon format,
   a classic `.icns` if a plain package build cannot compile that
   format, and a small-size drawing with two displays and a larger dot
   below 32 px.
7. **Homepage** (D7): the branch name and how changes reach it
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
- **A table of renamed settings keys**, so that a renamed key keeps
  its value. Deferred because nothing is released yet; an old key is
  dropped and named (D34). Revisit before the first
  change to a settings key after a release `v0.<N>.0` that people use.
- **End-to-end tests in the pipeline or in a virtual machine.**
  Research on 2026-11-13: other projects grant the screen recording
  permission on GitHub's hosted macOS runners by writing into the
  permission database, which breaks with macOS versions; a macOS
  virtual machine (Parallels, Tart) has one display and the host's
  default microphone, so display changes need the same virtual
  displays as on the Mac itself, and Parallels Desktop Business adds
  little here. Deferred because tests on the owner's Mac are "good
  enough for starters". Revisit when those tests exist and running
  them by hand becomes the bottleneck; first step then is a throwaway
  workflow that records ten seconds on a hosted runner.
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

- 2026-11-15: Copilot's review findings on #1 and #2 fixed (PR #4,
  with D38), one deferred to the crash reports PR; agents mark the PRs
  they open ready after Copilot reviews the draft (PR #5, D39).
- 2026-11-14: the skeleton and pipeline PR (#1) merged, with D25–D34
  and D36; the end-to-end test design (PR #2, with D35) agreed (D37)
  and brought to `main` with PR #3.
- 2026-11-13: the owner's rulings on auto mode, the settings file, the
  default microphone and end-to-end tests (D34).
- 2026-11-12: v0 design agreed (D17–D24); it settled the former queued
  items "v0 design", "build and release pipeline" and "test strategy".
- 2026-11-12: project setup with the starter (D1–D16).
