# Backlog

## Next session starts here

Two PRs are in flight (2026-11-19), see "In flight". First the
diagnostics PR (item 24) gets its adversarial review, the pipeline and
the owner's merge. Then PR #23 (item 3's first part) takes `main` in,
and its end-to-end job is rerun on one commit until it passes 5 times
in a row (the owner: "keep working till you see consistently reliable
e2e tests"); every failure is root-caused from the uploaded artifacts,
never retried away, and no check is loosened. The 4th attempt on
`298e4c9` failed on a real `screen file writer failed` at a mode
switch, whose cause item 24 makes visible. Then, one PR each: item
23, the Resolve timeline (after the owner's test import of the spike
`.otio` files, instructions in the session of 2026-11-19, remade if
gone); item 21, the meters (design signed off); item 3's follow-up;
item 4; item 7; item 12; item 22; the rest of item 6; item 16.

Agents may run `msr record` on the owner's Mac (D48), and BetterDisplay's command
line with the owner's virtual screen "Virtual 16:9"; by D56, before
an agent starts a recording or plays a sound on the owner's Mac, the
session running or briefing that test tells the owner, once before
the test's first run. The `resolve` MCP server failed to start in the
session of 2026-11-19 (its command path is cut at the first space);
the owner fixes it.

Still open from D34: what AGC does and whether it is on in auto mode;
"AGC can also come as an improvement after the recorder" (the owner,
2026-11-15).

## In flight

- **PR #23, end-to-end tests** (item 3, first part; branch
  `end-to-end-tests`, draft): six scenarios on the owner's Mac and on
  the hosted runner, review artifacts, a job summary and annotations.
  Reviewed in full, every round delta-reviewed. Waits for item 24, then
  5 green end-to-end runs in a row. Left for the follow-up: match a
  screen's notice by its name, not its order, and say "misordered"
  where "missing" is printed today (review NITs, 2026-11-19).
- **Item 24, diagnostics** (branch `diagnostics`, being built).

## Queued

2. **Toolchain catch-up** (D28): the pipeline builds with Xcode 26.6,
   Swift 6.3 and Python 3.15, the newest on GitHub's generally
   available runner image (D32 for Python), while the owner's Mac has
   Xcode 27.2. Move the pipeline and the Swift tools version up as soon
   as a runner image with Xcode 27 is generally available. The gap
   bit in PR #9: code the local Xcode 27.2 accepted failed to compile
   on CI's Swift 6.3.
3. **End-to-end tests in CI and on the owner's Mac** (the owner signed
   off the design as text on 2026-11-16: "Yes to both CI questions and
   plan for that"; its decisions entry, replacing D37's "out of the
   pipeline", comes with the PR). An experiment on 2026-11-16 (three
   runs on GitHub's hosted `macos-26` arm64 runner, image 20261102,
   macOS 26.7.2) showed: the image grants Screen Recording and
   Microphone, `msr check` passes, app windows are drawn on the main
   display and on a `CGVirtualDisplay`, hardware HEVC is there, a
   virtual display connected and disconnected during a recording gives
   the right files and events, BlackHole installed with brew carries a
   1 kHz tone into its file, and system audio is recorded.
   - Design: a test driver in Swift, separate from the app
     (`CGVirtualDisplay`, a private API, only there), run by
     `scripts/end-to-end-test`; a CI job after build and tests, no
     secrets, BlackHole and `ffmpeg` installed at fixed versions
     (downloads in CI are fine, the owner, 2026-11-16).
   - Scenarios: a plain recording; a virtual display connected,
     disconnected and resized; an audio input appearing and vanishing
     (an aggregate device on BlackHole); a tone checked for level and
     timing across files by timecode; system audio; stop by Ctrl-C and
     by kill; broken settings files; a full disk (a small disk image)
     and an unwritable folder. Checks: `recording.json` exactly, every
     file readable, frame counts, timecode, levels.
   - On the owner's Mac (D37, D48), what needs real hardware: the
     owner's displays through BetterDisplay, real USB devices, drift,
     sleep and wake.
   - To look into there: one of four 10 s recordings on the runner had
     nothing for 4 s, then gaps and "display file writer fell behind"
     (`result: problems`); the other three were clean.
   - Correct with it: `AGENTS.md` "Facts that bite" and `recorder.md`
     "Tests" still say capture cannot run in CI.
   - Not covered anywhere: real USB re-enumeration, the lid, Bluetooth,
     power loss. A VM on the owner's Mac (Tart, not Parallels) only if
     needed later; it has no hardware encoder.
   - Artifacts for review (the owner, 2026-11-16: "the PR preview
     builds could actually create some outputs as artifacts to look at,
     e.g. screenshots or videos"; then "CI screenshots are optimization
     and part of end-end tests in CI"): each PR run uploads offscreen
     renders of the start and status windows, drawn from made-up
     devices by a script CI only wires, and a few seconds of the files
     the end-to-end run recorded. The same script can then regenerate
     the homepage screenshot as a derived file. Rendering in a real,
     invisible window instead of `ImageRenderer` should draw the app
     icon and the links [ASSUMED].
4. **Simplification** (the Fable review of 2026-11-15; the owner: yes
   to all four questions, 2026-11-16): `unpack-app` uses the standard
   library's `filter="data"`; the run-loop hold goes; `recording.json`
   leaves out null keys; `end-to-end-tests.md` stays. Findings: one
   display reader (`ConnectedDisplay` with a `pixelSize`, one
   `leftToRight`); settings flags validated once; quit handling in
   `RecordingSession`; no double end path (`stop()` returns nil when
   already finishing); `sign-app`'s `version_form` goes; the smoke test
   trimmed; doc-prose and test-the-compiler tests deleted, duplicate
   tests merged; `Recorder` tests through a `DisplayCapture` stand-in;
   missing `DisplayTracker`, `DisplayFileTicker` and `TickLoop` tests;
   the test inventory in `recorder.md` cut to a few lines; the review's
   NITs 12 to 16; finding 17 (`StreamLifecycle`) is the owner's call;
   findings 3 and 6 on audio code now apply. Plus B2's leftover NITs:
   a drain error labelled as a writer timeout in `guideTracksCut`; no
   test for a gap after real data in a guide track's last mix; an
   unlocked test flag in `DisplayFileTickerTests`.
5. **Clock drift correction, what is left** after D57 (PR #19):
   - The Razer's and the BRIO's files are a constant 16 to 18 ms apart
     by room sound (10-minute run, 2026-11-17): each device's own input
     latency, which the recorder has never compensated [ASSUMED].
     Decide whether to read Core Audio's latency per device and place
     each file by it. Design first.
   - The BRIO's clock drift reads about −115 ppm for its first 70 to
     110 s, then settles near +5 ppm, in every run on the owner's Mac
     (2026-11-17). By room sound the Razer-to-BRIO lag held within
     0.3 ms from 30 s to 330 s in the hour run, so the BRIO's clock
     really runs slow while it warms up and the correction follows it
     [ASSUMED, one cross-correlation]. Nothing to change unless a
     tester's BRIO shows otherwise.
   - The owner's runs with `--debug` answer two assumptions: whether a
     source's timestamps keep following its sample count across a gap
     (a debug line at each gap shows it), and whether the rate's swing
     on the system audio (within ±67 ppm on the measured arrivals) is
     inaudible.
6. **CPU**: our process averaged 56 % of one core over an hour (two
   displays, five audio sources) and peaks at 165 to 386 % at start.
   A 20 s `sample` of 2026-11-16 (build `7ad0b6b`; shares solid,
   absolute values maybe 1.2 to 1.5 times high from `sample` itself):
   11 AAC encoders 22 % (guide tracks about 5.8 % per display, more
   than the video's own cost), movie writers 6 %, microphone capture
   7 %, VideoToolbox 5 % (3 % of it rebuilding a colour space from the
   frame's ICC profile, twice per frame), our own code 1.6 %. Without
   design changes: interleave stereo in `pcmSample` without per-sample
   arrays (about 3 %, `MovieTracks.swift:134`); small Swift fixes
   (about 1 %); set the stream's colour space to drop the ICC work (up
   to 3 %, colours checked by pixels, D24). Needing a decision: guide
   tracks encoded once for all display files (about 4 %), at 24 kHz
   (about 4 %) or with a mono system-audio guide (about 3 %); audio
   appended in 100 ms pieces (1 to 3 %, 0.1 s more at risk in a
   crash); uncompressed audio in the audio files (no encoder cost,
   about 0.5 GB per hour per mono channel) [ASSUMED]. A better profile:
   `sample <pid> 120 10`, runs with parts switched off, and the start-up
   peak sampled from launch. Scripts and outputs were in the session
   scratchpad. Measured steady CPU (after 30 s, 3-minute runs, two
   displays, 2026-11-16): video only 11.5 % (11.9 % at 1080p, so the
   resolution costs nothing); with system audio 25.9 % (+14.4 %); plus
   the default microphone 35.0 % (+9.1 %); wired, four inputs and six
   channels, 54.9 %; all inputs 62.0 %. Audio costs about four times
   the video, and far more per channel than an AAC encoder alone
   (0.17 % per mono stream benchmarked): per-buffer appends of 512
   samples are the suspect. The owner (2026-11-16): a cheaper encoder
   setting is welcome if files grow only 10 to 20 % "without quality
   loss", and redundant work goes "where obviously not needed"; the
   optimisations come later, research first.
   Encoder benchmark (2026-11-16, a replica of the audio path with the
   recorder's own code, real-time paced, M3 Pro; relative numbers): the
   encoder is not the main cost, the 94 appends a second are. Batching
   the audio files' appends to about 100 ms (as the guides already do)
   gives bit-identical files and saves about 1.9 % of a core per input
   (microphone path 6.4 % → 3.8 %). Today: AAC-LC, 48 kHz, quality
   medium (the default), 128k per mono track, 192k system audio, guides
   64k and 96k. AAC quality "min" at 160k: +19 % size, SNR −1.4 dB,
   about −0.5 % per track (the owner's "cheaper encoder" compromise; a
   listening test decides). Opus writes into `.mov` and Resolve
   imports and plays it with its timecode (the owner, 2026-11-16), but
   it costs more CPU than AAC; ALAC and PCM are 5 to 11 times the size; the bit-rate
   strategy changes nothing. A silent (all-zero) input still costs
   about 3 % in the writer. One mono input's live 9.1 %: about 2.7 %
   capture session (by subtraction), 2.1 % writer appends, 1.7 % its
   guides in two display files, 1.3 % encoder, 1.1 % our queue, split
   and mix. Scripts were in the session scratchpad.
   The owner's first step (2026-11-16): "batching and doing away with
   redundant work will be a good 1st step, without adding extra
   complexity": the audio files' appends batched to about 100 ms, the
   stereo interleave without per-sample arrays, no zeros written (item
   11), and the colour-space work dropped if the pixels stay identical.
   Not in the first step: a cheaper AAC setting, shared guide tracks,
   24 kHz guides. The design docs get these findings with that PR.
   A tester's MacBook Air (2026-11-18; two displays, system audio, a
   mono and a stereo input, 15 minutes): 41.7 % average, 137.5 %
   peak, no frame repeated for lateness. A MacBook Air has no fan, so
   a long recording falls behind there first if anywhere [ASSUMED].
   The first step shipped in PR #21 (2026-11-19): appends of about
   100 ms and the stereo interleave in place; auto mode on the owner's
   Mac went from about 43 % to about 32 % of one core (steady, from
   30 s on, 3-minute runs, two screens, system audio, three inputs).
   The colour space was left unchanged: set to BT.709 it made the
   picture about 6 of 255 levels lighter, so the pixels did not stay
   identical. Not writing zeros moved to item 21 (the owner,
   2026-11-18). A 30-minute run with the PR's build (2026-11-18, two
   screens, system audio, four inputs, a radio in the room, the Razer
   unplugged and replugged): `result: ok`, every file finalized, CPU
   40 % on average and 186 % at the peak.
7. **Auto-recovery from disturbances** (the owner, 2026-11-16: "if
   after a few seconds the recording is again good then I'd accept
   that. Main goal is auto-recovery after changes and continuing the
   recording instead of giving up"). The analyst's report of
   2026-11-16 on the owner's runs `12.24.51`, `12.41.06`, `12.50.45`:
   - Cause: plugging the Wacom's USB side into the CalDigit TS3 Plus's
     downstream USB-C port exhausts PCI address space, and macOS pauses
     every PCIe function of the dock for about 4 s ("pci pause", the
     dock's Ethernet last). Every USB audio device hangs off that
     dock; the MacBook microphone does not. Unplugging is harmless.
   - What the recorder gets: exact zeros, or a 250 ms loop of old
     audio (BRIO, Razer), delivered late in one burst (CMIO "Overload
     prepending silence"). Gap detection sees none of it; the guide
     tracks carry the loops into the display files; the disturbed
     stretches corrupt `clockDriftPpm` (BRIO 184.8, system audio
     -964.3 ppm).
   - The BRIO wedges after a pause: usbaudiod restarts it 12 times,
     then gives up; only a replug helps, an app cannot reset it.
   - The DELL's lost seconds (`12.24.51`): the hardware encoder did not
     stall (983 frames in, 0 dropped); the writer's video input stopped
     accepting frames for more than 2 s while macOS reconfigured. On
     "fell behind" the held frames are discarded, then finalizing, the
     1 s back-off and a new stream add 3 to 5 s.
   - A display's stream starts up to 5.6 s late: the screen-recording
     permission check before each stream (tccd checking the terminal's
     code signature), and msr held up during the pause.
   - Designs, ranked by recording saved against cost: (a) the 6 s
     allowance (item 1); (b) a new display file on the same stream
     when a writer falls behind, carrying the held frames, no back-off;
     (c) audio honesty: one event per episode (zeros, repeated audio,
     late burst, input dead), never write repeated audio, a dead input
     becomes a problem that says to replug it, one indicator per input
     in the status window (together with item 11); (d) fetch the
     shareable content ahead, off the Core Audio path; (e) a ready-check
     warning when audio inputs share a dock with a USB-C display;
     (f) leave disturbed stretches out of the drift measurement
     (done with D57 for a short one, which lies above the line; a
     late stretch of 7 s or more still tilts it, see recorder.md,
     "Clock drift"); (g) our own process tap for system audio, low: it is the
     mechanism ScreenCaptureKit already uses. Design first.
   - Advice for the owner [ASSUMED, from the mechanism]: the Wacom
     straight into a Mac port avoids the pause; check with one replug
     and `log show` for "pci pause".
   - The owner, 2026-11-16: in `12.41.06` and `12.50.45` nothing played
     through the Mac (the radio was in the room), so their system-audio
     zeros are right; the dock's Ethernet is in use, so it cannot be
     switched off to shorten the pause.
   - The Wacom on a Mac port (`msr record --debug`, `13.21.55`,
     2026-11-16): no PCI pause, no zeros or loops in any USB input, the
     BRIO stayed alive; the Pebble broke once (system audio 1.8 s of
     zeros at +124.8). Plugged back into the dock after the run: a
     4.1 s PCI pause (Ethernet last) and the BRIO dead again. So the
     cabling advice holds. But the DELL's writer still fell behind
     (video ends +123.7, new file +128.1, 4.4 s lost) while the Wacom
     came up on the Mac port: WindowServer logged "failed to send rlfg
     reply" 0.7 s before the DELL's frames stopped, and msr's own
     logging went nearly quiet. So the DELL loss comes from macOS
     reconfiguring the displays, not from USB: designs (a) and (b)
     are what saves it. The Wacom on another port is a new display
     to macOS (another UUID), so the recording named it Display 3;
     the same screen on another port getting a new number is
     expected but may puzzle people. The run also reproduced
     `result: problems` with `problems: []` (item 1). Open:
     app-against-CLI
     repeat runs with `--debug` to settle whether the app's front end
     adds to the stall (msr logged "skipping cycle due to overload" only
     in the app run).
   Found in PR #21's review (2026-11-18), older than it: after a wake
   with screens that cannot be read, the recorder returns before the
   audio's wake, so the system audio does not come back, at every
   resolution (`Recorder.swift`, `didWake`).
8. **Audio after v0** (D12, D18): AGC, in its own PR, with its own
   design, its column in the window's table and the HDMI test.
   What AGC does is open (D34). Recording all audio inputs is no
   longer here: auto mode brings it (D34).
9. **v1 gate:** acceptance tests on the owner's Mac (M3 Pro, macOS 26):
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
10. **Audio files in editors**: Resolve shows the audio files' timecode
   but no reel name or camera number (the owner, 2026-11-16), though
   they carry the same items as the display files; the owner wants
   "meaningful metadata for resolve and others". Research found no
   documented route for audio-only clips; Final Cut Pro reads iXML
   `TAPE` from WAV. The owner's check in Resolve (2026-11-16) of the
   test variants: QuickTime user data and XMP in an audio-only `.mov`
   show nothing; a `.mov` with a video track shows the timecode
   track's name as Reel Name; a Broadcast WAV shows its BEXT
   originator as Camera #; all keep their timecode. Not checked yet: a
   Resolve metadata CSV imported per recording. The variants were made
   by throwaway scripts in a session scratchpad, so remake them if
   gone. Candidates: a WAV copy derived at Stop, or the CSV; the
   recording itself stays a fragmented `.mov`. Design first.
11. **An input that delivers only zeros** (from the live runs,
   2026-11-16): a broken BRIO and, during USB re-enumeration, every USB
   input and the system-audio capture delivered exact zeros for 4 to
   10 s, with no event (macOS's doing; the speakers kept playing). Tell
   it as an event and a problem when an input delivers exact zeros for
   2 s or more (system audio excluded, silence is normal there).
   The owner (2026-11-16): "We don't need to record zeros, MacBook
   internal mic is off on lid closed. Hardware muted mic would probably
   be the same, we can test that with my razer". So such an input is
   not written while it delivers only zeros (and is told), which also
   covers the closed lid. Tested 2026-11-16: the Razer's hardware mute
   delivers exact zeros, the same case. The status window shows per
   input whether sound arrives, a level meter if cheap (the owner,
   2026-11-16: "doesn't need to be a meter (would be nice though), but
   some visual indicator"). A device that delivers broken audio sends a
   storm of gap events (the BRIO, 28 in 5 s, 2026-11-16): tell one
   event per episode. Design first.
12. **Cameras** (the owner, 2026-11-16: "we'll have to add a feature to
   record cameras, same slider: none, default, all, all + virtual. Auto
   defaults to default camera if available"; 2026-11-18: keep "all +
   virtual"). A camera's file carries
   audio too ("Later for webcam we'll have more combined files as we of
   course want have audio there as well", 2026-11-16). Design first.
   Each camera records its largest format that still delivers the
   wanted frame rate (the owner, 2026-11-18); the architect proposes
   that the recording resolution caps cameras as it caps screens (a
   4K camera often delivers MJPEG, a decode on top of the encode).
   The owner (2026-11-18): a camera's file carries the camera's own
   microphone when it has one ("sync problem might be there"), and
   where a camera offers an H.264 stream, the recorder takes it as-is
   rather than decoding and encoding again. Open for the design: the
   audio of a camera without a microphone; whether AVFoundation hands
   out a camera's H.264 stream undecoded at all [ASSUMED: it usually
   delivers decoded frames]; and how a stream taken as-is fits D11's
   constant 30 fps on the host clock (no frame repeated or dropped
   without encoding again) and the resolution cap. Camera capture is
   out of scope in D1, so this needs a decisions entry that supersedes
   that line. A test device: a tester's Logitech BCC950 ConferenceCam
   (a camera with a stereo microphone, recorded as an audio input on
   2026-11-18); whether it offers H.264 is unchecked.
13. **Presentation: the window and the terminal output** (the owner,
   2026-11-16: "if running in a terminal (try) then show the running
   status as persistent last line, recording time, CPU, recording size
   etc."). Signed off on 2026-11-16, with the owner's additions ("a
   --quiet option to suppress all regular output", "make sure that
   stdout and error are handled properly for managed or scripted
   operation", "a brief banner with version info, build date and
   homepage link"):
   - Built for `msr record` on the branch under "In flight" (D58):
     the status line, the split and `--quiet`. Left: the other
     commands and the window, below.
   - Only when standard error is a terminal: one line, redrawn every
     second: recording time with seconds, CPU of our process, the
     recording folder's size, free space, sources, problems. An event
     or debug line clears it, prints, redraws it; it goes at the end
     and the summary follows. No option for it.
   - Today all human output goes to standard output (seen 2026-11-16).
     The split, the owner's yes on 2026-11-16 ("yes, good plan for
     the terminal output"): standard output carries only data a script uses (the
     recording folder's path, one line, when recording starts);
     everything for people (the banner, the table, the ready check,
     events, the status line, the summary, debug) goes to standard
     error; `recording.json` stays the machine-readable result.
   - `--quiet`: no output for people; errors still go to standard
     error; exit codes unchanged.
   - Banner in normal mode: version, build date, a link (the GitHub
     repository until the homepage, D7, is live).
   - Check the other commands (`check`, `list`, `settings`, `version`)
     against the same split.
   - The window, with the owner's feedback of 2026-11-16 on `12f846a`:
     the app icon, the version and a link (as the banner); a Cancel
     button in the lower right corner; the table as a real table, the
     total in the GB/h column; the output folder a clickable link. The
     status window shows sizes below 1 GB in MB (it showed 0.0 GB for
     everything after 1.5 minutes). The GB/h estimate is about twice
     what one hour wrote (4.0 GB/h estimated, 1.7 GB in the hour run):
     calibrate it with the v1 gate's hour run.
14. **App icon, what is left** after PR #7 (classic `.icns` rendered
   from `assets/icon/app-icon.svg`): the macOS 26 layered icon format
   from the SVG's layers, if a plain package build can compile it; a
   simplified drawing below 32 px (two displays and a larger dot), from
   the owner's choice of 2026-11-12. Revisit when the owner finds the
   Dock or Finder icon lacking.
15. **Homepage** (D7, D53): live since PR #13. Left: preview URLs on
   PRs: on PR #20 Cloudflare's check passed but linked to a build of
   the production Worker and no preview URL appeared, so preview
   builds for other branches are not set up [ASSUMED from the check's
   link]; that is the owner's, in Cloudflare. The owner's check that
   `schapiro.org/impressum/` covers the subdomain.

16. **Mac App Store and Homebrew** (the owner, 2026-11-16: "I'd like
   to release the app through the Apple Store [...] charge like 5-10€
   via the app store while still offering the free install via
   Homebrew"). The licence stays GPLv3; the owner, as the sole
   rights holder, distributes App Store builds under other terms; the
   contributor clause and the dual-licensing note were to come with
   the command line polish's PR (D54) and did not: PR #19 left them
   out; they wait for the owner's go-ahead on their text. Homebrew
   waited until `scripts/install-app` worked for the owner (the owner,
   2026-11-17: "maybe hold back on the cask and we first solve my local
   problems and then apply this learning"); it does since PR #20: the
   owner's build, signed with their certificate and installed without
   the quarantine, started without a permission prompt. The cask
   applies the same: the stable certificate, the quarantine removed. Order, from the
   architect's assessment of 2026-11-16:
   - A sandbox test on the owner's Mac (about half a day, no cost):
     our build signed with `com.apple.security.app-sandbox`; check
     displays, microphones, system audio, writing to `~/Movies`
     (`assets.movies.read-write`), any other folder (security-scoped
     bookmark), `msr` from a terminal, settings and `state.json` in
     the container, the crash-report reader (blocked in the sandbox).
     Aim: one sandboxed build for every channel (tested = shipped);
     a second build only for what the sandbox cannot carry.
   - The owner joins the Apple Developer Program (€99 a year; revives
     the deferred Developer ID item, D5).
   - Developer ID signing and notarization, a Homebrew tap
     (`schlomo/tap`; Homebrew drops casks that fail Gatekeeper
     [ASSUMED]).
   - The App Store build (Apple Distribution certificate, installer
     certificate, provisioning profile, App Store Connect key, all
     injected), App Review; each submission needs the owner's go-ahead.
   - The owner's, outside the code: the EU trader details shown on the
     App Store (address, phone, email; DSA), tax, and a lawyer's look
     at the contributor clause.

19. **The crash dialog offers only the app's own crashes.** On
   2026-11-17 the owner's freshly installed app showed the crash dialog
   for four `msr-*.ips` reports that a test's stand-in program (a copy
   of `/bin/sleep` named `msr`, killed by macOS at launch) had written;
   the app reads every `msr` report in `~/Library/Logs/DiagnosticReports`.
   The stand-in is now a program of the tests' own that writes no
   report. Left: the app could skip reports whose `procPath` is not
   inside an app bundle named `Multi Screen Recorder.app`, so a
   developer's test runs or a stray `msr` never prompt a report. Needs
   a design (which paths count), signed off by the owner.

20. **A re-run when GitHub has no macOS runner** (the owner,
   2026-11-17: "can we add a retry as failure path into the CI yaml?",
   then "add the idea to the backlog for later"). Twice on 2026-11-17 a
   merge's build was cancelled because GitHub found no Apple-silicon
   runner, and a person re-ran it. The idea: a workflow on
   `workflow_run` of `ci.yml` ending cancelled calls
   `scripts/rerun-without-runner` (Python, tested with a stand-in
   `gh`), which re-runs the failed jobs only when the run's annotations
   say "not acquired by Runner", up to the third attempt; on a Linux
   runner, with `actions: write` for that workflow only and no checkout
   of PR code. Needs the owner's sign-off of the design. The pushed
   branch `troubleshooting-ci-runner` holds two troubleshooting entries
   (no macOS runner; a crash dialog for crash reports the tests wrote):
   they ship with this item.
21. **Audio level meters, with an input gain slider** (the owner,
   2026-11-18, as the first step towards AGC, item 8): each audio
   input's level shown live in the status window, and a slider that
   sets the input's gain. Meters also make an input that delivers only
   zeros visible (item 11). The slider sets the device's own input
   volume in Core Audio, because gain added after capture cannot undo
   clipping; that changes the volume for every app on the Mac, and
   devices without that control show the slider disabled [ASSUMED:
   some USB interfaces and HDMI inputs have none]. Every gain change
   is written to `recording.json`; AGC later moves the same control
   (the owner's "turning up input volume till before it clips", D34).
   Levels come from the 100 ms batches of item 6's first step. With
   the meters, an input is not written while it delivers only exact
   zeros (item 11; the owner, 2026-11-18: "OK to defer the audio zeros
   to the meters feature, good idea"). In the 30-minute run of
   2026-11-18 the MacBook microphone, its lid closed, delivered exact
   zeros for the whole run and still got a file. Design signed off by
   the owner on 2026-11-19 ("Yes to meters design"), as text:
   - Meters: one bar per audio input and the system audio, sample
     peak in dBFS on −60 to 0, a peak hold of 1.5 s, red from −1 dBFS,
     measured per incoming buffer, drawn 10 times a second only while
     the window is open; `msr record` gets them through its window.
   - Input volume (macOS's word; "gain" is taken by the guide mix):
     a slider per input that sets the device's own volume through
     `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, shown
     only where it can be set ("No slider conveys a clear message
     while grey means forbidden", the owner); every change, from the
     slider, a knob or another app, held still for 0.5 s, is the event
     `audio input volume changed` (`from`, `to`, 0 to 1); each audio
     file records `inputVolume` at its start; not reset at Stop.
   - No audio: after 10 s of exact zeros ("10s silence is better as
     trigger", the owner; 2 s would split speech pauses of a noise-gated
     microphone into many files) an input's file ends, the window shows
     `no audio` ("Only zero is bad UI, better say no audio"), and
     `no audio started` and `no audio stopped` go into the manifest;
     a new file starts when sound returns, nothing of it cut; an input
     with no audio from the start gets no file; the system audio is
     excluded; not a problem.
   - No agent sets an input's volume on the owner's Mac (D48); the
     owner checks the slider and a hardware knob by hand.
   Unverified until built: which of the owner's inputs can be set,
   whether lowering the volume prevents clipping, whether a knob fires
   the listener. The analysis is in the session of 2026-11-19.
22. **Lip sync calibration** (the owner, 2026-11-18: measured AV
   offsets between cameras and microphones; fixing them by hand in
   Resolve is "super tedious", so worth automating): a support tool
   shows a signal on the laptop's built-in screen and plays a sound on
   its built-in speakers; the person points each camera at the screen;
   the tool measures every camera's and microphone's offset and the
   recorder corrects for it, for lip sync across all cameras and
   microphones. The built-in screen and speakers are the source (the
   owner), because their own delays are small and known; Bluetooth or
   external ones would add their delay to the measurement. Known for
   the design: lip sync is noticed beyond about +45 ms audio early and
   −125 ms audio late (ITU-R BT.1359); audio shifts by the sample,
   video at 30 fps only by 33 ms frames (D11), so the correction moves
   audio; a webcam's delay may change with its exposure in low light
   [CONJECTURE], so the design says when a stored offset is measured
   again. Needs item 12. Design first. Measured 2026-11-18 (30 minutes,
   a radio in the room): the Razer and the BRIO stay a constant 17 to
   18 ms apart, before and after a replug of the Razer, with no drift.
23. **A Resolve timeline in every recording folder** (the owner,
   2026-11-19: "a timeline where all clips are already loaded and
   aligned by time code … longest clip starting at the beginning as
   track v1, all clips from the same device on the same track, track
   named like device … goal is to make editing in resolve super easy";
   "otio sounds great, go ahead with that"). Signed off: an
   OpenTimelineIO file (`.otio`, open JSON; Resolve 21.1 imports it,
   manual ch. 22 p. 527), named after the recording folder, written at
   Stop from `recording.json` and by `msr timeline <folder>` (also
   for older or unfinished recordings, a file's length read from the
   file when `end` is null); a derived file, rewritten, never edited.
   30 fps, starting at the first file's timecode; V1 the screen whose
   file starts at the beginning and runs longest, then the screens by
   number; one audio track per audio source, `Audio 0 - System` first;
   each track named by its label; each file at its timecode; the
   screen files' guide tracks left off. A spike (made with the
   reference library in a session scratchpad) put a 30 s recording of
   2 screens and 5 audio sources on V1, V2 and A1 to A5 as designed;
   the owner's import into Resolve is still to come and decides: track
   names kept, absolute vs relative paths, multichannel audio files on
   one track, and whether only a screen file's video is placed. Then
   built in Swift without a library, with golden-file tests.
24. **Diagnostics** (the owner, 2026-11-19: "The error handing pr must
   be smarter about collection unknown and unexpected errors in
   general so that future similar situations will give us something
   to analyze. Same with user reports. And think about how to connect
   such error details from GUI runs without terminal, ideally writing
   something into the results folder"; on the design: "Better append.
   Otherwise agree"): one error detail for every error (its whole
   chain of domain, code and underlying errors, in the events, the
   problems with `errorDetail`, and the log), enforced by a test
   against `localizedDescription`; a recording log, `recording.log`,
   in every recording folder, append-only, synced at each event and
   problem, with the detail lines `--debug` printed before (partly
   reverses D46); **Report a problem** in the status window after a
   recording with problems. In flight.
25. **A new screen showing a still picture gets no file until it
   changes** (found by PR #23's runs, 2026-11-19): ScreenCaptureKit
   delivers complete frames only on change, so a newly connected
   screen with a static picture has no file and no event for that
   stretch [CONJECTURE for real Macs]. Settle it with a `--debug`
   run (now the recording log), then decide.
26. **A screen file's guide tracks miss their start** (PR #23's runs,
   2026-11-19): a screen file listens to the guide mix only after its
   first frame passes the screen check (`ScreenCapture.swift`), so its
   guide tracks start 5 to 77 ms in (an edit list), and the design
   says they "cover exactly its own time". The audio files are
   complete. Decide whether it matters for editors.

## Deliberately deferred

- **A warm-up before the end-to-end scenarios** (the owner's idea,
  2026-11-19: "On the VM maybe worth warming up the system first";
  then "keep the warm up in the backlog"): a throwaway recording and
  one virtual screen's connect and mode switch before the scenarios,
  not asserted. Deferred because runs 5 and 6 of PR #23 on the hosted
  runner showed no first-use failure (runs 1 and 2 had a first mode
  switch of 1.7 s and audio gaps around 3 s). Revisit when a failure
  on a first use repeats.

- **`GuideTrackFeedTests.theLastMixWaitsForSamplesThatComeLate`
  delivers its late samples from a task after 150 ms, against a 60 s
  bound** (PR #19, `docs/troubleshooting.md`, "Async tests time out on
  CI while simulation tests run"). Deferred because the feed's wait
  polls every 10 ms and offers no event to deliver on, so the fix is a
  change to the feed itself. Revisit the first time it fails on CI, or
  with any change to the guide track feed: signal on arrival instead
  of polling.

- **A new app name.** With audio only (queued item 1a) "Multi Screen
  Recorder" can be a misnomer; the owner accepts that (2026-11-16):
  "application name stays for now till somebody comes up with a
  really great improvement on the name". Revive when someone proposes
  a name the owner finds really great.
- **Skipping the MacBook microphone while the lid is closed**: Apple
  silicon MacBooks disconnect it in hardware then, so its file holds
  only zeros (seen 2026-11-16). Harmless; revisit with item 11 (an input
  that delivers only zeros) or if the files bother the owner.
- **Developer ID signing and notarization** (D5), revived as part of
  queued item 16 after the optimizations. Deferred because the
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
  available (queued item 2), or if macOS 27 is shown to fix the
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

- 2026-11-19: PR #22 merged by the owner (Markdown only, no release):
  item 17. Rounds are pushed with the skip-ci marker, so they start
  no run; the commit about to be marked ready carries no marker and
  starts the one pipeline run; a PR title or description never holds
  one of GitHub's skip strings, since squash merges take the PR title
  and description (the owner's repository setting, 2026-11-18). The
  setup skill is removed. D61, superseding D56 in part. A first
  design (rounds kept local, pushed once) was signed off and replaced
  the same day after a top-tier review. Reviews: three top-tier
  rounds.
- 2026-11-19: PR #21 merged by the owner: item 1a, audio only (the
  recording resolution None; at None the system audio needs a
  readable main screen, a microphone-only recording reads no screen;
  nothing to record refuses to start), item 6's first step and the
  icon's dark-mode frame. D62. Verified: the tests, the build and
  the smoke test locally and in one pipeline run; live runs at None;
  a 30-minute run with a replug (item 6). Reviews: a top-tier review
  and its full re-review.
- 2026-11-18: item 18, dark mode in the app, closed by the owner
  without a change: a tester's screenshots showed the start and
  status windows in dark mode, readable, the dimmed rows included.
- 2026-11-17: PR #20 merged by the owner, release `v0.20261117.52` (its
  build re-run after GitHub found no runner, again): the homepage's
  collage of the three windows with arrows from Start and Stop, the
  wide layout, the features from README (with "In sync after hours"),
  dark mode, the red download button; `scripts/install-app` with
  `--release` and `--snapshot <n>`; `--help` for the scripts and the
  crash form's log command as a comment (D60). The tests' stand-in
  app no longer writes crash reports (troubleshooting). Unverified until
  someone opens a crash report issue: that GitHub hides the comment.
- 2026-11-17: PR #19 merged by the owner, release `v0.20261117.51`
  (its release job re-run after GitHub found no runner): the clock
  drift correction (D57), `msr record`'s status line, output split and
  `--quiet` (D58), the command line polish and the order of sources
  (D59, was queued item 1). The owner confirmed D57 to D59 and ruled
  that `--quiet` writes no warnings, only errors. One hour on the
  owner's Mac: the Razer and the BRIO kept the same lag by room sound
  where uncorrected they would have drifted 420 ms apart; CPU 37 % of
  one core. CI's one failure was the clock drift test suites starving
  three async tests (`docs/troubleshooting.md`). UNVERIFIED: a gap
  within a stream, a click test through the speakers. Reviews: an
  adversarial review of each change, delta reviews of every fix.

- 2026-11-16: PR #16 merged by the owner: the tester guide's "What to
  test and send" (a one-hour recording, a screenshot of the start
  window, `recording.json` of every recording, a few sentences; not
  the recordings). The owner's idea: the screenshot instead of `msr
  version` and `msr list`, whose permissions are Terminal's. Reviews:
  standard tier (Markdown only), two delta rounds.
- 2026-11-16: PR #15 merged by the owner: the homepage shows the start
  and status windows and fits phones (measured at 320 and 375 px).
  Cloudflare's preview URL worked for the first time (PR #13 had
  none). A Retina screenshot is named `-2x.png`: Cloudflare redirects
  URLs with `@`. Reviews: one top tier, two delta rounds. Leftover:
  the start window screenshot is 1x and looks soft on Retina screens;
  retaking it is the owner's call (`homepage/README.md` says how).
- 2026-11-16: PR #14 merged by the owner: naming and window polish
  (D55): `Screen <n>`, `Audio <n>`, `Audio 0 - System`, the "Audio
  inputs" guide mix, icons in the window table, the tagline in the
  header, windows as wide as their table, the status window keeping
  its width, the banner and header rule in `msr check`; release
  `v0.20261116.43`. Reviews: one top tier, three delta rounds, the
  last NIT commit read by the architect. Leftovers, kept here until
  they land:
  - The owner's check on the real screen of the window widths and the
    banner was asked for before the merge; its result is not recorded
    here.
  - A one-word-per-concept pass: the window's tagline was called "the
    claim" in this backlog, and the process docs use "claim" for a
    stated fact; check the process docs' "claim" and "evidence label"
    against the glossary (item 4's naming pass).
  - `docs/design/recorder.md`, the "Stop" bullet of the status window:
    two lines over 72 characters.
- 2026-11-16: PR #13 merged by the owner: the first tester release
  (D53, D54): the fixes, the window, the homepage, the tester guide,
  the problem report form, the contributor clause. Reviews: one top
  tier, three delta rounds. Leftovers, kept here until they land:
  - `Recorder.stopping` is never emptied (harmless; item 4).
  - Test harness: on GitHub's runner a 150 ms delayed task ran 13 s
    late, likely `Process.waitUntilExit()` in `CommandTests` holding
    the cooperative pool [CONJECTURE]; move those waits off the pool
    (item 4).
  - The live telling of display and audio failures in `Recorder` has
    no unit test (`Recorder` is not built in any test); verified only
    live (item 4's `DisplayCapture` stand-in).
  - The last mix's wait for the sound is unit-tested only; one live
    recording on the owner's Mac checks the guide tracks' end (after
    item 1, announced to the owner).
- 2026-11-16: PR #12 merged by the owner: B2, the audio, with B1's
  follow-ups (D48 to D52); release `v0.20261116.33`. Leftovers, kept
  here until they land in a later PR:
  - **Open, found on `12f846a`:** in the owner's app recording
    (`2026-11-16 12.24.51`), the DELL's file writer fell behind twice,
    within about 3 s after the Wacom changed USB-C port and the built-in
    display came and went: its files end at 33.0 and 68.6 s and the next
    start at 38.0 and 75.3 s, so the main display lost 5 and 7 s.
    Not seen with a virtual screen on the same build, nor in the
    owner's Wacom replugs on `7ad0b6b`. The recorder gives a writer 2 s
    before it ends the file. To settle with a `--debug` run during a
    Wacom port change: whether it is the hardware encoder stalling
    through macOS's display and USB reconfiguration, and whether a
    longer allowance (frames held, not dropped) keeps the file.
    Not reproduced by the lid alone (`12.50.45`) or the Wacom port
    change alone (`12.41.06`) from `msr record`. The owner
    (2026-11-16): "if after a few seconds the recording is again good
    then I'd accept that. Main goal is auto-recovery after changes and
    continuing the recording instead of giving up". The recording did
    recover by itself, so this does not hold up B2; shortening such
    gaps belongs to the USB resilience analysis (running).
  - Guide tracks end with about 0.3 s of zeros at Stop although the
    microphones recorded sound then (`2026-11-16 12.29.59`): the audio
    sources stop at the same moment as the display files' last mix.
    Stop the audio sources after the display files' last mix.
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
