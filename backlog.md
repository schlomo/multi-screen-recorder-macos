# Backlog

## Next session starts here

PR #11 (B1, the displays) merged 2026-11-15. B2 is next and carries
B1's follow-ups (the owner: "B2 PR needs to carry what was missed here
together with the audio stuff"). The owner asked agents to run tests
on the Mac themselves (D48, recorded with B2). After B2: the first
slice of the end-to-end tests, which lets agents test display changes
without the owner (virtual displays).

How the owner wants changes that show in the window or on the command
line handled (2026-11-15: "what about working locally and letting me
test first to speed up?"): as soon as the builder's tests pass, the
owner gets the local build or snapshot release to try, while the
review runs alongside; the owner's feedback and the review findings go
into the same fix round. Not yet written into the architect skill.

Still open from D34: what AGC does and whether it is on in auto mode;
"AGC can also come as an improvement after the recorder" (the owner,
2026-11-15).

## In flight

- **Recording core B2, the audio, with B1's follow-ups** (branch
  `recording-core-audio`): phase 1 built (new files only, unreviewed:
  the audio file writer, the proof that an audio-only file carries
  timecode, gaps, drift measure, the "Microphones" mix, names); phase 2
  wires it in. See queued item 2.

## Queued

1. **Toolchain catch-up** (D28): the pipeline builds with Xcode 26.6,
   Swift 6.3 and Python 3.15, the newest on GitHub's generally
   available runner image (D32 for Python), while the owner's Mac has
   Xcode 27.2. Move the pipeline and the Swift tools version up as soon
   as a runner image with Xcode 27 is generally available. The gap
   bit in PR #9: code the local Xcode 27.2 accepted failed to compile
   on CI's Swift 6.3.
2. **Recording core B2, the audio, and B1's follow-ups** (D45, D46,
   D47; the design signed off 2026-11-15 in the session, to be written
   into `docs/design/recorder.md` with its decisions entry):
   - Audio: an audio file per recorded audio source, one mono track per
     channel, system audio one stereo track from a small ScreenCaptureKit
     stream on the main display, guide tracks "Microphones" (sum / √n,
     clamped) and "System audio" in every display file, the default
     microphone followed, placement by sample count from a tick, drift
     measured as `clockDriftPpm` per audio file (corrected in a later
     PR), a gap detected above 32 ms and filled up to 1 s, a new file
     beyond (D46 point 7), names with `/` and `:` as `-` and " (2)" for
     a duplicate, the reel name and metadata as for display files.
   - Settled by experiment on 2026-11-15: `AVAssetWriter` writes
     timecode into an audio-only fragmented `.mov`; unplugging a
     microphone recorded by an `AVCaptureSession` does not crash (D36):
     the session stops with -11808, and a replug needs a new session.
   - B1's follow-ups: a second lost capture source without a display
     change is a failure (the review's N-A); the "manifest could not
     be written" alert only after the person's Stop; the display's name
     on the video track itself; CPU of our process in the status
     window, the summary and the manifest (the owner, 2026-11-15),
     naming that encoding and capture run in macOS's own processes;
     `SliderSteps.swift:9` converts without a guard (side finding of
     2026-11-15).
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
     microphone's audio file to a separate recording. Seen on
     2026-11-15 for display files: Resolve and Kdenlive place them by
     timecode; Resolve shows the reel name with Project Settings,
     Conform Options, "Embedding in source clip file", and Camera #
     from `com.apple.proapps.cameraName` without it.
   - A recording through a daylight-saving change keeps one timeline
     (the owner's idea, 2026-11-15).
   - Other players: the files open in QuickTime Player and, checked
     once by the owner, in Kdenlive; how Kdenlive places the files
     decides whether the joining command below is needed.
   - A snapshot release installed over an earlier one keeps both
     permissions, with the app started from Finder (D5).
5. **Automated end-to-end tests on the owner's Mac** (D34), their
   first slice its own PR after B1, testing the display events (the
   architect's sequencing, 2026-11-15; before D45 they were part of the
   recorder PR). The
   agreed design (D37) is
   [docs/design/end-to-end-tests.md](docs/design/end-to-end-tests.md):
   tests by error class, what the recorder design must
   provide for them, the experiments that settle its unknowns, and its
   open questions. It is agreed with D35's rulings (D37). Nothing
   of it is built; of its experiments, those on virtual displays and
   the audio drift have run (2026-11-13, 2026-11-15); the audio ones
   (aggregate device, BlackHole drivers, a tone in system audio),
   BetterDisplay's command line and the clock have not. Agents may now
   run them on the owner's Mac (D48, with B2).
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
- **Screenshots as a fallback for the wrong-display fault**
  (`SCScreenshotManager`, right in 3 of 3 faulty runs). Deferred
  because it is a second capture path of unknown cost at 30 fps, and
  the fault has been seen only with virtual displays (D45). Revisit
  when a recording shows the event `display shows another display's
  picture` in real use, or the owner's unplug test shows the fault with
  real displays.
- **Choosing audio inputs one by one with auto mode off** (open in
  D34). Deferred because `all-inputs` covers the end-to-end tests and
  no one has asked (D45's design). Revisit when the owner wants a
  device left out that its audio mode records.
- **macOS 27 as the minimum.** The owner offered it on 2026-11-15;
  nothing found depends on it and the pipeline cannot build for it
  (D45). Revisit when a runner image with Xcode 27 is generally
  available (queued item 1), or if macOS 27 is shown to fix the
  wrong-display fault.
- **Frame rates other than 30 fps** (60, or 100 and more). The owner,
  2026-11-15: "maybe somebody would like to record at 60 or 100 fps, so
  we shouldn't make it too hard to change that." Kept open in B1: the
  frame rate is one named value that the tick grid, timecode and
  encoder derive from, with a test at a second rate; there is no
  setting. Deferred because D11 and D21 fix 30 fps. A screen shows no
  more frames than its refresh rate (60 Hz for most external displays,
  up to 120 Hz for ProMotion), and editors' timecode support above
  60 fps is unknown. Revisit when someone asks; it then needs its own
  design (setting, disk estimate, timecode above 60 fps, encoder load).
- **A short test recording that measures the system load**, like OBS's
  auto-configuration. The owner, 2026-11-15: "We could also do a 5 sec
  test recording at full quality without writing the files (or with
  writing to a temp folder we trash) to "measure" the system load and
  to show it to the user". The design stays open for it: `msr record`
  with `--duration` and `--output-folder` already makes such a
  recording, and the manifest's `framesRepeatedForLateness` shows
  whether the encoder kept up. Deferred because the v1 gate's one-hour
  measurement first shows whether load is a problem at all. Revisit
  when that measurement or a user shows recordings falling behind.

- **A recording across midnight.** The timecode starts over at
  `00:00:00:00`, so an editor places a file started after midnight
  before the earlier ones. Deferred because recordings across midnight
  are rare. Revisit when one is needed; options then are a timecode
  continuing past 24 h where editors accept it, or the manifest's
  offsets.
- **An `msr log` command** that runs the `log show` command for the
  person. Deferred because the command is in the crash report form and
  the README (D46). Revisit when people struggle with it.

## Done (recent)

- 2026-11-15: PR #11 merged by the owner: B1, the displays (D45, D46,
  D47). The owner's runs: reconnects, frame size changes, the lid,
  Ctrl-C and the status window from `msr record`; Resolve and Kdenlive
  align the display files by timecode. The test crashes of 2026-11-14
  were the first failing run of a test-first change and need no fix;
  a crashing test fails `scripts/test` (checked 2026-11-15).

- 2026-11-15: PR #10 merged by the owner: the virtual display and
  audio drift experiments. The owner signed off the recording core's
  display half (B1) and split the core in two PRs (D45).
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
