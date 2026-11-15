# Backlog

## Next session starts here

PR #9 merged 2026-11-15: settings and auto mode, the first of the
recorder's two PRs (D44). Start the next architect session fresh with
the recording core (queued item 2): its design text first, for the
owner's sign-off, from the findings of 2026-11-15 in
`docs/design/end-to-end-tests.md` (the docs PR "Record the virtual
display and audio drift experiments" brings them; merge it first).

How the owner wants changes that show in the window or on the command
line handled (2026-11-15: "what about working locally and letting me
test first to speed up?"): as soon as the builder's tests pass, the
owner gets the local build (`scripts/build-app` in the builder's
clone) to try, while the review runs alongside; the owner's feedback
and the review findings go into the same fix commit. Not yet written
into the architect skill.

Still open from D34: what AGC does and whether it is on in auto mode;
"AGC can also come as an improvement after the recorder" (the owner,
2026-11-15).

## In flight

- **Docs PR "Record the virtual display and audio drift experiments"**
  (branch `experiment-findings`): the experiments of 2026-11-15 in
  `docs/design/end-to-end-tests.md`; review, then the owner merges.
- **`swiftpm-testing-helper` crashed twice** on the owner's Mac on
  2026-11-14 (21:53 and 22:08, crash reports in
  `~/Library/Logs/DiagnosticReports`), likely during `scripts/test`
  runs. Not looked at yet; a test run that crashes must fail loudly.

## Queued

1. **Toolchain catch-up** (D28): the pipeline builds with Xcode 26.6,
   Swift 6.3 and Python 3.15, the newest on GitHub's generally
   available runner image (D32 for Python), while the owner's Mac has
   Xcode 27.2. Move the pipeline and the Swift tools version up as soon
   as a runner image with Xcode 27 is generally available. The gap
   bit in PR #9: code the local Xcode 27.2 accepted failed to compile
   on CI's Swift 6.3.
2. **Recording core (PR B)** (D18, D44): `msr record`, Start and Stop
   in the app, a display file per display and an audio file per source
   with guide tracks (D31), a new display file when the frame size
   changes (D30), timecode in every file (D21, D31), mono tracks per
   channel (D22), SDR with the colour space tagged (D24), the recording
   following a change of the default microphone (D34), the first
   end-to-end tests (item 5). The system audio stream needs a display
   to attach to and must move when that display disappears. Its design
   text, signed off before any brief, must cover:
   - The findings of 2026-11-15 (`docs/design/end-to-end-tests.md`):
     the wrong-display fault after a reconnect is reproducible with
     virtual displays and survives every restart tried; each frame's
     screen rectangle detects it, a screenshot of the display's area
     still shows the right picture; a display's stable identity is
     macOS's display UUID (the serial can be 0); a mode change is not a
     reconnect and a stream configured to the looks-like size keeps
     running, scaled; the frames are tagged BT.709 in 420v; a process
     without the AppKit event loop is never told of display changes;
     two of the owner's four microphones drift 50 and 117 parts per
     million against the host clock, and macOS does not correct it.
   - The open questions in `docs/design/recorder.md`: whether Apple's
     file writer puts a timecode track into an audio-only file, clock
     drift (above), two audio inputs with the same name, device names a
     file name cannot hold, the gain of the "Microphones" guide mix.
   - What the end-to-end tests need from the recorder design ("What the
     recorder design must provide" in `docs/design/end-to-end-tests.md`).
   - The app quits when its last window closes; Start closes the
     window, so that must change.
   - Before microphones are captured with an `AVCaptureSession`, an
     experiment shows that unplugging a microphone does not crash the
     process (D36); it needs the owner at the Mac.
   - Whether the wrong-display fault shows with the Mac's own displays;
     it needs the owner to unplug and replug one.
   - The ready check does not run while a recording runs, activation
     included.
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
   design, its column in the window's table and the HDMI test.
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
6. **App icon, what is left** after PR #7 (classic `.icns` rendered
   from `assets/icon/app-icon.svg`): the macOS 26 layered icon format
   from the SVG's layers, if a plain package build can compile it; a
   simplified drawing below 32 px (two displays and a larger dot), from
   the owner's choice of 2026-11-12. Revisit when the owner finds the
   Dock or Finder icon lacking.
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
  change to a settings key after a release `v0.<YYYYMMDD>.<N>` that people use.
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
  - The owner's angle, 2026-11-15: "why won't it help to run them in a
    VM end-end where you can also deal with the approvals via remote
    control? you'd still use the virtual screens etc. to test the
    recorder, but control it from the outside end-end." Kept deferred
    on the same day ("Keep deferred").
  - The architect's assessment, given in the session: a VM on the
    owner's Mac, as a second tier beside the Mac, not instead of it.
    It would leave the Mac usable during a run, start each run from a
    copy of an image with the permissions granted, and, with the
    host's mouse and keyboard reaching the guest as hardware input
    [ASSUMED], make testable what the design leaves out: the
    permission prompts of a first start, a permission taken away
    during a recording, the monthly "continue to allow" prompt, and a
    locked screen (unlocked with the VM's own password). It cannot
    replace the Mac for the encoder and timing: the guest is reported
    to have no hardware HEVC encoder, which the recorder uses (D21).
  - First step on revival: a test of about an hour on the owner's Mac
    (downloads a macOS image of tens of GB; Tart's licence terms to
    check, or UTM) answering three questions: does a `CGVirtualDisplay`
    display appear in a macOS 26 guest and can ScreenCaptureKit
    capture it; does the guest list a hardware HEVC encoder; does a
    click sent from the host press "Allow" on the Screen Recording
    prompt.
  - Not decided, the architect's recommendation: let the end-to-end
    driver run the recorder through a remote command from the start,
    with running it locally as a special case, so a VM tier costs
    little later. That changes the signed-off design (D37), so it
    needs the owner's sign-off as text.
  - Revive also when the Mac being unusable during runs, or the
    permission and locked-screen cases left untested, become the
    bottleneck.
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

- 2026-11-15: PR #9 merged by the owner: settings and auto mode
  (D44): Native is the looks-like size, four audio modes, a Mac without
  a microphone records, one table of what will be recorded, the
  settings file only read and written by the window and `msr settings`
  with flags. The owner tried local builds during the review.
  The owner confirmed the icon of `v0.20261115.12` and considers PR
  #1's open re-checks done through the snapshot releases.
- 2026-11-15: PR #7 (app icon rendered from the vector drawing, the
  owner's Gemini artwork in `assets/icon/`) and PR #8 (versions
  `0.<YYYYMMDD>.<N>`, D42; Copilot an optional extra, D43) merged by
  the owner; branches deleted.
- 2026-11-15: PR #6 merged by the owner: crash reports through GitHub
  (D40) and the HiDPI crash fixed by removing the start window's popup
  menus (D41); checked by the owner ("I couldn't provoke the crash").
  The branch is deleted.
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
