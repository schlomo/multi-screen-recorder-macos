# End-to-end tests

**Status: agreed (D37); the first part built, run by hand in a tart VM
(D67; D63's pipeline job is gone).** The owner asked for this
document (2026-11-13) after ruling that automated end-to-end tests run
on the owner's Mac first (D34), ruled on five of its open questions
(D35) and merged it, which by the rule this status line stated before
is the sign-off (D37); two questions stay open ("Open questions").
Corrected after an automated review (D38). D63 put the tests in
the pipeline, on GitHub's hosted runner; D67 took them out again and
made them a manual step in a VM ("Running them", "Why the VM"). Built (backlog item 3,
first PR): the driver, the device helper's virtual screens and mode
switches, the test tone, the restore file and `restore`, and six named
scenarios ("Built so far"). Not built yet: the picture's pattern and
its assertions, combinations and random runs, the self-test, audio
inputs appearing and vanishing, broken settings files, a full disk,
an unwritable folder, the clock scenario set, BetterDisplay and real
hardware.

Every statement about what a tool or macOS does comes from web
research of 2026-11-13 (sources at the end) and is UNVERIFIED on this
project's Mac, except what "Unknowns" marks as tried.

## What this covers

How the recorder is tested as a whole, automatically, on one Mac:
screens and audio inputs change, things fail, and a program examines
the result. What the recorder does is in [recorder.md](recorder.md).
The unit tests and the pipeline are in [recorder.md](recorder.md)
"Tests" and [delivery.md](delivery.md). What a person verifies by hand
is the v1 gate in [backlog.md](../../backlog.md).

## The goal

The owner: "important that automated tests cover error classes to help
us cover more ground quickly than by manual testing".

So the tests are organised by **error class**: a kind of thing that
goes wrong with a recording. For each class there are events that
provoke it and assertions that detect it.

## The design

**The recorder under test is the built app, as shipped,** driven
through `msr record` with a scratch `HOME` and a scratch output folder.
A run uses the app that `scripts/build-app` builds from the checkout:
built as for shipping, signed ad hoc.
The recorder has no test mode and no test-only code path.

**A test is a scenario:** a list of timed events while a recording
runs, followed by the assertions. The events come from a small fixed
vocabulary (below). An assertion is an invariant: it must hold after
any scenario. So three kinds of scenario use the same code:

- **Named scenarios,** one per event and per error class, well under a
  minute each: the regression suite.
- **Combinations,** generated: pairs of events close together and
  overlapping, because most failures need two things to happen at
  once. All pairs in both orders are hundreds of scenarios, so a run
  takes a sample that fits a time budget given on the command line,
  and prints its seed.
- **Random runs:** a seeded random sequence of events for a chosen
  time. A failure prints its seed, and the seed replays the sequence.
  This covers ground no one thought of.

**Three parts, kept apart, all Swift, in the package** (the owner left
the language to the architect, D35; the reasons are under "Why not
otherwise"). They are one executable of its own, never in the app
bundle, which `scripts/build-app` assembles from `msr` alone.
`scripts/end-to-end-test` builds it and starts it in a VM ("Running them");
`scripts/` holds scripts only, so the tests' code and data live in the
package (D35).

1. **Device helper.** It makes the events and the known picture and
   sound. Each virtual screen lives in a process of its own, a
   subcommand of the executable, so ending the process disconnects it.
2. **Driver:** reads a scenario, starts the helper and the recorder,
   fires the events on a clock, stops the recorder, runs the
   assertions, prints one line per failed assertion and exits non-zero
   on any. It requires `ffprobe` and `ffmpeg` on the `PATH` up front.
3. **Assertions,** part of the driver. They read the recording folder,
   as a person would have it afterwards, and what the driver itself
   saw: the recorder's exit status and messages. They read the recording manifest and the
   files through code of their own and through `ffprobe` and `ffmpeg`,
   never through the recorder's code: a fault shared with the recorder
   would hide itself.

Everything that needs no device and no `ffmpeg` is a library target
with unit tests in `scripts/test`, so the pipeline gates it: scenarios,
seeds, sampling, the manifest assertions, reading `ffprobe`'s output,
and the pattern, drawn and decoded again in memory.

**Each assertion is first seen failing** against a recording folder
broken on purpose (a frame removed, a track swapped, a file missing
from the manifest). The driver keeps these as its self-test: it builds
the broken samples with `ffmpeg` when run, so no media file is
committed. The samples start from a short recording
folder that the self-test also builds with `ffmpeg`, in the layout of
[recorder.md](recorder.md) "Output on disk". The self-test is not part
of `scripts/test`, which must not come to need `ffmpeg`. That the
pipeline does not run this self-test is an accepted risk, below.

**The Mac's own devices do not leak into the result.** The driver
lists screens and audio inputs before a run and asserts exactly only
on the virtual ones it adds; for the Mac's own screens and audio
inputs it asserts only that their files are readable and listed.

**Run in a person's own session** (D35). A run adds
screens, covers every screen with a pattern and changes the default
microphone, which since D67 happens in a VM, not on the Mac the tests
are started from. Not part of `scripts/test` and not part of the
pipeline.

### Running them

Once, `brew install openai/tools/tart hashicorp/tap/packer` and `scripts/end-to-end-setup`: it
clones Cirrus Labs' `macos-tahoe-vanilla` image to the VM
`msr-end-to-end` (50 GB disk, 27 GB used, 4 CPUs, 8 GB memory), disables
SIP through Recovery with Packer's `tart-cli` template
(`scripts/end-to-end-vm/disable-sip.pkr.hcl`), writes the Screen &
System Audio Recording, Microphone, Accessibility and Automation rows
into the system's and the admin user's TCC.db the way actions/runner-images does for GitHub's
runners (`scripts/end-to-end-vm/guest-configure-tcc`), installs Python
3.15 (its signature is checked) and then ffmpeg, ffprobe and BlackHole
2ch at fixed versions by their SHA-256
(`scripts/install-end-to-end-tools`). Re-running rebuilds it; it took
3.5 minutes with the base image cached. It needs `tart` and `packer` on
the `PATH` and installs neither. Every SSH login to the VM, the setup's
and each run's, uses the image's published default login, `admin` with
the password `admin`, no secret (`scripts/end-to-end-vm/askpass`, D67).

Run them on an idle Mac: the VM's screens and encoder share the Mac's
processor, graphics and media engine, and its timing checks have about
a second of slack. On 2026-11-23 and 2026-11-24, 9 of 10 runs failed
while another virtual machine (Lima), a virus scan, a backup and DaVinci
Resolve ran on the Mac, a load of 10 to 15 on 12 cores, for the release,
the release before it and a local build alike; with those stopped the
release passed 3 runs of 3 (`docs/troubleshooting.md`, "The end-to-end
tests fail at a mode switch on a busy Mac"). This qualifies "Why the
VM" below: the VM avoids the hosted runner's contention only while the
Mac itself is idle.

Per run, `scripts/end-to-end-test --scratch-folder <folder>`: builds the
app and the driver on the Mac, clones a throwaway VM from
`msr-end-to-end` (a copy-on-write clone, so every run starts clean),
copies the app and the driver in, waits until the automatic login of
the admin user has finished (the user owns the console and the tccd of
their GUI session runs; SSH answers before that, and until then the
Microphone permission reads as denied, see
[troubleshooting.md](../troubleshooting.md)), runs the driver in the admin user's
GUI session, copies the driver's whole scratch folder to `<folder>` (new
or empty; "Artifacts for review") and deletes the clone, also when the run fails. With
`--release` or `--snapshot <n>` it runs the published app instead of
building one: the latest release's zip or PR n's snapshot release's
(tag `pr-<n>`), downloaded by `scripts/install-app` into a folder of the
run's own (signature checked, quarantine removed), signed with the
owner's certificate; the driver is still built on the Mac, from the
checkout, so it must be of the app's commit (a driver that expects what
the app lacks fails its scenarios). The VM's permissions, granted by
path and bundle id with no code requirement, hold for it too (a
`--release` run of 0.20261122.79 on 2026-11-22 passed, no prompt; D72).
Arguments other than `--scratch-folder`, `--release` and `--snapshot`
go to the driver (`--scenario <name>`). The exit
status is the driver's. All 7 scenarios and the start window's
screenshot took 2 minutes 10 seconds with the build. Nothing records or
plays sound on the Mac itself.

**On the owner's Mac:** `scripts/update-homepage-screenshots --this-mac
[--app <path>]` (D82) builds the driver from the checkout and runs only
its `app-windows` subcommand, the app's window step of the scenarios'
run (`Driver.startWindow` and `recordingWindows`, told `onThisMac`), on
this Mac with the installed app or the given one: light only, no virtual
screen connected, no dark appearance, no window moved (no Accessibility
permission), `HOME`, the recording (until the status window's audio
rows are final, about 25 s or more, see the status window below) and the
scratch folder
deleted afterwards. It needs the Screen & System Audio Recording
permission and Automation for the app, System Events and Finder for the
program running it, and says which is missing; on this Mac the reopen
event asks for Automation for the app, so macOS shows its prompt (in
the VM the driver never asks); it refuses, before
building, while the app runs (quit it first) or the Mac is in dark mode,
sends the reopen event to the app's process it started, and removes its
restore file after a clean run. The screenshots then show this Mac's
real screens, cameras and microphones, so an agent tells the owner
before each run; the VM run stays the gate for marking a PR ready.

**When:** before a PR that touches the recorder or the driver is marked
ready, the architect runs it on the PR's head and records the commit and
the result in the PR description (`AGENTS.md`). The owner (2026-11-19):
"We'll leave e2e a manual step that uses the VM and another script for
setup. You'll run e2e manually when needed and mark in the pr that it
succeeded. Kiss" (D67).

### When a VM is left behind

A run deletes its clone on every exit it can handle; a killed script or
a crashed Mac can leave one. Two kinds of VM exist: the image
`msr-end-to-end`, which **must not be deleted unless you mean to rebuild
it** (`scripts/end-to-end-setup`, with a 28 GB download), and the
throwaway clones `msr-end-to-end-run-<pid>`, named after the process of
the script that made them.

1. Find them: `tart list` (State `running` or `stopped`); a running
   one has a `tart run --no-graphics msr-end-to-end-run-<pid>` process,
   `pgrep -fl "tart run"`.
2. Its IP address: `tart ip msr-end-to-end-run-<pid>` (waits with
   `--wait 60`).
3. Get in: `ssh admin@<ip>` with the password `admin`, the image's
   published default login. See its screen: `open vnc://admin:admin@<ip>`
   (macOS's Screen Sharing; the guest's port 5900 answers), or, for a
   stopped clone, start it with a window: `tart run msr-end-to-end-run-<pid>`.
4. Stop it: `tart stop msr-end-to-end-run-<pid>`; if it stays running,
   end its process: `pkill -f "tart run .*msr-end-to-end-run-<pid>"`, and
   `pkill -9 -f ...` if that does not end it.
5. Delete it: `tart delete msr-end-to-end-run-<pid>`. Deleting a clone
   frees what it wrote, not the image's 27 GB.

### Why the VM

On GitHub's hosted macOS runner the video encoder stalls at a virtual
screen's mode switch and sometimes fails: in about 2 of 9 runs the
screen file writer failed with `-11800` from `-19092`, inside a stall of
the encoder at +6.6 to +7.0 s into the recording, which hit both screen
files at once (the old one and the new one, so no fault of one
writer's input). That did not happen in 18 runs on the owner's Mac and
in a tart VM (0 failures). Hosted macOS arm64 runners are also often
unavailable, which holds the pipeline up for something that is not the
code. So the runner is not a place for these tests; the VM is the same
macOS with permissions and SIP set the way the runner has them.

### Built so far

The executable is `msr-end-to-end`; `scripts/end-to-end-test` builds it
and passes its arguments on. Its subcommands: `run` (the default: the
named scenarios, or those given with `--scenario`), `restore`, `state`
(prints what the restore file saves), and the device helper's
`virtual-screen` (one virtual screen, given its `--serial-number`, its
`--name` and its `--size`s, held until SIGTERM or until its
standard input closes, which happens when the driver ends in any way;
a line `size <width>x<height>` switches its mode) and `switch-mode`.
Its logic is the library `EndToEndLogic`, under unit tests in
`scripts/test` (`EndToEndLogicTests`): the scenarios, what the manifest
must say, the assertions on the manifest, on `ffprobe`'s output and on
decoded sound, the timecode maths, and the restore file and its plan.
The private interface is declared in the Objective-C target
`VirtualScreen` and looked up when it runs.

Two facts of macOS shape it (tried 2026-11-19, macOS 27.2.1): a process
that has read the screens' modes keeps what it read, and sees none of a
screen that connected later, so every mode switch and every read of
the state after a run is a process of its own (`switch-mode`, `state`,
`restore`); and macOS brings a virtual screen back at the last mode its
identity had, so the helper puts it back to its first size when it
starts and when it ends. A frame size change is therefore a mode switch
on the virtual screen, not the replacement "The design" describes; the
owner confirmed it (D63).

The review files and screenshots: "Artifacts for review".

The driver writes its error lines (`FAIL`, `STOP`, `restore: FAILED`,
`restore: NOT RESTORED`) to standard error and its progress and `ok`
lines to standard output, and every one of them also to `run.log` in
the scratch folder (a run starts it afresh, `restore` adds to it). Its targets are exempt from the app's rule
that only one writer writes to standard error, which protects the app's
status line (D63).

Every `msr record` gets a `--duration`: the scenario's own, or for a
scenario stopped by a signal its stop plus 120 s, a ceiling, so a
driver killed or crashed before it sends the signal never leaves the
recorder recording the person's session.

The named scenarios, each about 10 to 25 s of recording:

| Scenario | What happens | What it asserts beyond every scenario's checks |
|---|---|---|
| `plain-recording` | auto mode, ended by `--duration` | exit 0 |
| `virtual-screen` | a virtual screen of 1280 × 720 connects, switches to 1600 × 900 and back, disconnects; stopped by SIGINT | the screen's three files, frame sizes, number and times, and its events in order at their times |
| `virtual-screen-stress` | a virtual screen of 1280 × 720 connects, its mode is switched ten times, 1280 × 720 ↔ 1600 × 900, about 2 s apart (the next switch waits for the screen to settle, so at least that), and it disconnects; stopped by SIGINT | as `virtual-screen`, as strictly: no failure event, a `screen frame size changed` per switch, no lost content. Added to make the writer failure of `OSStatus -19092` happen often enough to study (D66); it passed on the hosted runner, and no frame of the new size reached the old file (D67) |
| `tone` | the test tone in BlackHole, BlackHole the default microphone for the run (the original put back after it, and by the restore) and the only input recorded (`default-microphone`), no system audio | the tone's level, no silent stretch and a click every second in each of BlackHole's tracks; the clicks at the same time of day, by timecode, in every screen file's guide track "Audio inputs" |
| `system-audio` | as `tone`, with the system audio | the system audio's file: one stereo track, its length |
| `stop-by-ctrl-c` | auto mode, SIGINT | exit 0, finalized |
| `stop-by-kill` | auto mode, `kill -9` | no `ended`, every file `recording` and readable up to its last fragment, less 0.5 s of slack (`killSlack`); a screen file's less the guide tracks' delay of 1 s too, as its fragment is written only once its guide samples arrive (`EndToEndValues.guideTrackDelay`, D80) |

The tone scenarios record only BlackHole, made the default microphone
for the run, so it is the anchor and in the guide track "Audio inputs"
from the start (D80). The anchor is the first input whose file starts
(until another has more action at the first measurement with sound,
D89; a steady test tone has hardly any), and with every input recorded
that is a race between the VM's two:
in the run of 2026-11-24 at 2628b9d, the two files' starts in the tone
scenario's `recording.json` were 0.1333 s for BlackHole and 0.1667 s
for the Apple Virtual Sound Device. Any other
input joins the guide only once measured, and the test tone never
yields a counted window: a steady 1 kHz sine with a 1 ms click each
second correlates about as well at many lags, a clarity of about 1.6
against the 12 needed (`AudioDelay.clarityNeeded`, D80), so no input is
ever measured on it, however long the run. The Apple Virtual Sound
Device hears the tone 300 to 400 ms late; with it as the anchor,
BlackHole got no audio delay and the clicks were missing from the
guide. So no scenario checks a late input's placement: that is
`RecorderTests`' (backlog item 52).
The virtual-screen scenarios still record every input (`all-inputs`),
and `plain-recording` and the stop scenarios run in auto mode (Wired).

Every scenario's checks: `msr record`'s exit status, the recording
folder's path alone on standard output, `recording.log` present next to `recording.json`, the timeline file (D68) in the folder not counted as a recorded file (its content is not checked here), `recording.json` exactly
(its keys, the app and the settings, its state, `ended`, `result`
and `cpu` for how it stopped, each file's name, label, number, state,
start, end and timecode from `started` and its start (within half a
millisecond of a half frame, either neighbouring frame, as `started` is
written to the millisecond after the timecode is taken), the guide
tracks, no failure event, the played audio input and the system audio
once; the recording ran from `started` to `ended` as long as the
driver let it, and each file of a source no event names, the played
audio input among them, starts within the settle time of the start;
both end not before the stop and at most a finalize allowance of 3 s
after it, as `ended` follows the finalizing of every file; each
scenario prints that margin, so the runs calibrate the
allowance),
and every file through `ffprobe` and `ffmpeg`: it decodes without an
error, its timecode track, its tracks and their names, the video's
codec, frame size and 30 frames for each second of its length, an audio
file's length. The tolerances are data (`EndToEndValues`), calibrated
on the owner's Mac: a time in the manifest within the change's window,
the tone within 1 dB, a click within 5 ms across files (measured: within
1 ms) and 1 ms of one second apart in BlackHole's file. A run of the six
took 97 s on the owner's Mac.

**A change's window.** For each connect, mode switch and disconnect the
driver keeps when it asked for the change and when it saw it done (the
helper reported the screen active or the mode switched; for a
disconnect, the helper has ended and the screen is gone from the active
screens). From just before the ask a thread reads every screen's place
and size every 20 ms; the changed screen's last change is the last
reading in which its own place, size or presence differed from the one
before, once it has been unchanged for the settle time after it. The
recorder's settle time is per screen and starts again with each change
of that screen's own reading, a knock-on one included (on the runner a
connect switched the own screen from 1024 × 768 to 1920 × 1080, which
can move the virtual screen too); another screen's change does not
count. A screen that has not settled within 15 s of the done fails the
scenario. A time the recorder writes for the change lies in one of two
windows, widened by the 0.5 s tolerance: **immediate** (`screen
connected`, `screen disconnected`, a file's end at a disconnect) from
the ask to the done; **settled** (a screen file's start, `screen frame
size changed`, a file's end at a mode switch) the settle time after the
change's anchor, and a screen file's start, which waits for the new
stream's first frame, up to the first-frame limit, 1 s, instead of the
tolerance late (recorder.md, "Screens coming and going"). The anchor is the later of the screen's last change and
the recorder's notice of the change: for a connect, its `screen
connected` time, which the recorder writes when macOS tells it of the
screen, measured up to about 0.5 s after the screen is in the active
display list; a mode switch has no notice, as the recorder writes
`screen frame size changed` only at the settle (its own notice
measured 0.03 to 0.08 s after the screen's last change). A connect's
file start is checked only against a notice that passed its own check;
a missing or misplaced notice fails the start too, naming it. `run.log`
shows each change's times, the screen's last change, the anchor and
where it came from, the windows' widths and, after a connect or mode
switch, how long after the settle time its file started. The `virtual-screen`
scenarios record with `--debug`, so their `msr.err` keeps the recorder's detail;
it changes only standard error, which nothing asserts.

**The system log of a failed scenario (D66).** When a scenario fails,
the driver (not the workflow) runs `log show --style compact --start
<the scenario's start, local time, a second early>` with a predicate on
the subsystems whose name contains `videotoolbox`, `coremedia`,
`avfoundation`, `screencapturekit` or `display`, and the processes
`WindowServer`, `replayd` and `coreaudiod`, and keeps the output as `logs/system.log`
in the scenario's folder, which the copy to `--scratch-folder` takes whole. When
`log show` fails or does not end within 300 s, that is one more failure
line of the scenario, never skipped silently.

**A failed file's end (D66).** The recorder now writes the end of a
file whose writer failed from what the file holds (recorder.md, "A
failed file's end"). The driver's checks are unchanged and none loosened:
such a file is still `not finalized` and a failure event is still a
failure, so the scenario fails on those as before; its frame count and
its length are now compared with the file's real end, so they no longer
add a mismatch of their own to the failure lines, and the problems list
gains the problem that tells what was lost (the check of problems' keys
is unchanged).

**Moving content.** Screen capture delivers a frame only when the
picture changes, so a virtual screen showing a static picture gives its
file no frame to start with (seen on the runner: 26 identical black
frames, the file's start only after the next mode switch). The device
helper therefore puts a borderless window on its virtual screen only,
following its bounds through mode switches, with a block that moves and
a frame counter, redrawn 60 times a second; the window never takes the
focus or the mouse and ends with the helper. The full pattern of "Known
content" is not built.

**Placing decoded sound.** A track's samples start at its first sample,
which an edit list may put after the file's start (the guide track
"Audio inputs" by a few to about 80 ms): ffprobe's `start_time` for the
stream is added to the file's timecode before clicks are compared.

**Playback breaks.** The tone player takes the tone from each render
cycle's sample time, so a cycle the output skips does not shift the
tone; each skip, and each overload the loopback device tells of, is kept
with its time of day. When a click spacing in BlackHole's file fails and
a break lies in it (within 0.1 s), the failure line says so: "playback
on the loopback device broke at <t> s (<n> samples); the recording shows
it" (an overload the device tells of may come from the recorder's own
input on it too). The breaks are kept in a fixed buffer, so the render
thread never locks or allocates; more than it holds are counted.
`run.log` gives the number of playback breaks for each scenario with
the tone.

**A break the recording shows exactly is pardoned (D67).** Run 4 of the
VM runs at 3c8fe02 failed `tone`: the test's own player ran late, the
loopback device carried 32 ms of zeros from 4.641 s (the player saw an
overload at 4.643 s), the recorder recorded exactly that, and the clicks
on either side of the hole, one lost in it, were exactly 2.000 s apart.
That is the test equipment failing, not the recorder. A failing click
spacing is therefore pardoned only when all of these hold: (a) the
track holds a hole, a quiet run found at sample resolution (the 1 kHz
tone stays below 5 % of its peak for 0.032 ms around a zero crossing,
so a run of 1 ms or more, one tone period, is no tone), between the two
clicks, which starts within the break margin (0.1 s) of a playback
break the player measured, each hole having a break of its own; (b) the
clicks on either side are a whole number of seconds apart, at least
two, within the click period tolerance (1 ms), so the hole took whole
clicks and moved nothing; (c) the number of pardons is at most the
player's break count, counted per played track (every track of the
loopback device's file records the same playback, so each shows the
same holes and uses the player's breaks once; a count over the scenario
would charge the one break once per track), which the one-break-per-hole
matching gives. The
expected click count is lowered by the clicks the pardoned holes took.
`run.log` reports each pardon: `pardoned: playback broke at 4.643 s,
31.9 ms quiet in the recording, clicks 2.000 s apart`. Anything else
fails as before: a hole without a break, a break without a hole whose
spacing is off, a hole at a break whose spacing is off by a fraction,
more holes than breaks.

### Artifacts for review

The owner (2026-11-19): "full artifact upload now, only homepage
screenshot automation comes later", and "No, screenshots as artifacts
now, to check them" (D63; the pipeline's artifact upload went with the
pipeline job, D67: the scratch folder is copied to `--scratch-folder`).
Each run writes, in its scratch folder, all of which
`scripts/end-to-end-test` copies to `--scratch-folder` (the owner,
2026-11-19: "we need full export of results, screenshots and desktop
video from the e2e runs"):

- `run.log`: every line the driver printed.
- `<scenario>/` for each scenario, passed ones included, whole: the
  recordings (the screen files, the "desktop video", and the audio
  files) in `recordings/`, `recording.json` and `recording.log` in
  there, the recorder's output in `logs/` and, for a failed scenario,
  `logs/system.log`. A run's folder is a few hundred megabytes; the
  review folder below is the quick look.
- `review/<scenario>/` for each scenario, passed ones included:
  `recording.json`, `recording.log` and `msr.err` (the recorder's
  standard error: its detail lines with `--debug`, and what macOS
  prints into it, such as `IOServiceMatchingfailed for:
  AppleM2ScalerParavirtDriver`, so passing runs show it too, D66; it
  is text, a few hundred kilobytes at most); `contact-sheet.png`, a still from the middle of
  each screen file (taken by `ffmpeg`) under a strip with the file's
  name; `excerpt <file>`, the first 5 s (`reviewExcerptSeconds`) of the
  smallest screen file and, in `tone` and `system-audio`, of
  BlackHole's audio file, copied by `ffmpeg -c copy`, not re-encoded.
- The app's windows, each in light and in dark, window only (macOS's own
  window capture, `screencapture -o -l` by the window's number from
  `CGWindowListCopyWindowInfo`, without its shadow, since the homepage's
  collage draws its own, D70), each brought to the front first so it is
  captured active, in `review/app/`, named
  `app-<window>-<appearance>.<png|mov>`; `scripts/update-homepage-screenshots`
  puts the three light PNGs of a published app's run onto the homepage's
  screenshots (D72, [homepage/README.md](../../homepage/README.md));
  `--this-mac` (D82) takes the same three on the owner's Mac:
  - `app-start-window-light.png`, `app-start-window-dark.png`: the real
    start window, the built app started as `msr` without arguments, with
    a scratch `HOME` (its ready check, `state.json` and crash report
    folder are there), then quit (the quit Apple event when macOS allows
    it without asking, otherwise SIGTERM, and SIGKILL after 15 s; the
    process is in the restore file meanwhile); System Events makes it
    the frontmost app before the capture.
  - `app-status-window-<appearance>.mov` and `.png`: the app's own
    recording, `msr record` with a scratch `HOME` (it shows the same
    status window as the app, D46). Right after the recording starts, the
    driver connects two virtual screens of their own identities and
    disconnects one of them and connects it again
    (`Scenario.statusWindowScreenEvents`), so the window shows several
    screens and a file count of 2; 8 s after the last of those the driver
    sends the app its reopen event (what a click on the Dock icon does),
    moves the window to the screen's corner with System Events (the VM's
    screen is small and the window first opens partly off it), makes the
    app the frontmost one, waits until the window's audio rows are final
    (below), and takes
    a 5 s video of that window with `screencapture -V` (H.264, 5.000 s,
    one frame per change, so about one a second), then the PNG right
    after it, then sends Stop (SIGINT) and waits for the recording's
    files. The video shows macOS's sharing indicator over the window's
    traffic lights and the pointer; the video has no shadow, its margin is
    black. The audio rows are final when every audio source whose newest
    file is being written shows its clock drift (no longer "measuring")
    and, for an audio input, its sync (no longer "not synced yet"); the
    system audio's sync is not shown, so only its clock drift is waited
    for. It is read from the recording's `recording.log`, polled once a
    second (`AudioRowsFinal`), keyed by the source's number N of its
    `Audio N` label (device names repeat, and a file name changes a
    name's `/` and `:`; a `startInput` detail line maps a device name to
    N): the clock drift from the source's latest `clock drift` detail
    line, not `not measured yet`; the sync from a detail line of one of
    its files that `joins the guide track`, `rejoins the guide track`,
    `carries over` a delay, is `in` or `out of the guide track with` the
    carried-over audio delay, `leaves the guide track` or has `no clear
    sound to sync`, which the source's newer files keep (the anchor's own
    file joins at its start, and a new file of the anchor's device logs
    nothing); a `reference … every input starts over` line clears it for
    every input but the new anchor, which show "not synced yet" again
    until they join or, unable to sync to the new anchor, show "no clear
    sound" (D89); a line `reference <file> moves: …` and a re-base change
    no row. A source in no audio (a `no audio started` event
    naming it, with no `no audio stopped` after it) is not waited for:
    its clock drift shows "measuring" for as long as it is silent. The
    event names only the device, so silence is keyed by the device name
    and two devices of the same name share it. Past 90 s
    (`audioRowsFinalLimit`, *data*) the step fails, naming the files
    whose rows are not final. In the owner's run of 2026-11-25 the clock
    drift showed at 21 s, and a Logitech BRIO's row was final about 28 s
    after its file started.
  - `app-finder-window-<appearance>.png`: a Finder window of the finished
    recording folder, driven through AppleScript: list view, no sidebar,
    no toolbar or status bar, Name, Date Modified, Size and Kind as wide
    as their content (the Name column from the longest name, measured in
    the 13 pt system font), the window as high as its rows (Finder keeps
    a minimum height, so a short folder shows empty rows), closed
    afterwards; Finder is activated with it. The two virtual screens are
    disconnected after it.
  The dark ones, the status window's video and PNG and the Finder window
  are taken only when `scripts/end-to-end-test` passes the driver
  `--throwaway-vm` (the VM's setup grants the permissions they need:
  Accessibility and Automation for System Events, Finder and the app, in
  `guest-configure-tcc`); the driver switches the whole system's
  appearance with System Events' `dark mode` and back. A run without the
  flag changes no appearance, takes the start window in light only and
  says so in `run.log`. Each appearance's own recording folder stays,
  as `app-recording-light/` and `app-recording-dark/`, beside
  `app-light/` and `app-dark/`. The start window is part of the run:
  when a window cannot be taken, the run fails like on any other failure.
  (Setting `AppleInterfaceStyle` in
  the app's own defaults domain left its window light, tried
  2026-11-19.)
- A restore file, if one is left.

Anything in the review folder that cannot be made fails the run.

### Known content

An assertion can only detect a wrong picture or sound if it knows what
was shown and played.

- **Picture:** the helper shows a full-screen pattern on every screen:
  blocks that encode the screen's identity, a frame counter and the
  time in milliseconds, large enough to survive scaling and HEVC.
  The blocks are black and white and are read by brightness, because
  HEVC stores colour at a lower resolution than brightness. Tried (see
  "Unknowns"): the menu bar of macOS covers the top of a virtual
  screen, so the blocks stay below it.
  Colour is asserted on its own. The owner: "shouldn't we also check
  colors to ensure that no problem creeps in with colors? After all,
  all screen content is colored". So the pattern also carries large
  colour fields (red, green, blue, their mixes) and grey steps from
  black to white. Two assertions use them. One reads the screen
  file's colour tags with `ffprobe` (primaries, transfer, matrix,
  range) and compares them with what the recorder design says it
  writes (always SDR with the colour space tagged, D24; which colour
  space, the recorder design must name). The other decodes the fields
  with `ffmpeg` into sRGB and compares them with the sRGB values the
  helper drew: that detects a wrong matrix and a wrong range, where
  black comes back grey and white dull. A wrong primaries or transfer
  tag does not change decoded values, which is why the tags are
  asserted themselves. The tolerance is calibrated on the first
  recordings.
- **Sound:** a virtual audio input carries a tone and a click once a
  second, played into it by the helper.

Limits of the sound, which the assertions respect: one loopback device
(BlackHole) gives one signal, so several virtual audio inputs built on
it carry the same tone and cannot be told apart by content; the Mac's
own microphone records the room, which may be silent (a muted input, a quiet room), so it is asserted only as readable and listed, like all of the Mac's own devices;
whether a tone played into a loopback device also lands in system
audio is unknown. Telling several audio inputs apart by content needs
several loopback devices, each with its own tone. The owner: own
helpers "might be useful if cheap to build" (D35). The cheap way,
untried: BlackHole comes as three drivers (2, 16 and 64 channels) that
are said to install side by side, and its source builds further
drivers under other names; a test audio driver of our own is built
only if that falls short. See "Unknowns".

### Error classes

| Error class | Events that provoke it | Assertions that detect it |
|---|---|---|
| **A file is lost or unreadable** | kill the recorder (`kill -9`), also while it finalizes; full disk; output folder made unwritable or its volume removed; sleep; a screen or audio input vanishing | every file in the recording folder opens and decodes to its last complete fragment (fragments of 2 s, [recorder.md](recorder.md)); nothing recorded more than one fragment before the event is missing |
| **Wrong picture** | screens connect and reconnect (a macOS fault then delivers another screen's picture, seen on the owner's Mac with virtual screens), mirroring, main screen change, many screens at once | the identity decoded from each screen file is that file's screen; no black stretch; the pattern's counter keeps advancing; the colour fields and grey steps come back as shown, within a tolerance, black as black and white as white |
| **Wrong sound** | audio inputs appear and vanish, default microphone changes, channel count and sample rate change | a virtual audio input's audio file holds the tone, on every track; no silent stretch in it; each guide track is present in every screen file |
| **Wrong timing** | still picture for 60 s, load on the processor, a stalled recorder (`SIGSTOP`, then `SIGCONT`), long random runs | every screen file has 30 frames for each second of its length; the time shown in each recorded frame is that frame's time within one frame, except where the last picture is repeated by design (D11, D21): during a still picture or a stall the scenario makes, the shown time may lag by up to the length of that still picture or stall, and under load by a bound the recorder design sets ("What the recorder design must provide"); it never runs backwards or ahead of the frame's time; the timecode of every file matches its start; where no picture is repeated, the click sits at the frame that shows its time |
| **A change handled wrongly** | every screen and audio event below | the right file ends and the right one begins; a frame size change leaves under one second without picture (D30); the audio files have no gap across it; a screen keeps its number; an unchanged frame size continues the file |
| **The recording manifest is wrong** | all of them | `recording.json` lists exactly the files in the folder; each event the recorder design defines appears once, in order, at the scenario's time; its state is right after Stop and after a kill |
| **Resources run out** | a small disk image as output folder, filled during a recording, then given room again; processor and memory pressure; more screens than the Mac has hardware encoder sessions | what was written stays readable; the recorder keeps retrying and continues in new files once there is room (D14); nothing is discarded |
| **The process ends badly** | `kill -9`, `SIGTERM`, a second recording into the same recording folder, a recording into another folder in parallel (D20) | after `kill -9` the recording manifest has no `ended` and the audio files are readable up to the last 2 s and the video files up to about the last 3 s, a fragment waiting for its guide samples (D47, D80); after `SIGTERM` the recording ends as after Stop, finalized ([recorder.md](recorder.md), "Command line"); the second recording into the same folder is refused; parallel recordings do not disturb each other |
| **Settings and start** | old, damaged and empty settings files; auto mode on and off (D34) | a settings file is never refused; the recording folder holds what the settings ask for |

### Events

| Event | How it is made | Needs |
|---|---|---|
| Screen connects, disconnects | the helper creates a virtual screen through Apple's private `CGVirtualDisplay` interface; ending its process removes it | private interface |
| Frame size changes, HiDPI | a mode switch of the virtual screen through the public interface, in a process of its own (D63; replacing it by one of another size does not work, as macOS brings an identity back at its last mode, and the screen was removed after every mode switch, both tried 2026-11-19); on one of the Mac's own screens, a mode change through the public interface | |
| Mirroring, arrangement, main screen | the helper, through the public display configuration interface (Apple's) | |
| Rotation; one of the Mac's own screens switched off and on | BetterDisplay's command line | BetterDisplay Pro, a paid licence (the owner: "I have BetterDisplay Pro if it helps we can use it"); a scenario set of its own, asked for by name, which stops with an error where BetterDisplay is missing |
| Audio input appears, vanishes, changes its channel count | the helper creates and removes an aggregate device around BlackHole through the public CoreAudio interface | BlackHole installed once (administrator) |
| Sample rate, input volume | the helper sets them on BlackHole | |
| Default microphone changes | the helper, through the public CoreAudio interface | |
| Screen sleep; sleep and wake | `pmset` | screen sleep locks the Mac where macOS is set to ask for the password after it; wake is reported unreliable, and the Mac may wake locked; a locked Mac needs the person: a scenario set of its own, asked for by name, with the person present |
| Kill, stall, full disk, unwritable folder, volume removed, load | `kill`, a small disk image, `chmod`, `memory_pressure` | |
| A real USB microphone is pulled; the clock, the date or the time zone changes | the helper captures the USB device so the Mac loses it; the system clock is set | administrator; a scenario set of its own, asked for by name; the USB capture is unproven on macOS 26 |

### What these tests cannot do

Their output names what a run did not cover. These stay with a person
(the v1 gate):

- the app itself: Start in the window, the Dock icon, Stop, Quit,
  finalizing at logout (the tests drive `msr record` only);
- closing the lid, a cable pulled from the Mac's own port, a real
  screen's own behaviour (HDR, variable refresh rate);
- power loss and a kernel panic: after `kill -9` macOS still writes
  out what the recorder handed it, so a kill does not prove what
  survives losing power;
- a Bluetooth headset switching to call quality, an iPhone as
  microphone, AirPlay;
- the drift of a real audio device's clock: a virtual audio input runs
  on the Mac's clock;
- a locked screen (unlocking needs the person's password), the
  permission prompts of a first start, a permission taken away during
  a recording, and the monthly "continue to allow" prompt of macOS;
- whether an editor (DaVinci Resolve, Kdenlive) places the files right.

A virtual screen is drawn by the same window server and captured
through the same ScreenCaptureKit as a real one, so these tests should
show how the recorder handles a change. That removing a virtual
screen looks to the recorder like pulling a cable is an assumption,
UNVERIFIED. One difference may already be known: the wrong-screen
fault shows after a virtual screen reconnects ("Unknowns"), and
whether it shows with the Mac's own screens is untried. Until that
is tried, a wrong picture after a reconnect is a failed assertion all
the same: the recorder has to deliver the right screen in either
case, and a recorder that cannot yet keeps those scenarios failing.

### Known limits of the clock drift correction

The correction measures a device's clock from when its buffers arrive
([recorder.md](recorder.md), "Clock drift"); what that cannot tell
apart, a test cannot either:

- **A lasting latency change is taken as a clock offset.** When a
  device's buffers start to arrive later or earlier for good (a driver
  or a dock changing its buffering), the correction follows it as if
  the device's clock had jumped: up once the points before the change
  leave the 20 s horizon, down at once, at up to 1000 ppm, so that
  source's sound moves by the change; a step down overshoots (1.1 ms on
  2 ms, 2.1 ms on 4 ms). The clock drift shown, the median of the
  latest estimates' slopes, stays within 1 ppm through a step.
- **Late points that outweigh the others tilt the line.** Whenever the
  late points outweigh the others in the horizon, the support line tilts
  until they leave it, and empty intervals make that easier: nothing for
  8 s with the backlog drained over 6 s 6.8 ms off; a stall of 6 s or
  more can tilt it (6 s 0.85 ms at -116 ppm, 5.2 ms at +48.6 ppm), of
  7 s up to 6.2 ms, of 9 s with the buffers queued behind it up to
  8.3 ms, of 30 s up to 30 ms; a source at its lowest only once in 12 s
  with the rest 6 ms higher swings by up to 3.2 ms all the time. The
  clock drift shown stays within 3.1 ppm through a stall of up to 30 s;
  after a longer one it is the tilted slope until the tilted estimates
  are under half again (a stall of 40 s from 100 s: off by up to
  884 ppm, more than 5 ppm off from 131 s to 188 s, so about 90 s from
  the stall's start), and a file's `clockDriftPpm` if it ends then.
- **A gap after a long tilt adds the tilted slope.** The drift added
  across a gap is the kept slope, the median of the latest estimates'
  slopes, times the gap's length, so it carries the kept slope's error
  times the length: small while the tilted slopes are under half of
  the kept ones (a 600 s gap at once after a stall of 9 s moves the
  correction by up to 0.26 ms, of 20 s 0.84 ms, of 30 s 2.5 ms; a
  3600 s gap after 9 s 1.6 ms), the tilted slope after a tilt that
  lasted longer than the median covers (a stall of 40 s, then a 600 s
  gap within 30 s: 530 ms).
- **The reference is never revised.** It comes from the first
  estimate's about 10 s of points: a source at its lowest only once in
  8 s can start up to 3.4 ms off for good, depending on where its
  lowest second falls (within 0.57 ms in three of its eight phases);
  the system audio's measured 4 s pattern is within 0.32 ms in all
  four phases.
- **One early buffer pulls the line down, amplified.** A buffer early
  by a glitch of its timestamp or arrival puts the line under it for
  the horizon: 20 ms early up to 12.3 ms off, 6 ms early 8.9 ms, 3 ms
  early 4.4 ms, and up to 42 s until back within 0.5 ms.
- **A gap assumes the timestamps keep following the sample count.**
  After a gap the new segment starts at its own timestamp plus the
  correction applied so far plus the device's drift during the gap (the
  kept slope over its length); a source whose timestamps jump to the
  host clock across a gap would be off by its drift until then. The
  detail line for each gap shows the drift added and the lateness
  before and after it, which tells.

All figures are the worst of 20 seeds of the tests' simulation.

### What the recorder design must provide

The assertions need these, and [recorder.md](recorder.md) does not
have them yet; they go into the recorder PR's design:

- an expected result, and a manifest event, for: a screen connecting,
  mirroring switched on and off, the main screen changing, the default
  microphone changing, sleep and wake;
- the gap allowed in a screen file's guide tracks across a frame size
  change;
- on the command line, which screens and audio inputs a recording
  will record, as the window's tables show it (D13: every feature in
  both front ends);
- with auto mode off, a way to choose audio inputs (open in D34):
  without it a virtual audio input is recorded only while it is the
  default microphone;
- what picture a tick written late carries (it is counted in
  `framesRepeatedForLateness`, [recorder.md](recorder.md), "How the
  recorder works"), how far the shown time may then lag, and how that
  can be checked from outside the recorder, without trusting its own
  count.

## Permissions

The two permissions are granted once by a person.

- **Who holds them: the app the run is started from** (D35). A `msr`
  started from a terminal is attributed to the terminal app
  ([recorder.md](recorder.md), "Command line"), so that app holds
  Screen Recording and Microphone, and so does every program started in
  it, an agent's shell included. The owner: "whoever runs it, if
  needed the terminal or vscode (my vscode has already)". The
  architect's reading: that app may hold them, and the two ways out
  this document proposed before (starting the recorder through macOS,
  a terminal app kept for the tests) are not needed. The driver starts the recorder as its own child process, which gives it
  the process to signal, the exit status and the messages. Before
  anything else the driver asks macOS, without raising a prompt,
  whether both are granted, and stops with the name of the missing
  permission if not.
- **Whether they survive a rebuild** then does not depend on the
  build's signature, because the app the run is started from holds
  them, not `msr`. [ASSUMED from the attribution above; the first run
  shows it.]

## What research found for the recorder

For the recorder PR's design, each UNVERIFIED here unless marked as
tried:

- **ScreenCaptureKit delivers the wrong screen** after a virtual
  screen reconnects when two exist (reported as Apple feedback
  FB17797423; BetterDisplay is said to work around it). Tried, and it
  shows on the owner's Mac (see "Unknowns"; one run): after screen A
  came back, every new stream on A delivered screen B's picture, in three
  reconnects of three, while a screenshot of A through the same
  ScreenCaptureKit screen was right. The recorder must verify which
  screen a stream delivers, and its design needs a way to get the
  right one, which no experiment has found yet. Tried again
  (2026-11-15, 13 runs): it depends on the order of creation. When the
  screen that reconnects was created before the other one, every
  reconnect showed the other screen's picture (11 of 11 in 8 runs);
  when it was created after, none did (7 of 7 in 3 runs). The system
  holds the fault: a fresh process, a new serial number, a new fetch of
  the shareable content and the other workarounds tried did not clear
  it, and a screenshot through the screen filter was wrong too.
  `SCStreamFrameInfo.screenRect` is a one-directional sign: in every
  reconnect that showed the other screen's picture (11 of 11, one
  frame sampled per check) the frame's `screenRect` was the other
  screen's rectangle, and with a filter that includes A's window the
  frame was transparent, at the other screen's rectangle; but once a
  frame with a matching `screenRect` was black (cause not known,
  perhaps not yet painted), so a match does not prove the picture
  right. The run logs of 2026-11-15 are not kept. A screenshot with
  `SCScreenshotManager.captureImage(in:)` of the screen's bounds
  was right in 3 of 3 faulty runs; as a recording path it is
  UNVERIFIED (its cost at 30 frames per second is not known). So the
  recorder needs a check per frame that never writes a mismatched
  frame as that screen, and, since restarting does not help, a way
  to fail that screen loudly. Proposals for the recording core's
  design, untested: compare `screenRect` with `CGDisplayBounds` on
  every frame, act after several mismatched frames in a row (what
  debounce a mode change needs is UNVERIFIED), fall back to the
  screenshot. For these tests: create the reconnecting screen first
  to trigger the fault, last to avoid it. Not tried: whether this happens with the
  Mac's own screens or only with virtual ones, and three or more
  screens.
  Whether the owner's BetterDisplay HiDPI mode works through virtual
  screens, and so meets this fault in daily use, is a question for
  the owner.
- **A stream is told when its screen goes.** Tried (see "Unknowns"):
  the stream on a virtual screen stopped with error -3815 of
  ScreenCaptureKit's stream error domain 0.12 to 0.24 s after the
  screen went, in three cases of three; a stream on the other screen
  kept delivering throughout.
- **A screenshot's colour space had no name** in that run (see
  "Unknowns"). The recorder design names the colour space it tags
  (D24), so it must find out what ScreenCaptureKit delivers. Tried
  (2026-11-15, one run): the frames carry a colour space attachment
  without a name, whose ICC description is the screen's name, and no
  ICC profile key, in every format; BGRA has no primaries, transfer or
  matrix keys, while 420v and 420f are BT.709 in all three. So the
  recorder cannot read a colour space's name from the frames; for BGRA
  the frames carry no primaries, transfer or matrix to read either. Not tried: `colorSpaceName` and
  `colorMatrix`.
- **macOS's display ID is not a screen's identity.** Tried (see
  "Unknowns"): the same virtual screen got a new display ID each time
  it was created. A screen that comes back during a recording may
  so have another display ID; the recorder's stable identity for a
  screen (`backlog.md`, recorder PR) cannot be the display ID alone.
  Tried again (2026-11-15, 55 creations in the logs): the UUID from
  `CGDisplayCreateUUIDFromDisplayID` stayed the same across
  reconnects, processes and runs for the same vendor, product and
  serial number, and changed with a new serial number; the name did
  not stay ("MSR Test", "MSR Test (1)"). A serial number can be 0
  (the Wacom). So the UUID is the candidate identity; whether a
  real screen keeps its UUID after it was unplugged is UNVERIFIED.
- **AppKit may not list a new screen to a program that does not handle
  the app's events.** Tried (see "Unknowns"): not listed within 5 s
  without, listed after about a second with. The recorder lists
  screens through AppKit today; `msr record` from the command line
  must be shown to see a screen that connects during a recording.
  Tried again (2026-11-15, six runs): `CGDisplayRegisterReconfigurationCallback`
  never fired under `CFRunLoopRun`, `dispatchMain` or
  `NSApplication.shared` with `CFRunLoopRun`, and fired under
  `NSApplication.shared.run()`; polling `CGGetActiveDisplayList` saw a
  new screen after 0.11 to 0.16 s and `SCShareableContent` after 0.17
  to 0.23 s. So `msr record` would need to poll or run the AppKit loop.
- **A mode change is not a reconnect, and the frames keep the configured size.**
  Tried (2026-11-15, HiDPI in two runs, 1x in one; see "Unknowns"): a
  mode switch during a stream gave no error, the display ID stayed, and
  with a configured size of 1920 × 1080 the frames stayed that size
  with the content scaled and `screenRect` following the new bounds;
  a 4:3 mode came pillarboxed. The running stream kept delivering the
  configured size, so a screen file at the new size needs the stream
  reconfigured or restarted. A mode change can be told from a
  reconnect by the display ID and the callback's flags. Not tried:
  `updateConfiguration` or a restart to the new size, and a mode
  switch while the wrong screen's picture is shown.
- **The audio clock of an audio input drifts against the host clock,
  and `AVCaptureSession` does not correct it.** Tried (2026-11-15, one run of one
  hour, macOS 26.7.1): one `AVCaptureSession` for each of five audio
  inputs started together, the audio discarded, the samples of each
  counted and compared with the host clock from the first buffer on
  (the buffers arrive about 10 ms apart, so figures are good to about
  that). At 3600 s the samples counted minus the host time were:
  Razer Seiren V3 Mini (USB) -0.4217 s (-117 ppm), CalDigit
  Thunderbolt 3 Audio (USB) +0.1782 s (+50 ppm), Logitech BRIO (USB)
  +0.0097 s, MacBook Pro Microphone 0.0000 s and BlackHole 2ch
  (virtual) -0.0046 s. All five ran at 48000 Hz. The rate was steady
  over the hour. The buffers' presentation timestamps follow the
  sample count (the timestamp minus the samples stays constant; the
  constant of about 11 ms is the first buffer's duration, which follows
  from the probe's code, which leaves the first buffer out of the
  count, not from a measurement), so
  `AVCaptureSession` does not correct the drift in the timestamps it
  delivers. Whether Core Audio's own path corrects it was not measured.
  Hence two inputs
  recorded for an hour drift apart by up to 0.6 s, and an audio file
  that is placed by its sample count alone is that much off the
  screen files. A recorder
  that places each audio input on the host clock needs a correction;
  resampling is the obvious one (a proposal for the recording core's
  design, untested). Not tried: a run of several
  hours, other audio inputs, a run under load or with the Mac asleep,
  a Bluetooth input, and any correction.
- **When an audio input's buffers arrive shows its clock; their
  timestamps do not.** Tried (2026-11-16, one probe of 300 s, macOS
  26.7.1): one `AVCaptureSession` per audio input, five inputs, each
  buffer's arrival on the host clock against its sample count.
  `AVCaptureSession`'s timestamps follow the sample count exactly (the
  timestamp minus the samples spread 0.000 ms over 300 s, all five), so
  they carry no clock drift. The smallest, per second, of a buffer's
  arrival minus its audio time is the device's clock against the host
  clock: a straight line with a residual of 0.04 ms (standard
  deviation) for the Razer Seiren V3 Mini (-116.1 ppm), CalDigit
  Thunderbolt 3 Audio (+49.1 ppm), MacBook Pro Microphone (+1.7 ppm)
  and BlackHole 2ch (0.0 ppm), agreeing with Core Audio's own device
  clock (`AudioDeviceGetCurrentTime`,
  `kAudioDevicePropertyActualSampleRate`) to under 0.1 ppm. The
  Logitech BRIO's rate is not constant: -116 ppm for the first 45 s,
  then swinging between about -60 and +110 ppm with a period of about
  25 s around 0 (a sawtooth of ±0.5 ms), so a single measured rate
  cannot correct it; a correction must follow the offset. After 300 s
  the Razer was 34.7 ms behind the host clock, more than one frame.
- **The system audio arrives in bursts, so one second's smallest
  lateness is not its clock.** Tried (2026-11-17, one probe of 120 s
  (128 s of data) of a ScreenCaptureKit audio stream, macOS 26.7.1): its buffers hold 960
  samples, their timestamps follow the sample count exactly, but they
  arrive every 21.33 ms (median) with catch-up bursts. The smallest
  lateness per second is a sawtooth, not a line: 41.6, 44.3, 47.2 and
  43.1 ms, repeating every 4 s, with no clock drift (the lowest points
  stay within 0.25 ms over 120 s). The smallest over about 5 s is its
  clock. On the real arrivals of six sources (these probes), the
  correction as built (the lower support line of each interval's
  smallest lateness over 20 s, [recorder.md](recorder.md), "Clock
  drift") kept BlackHole within 0.05 ms, MacBook Pro Microphone 0.11 ms,
  CalDigit Thunderbolt 3 Audio 0.28 ms, Razer Seiren V3 Mini 0.48 ms
  and Logitech BRIO 0.93 ms against its 5 s envelope; the system
  audio's correction ended at 0.09 ms with its rate within ±67 ppm.
- **An unplugged audio input ends its `AVCaptureSession`, which does
  not resume.** Tried (2026-11-15, the Razer Seiren V3 Mini over USB,
  unplugged during a running session): `AVCaptureSession`'s runtime
  error -11808 (`AVErrorDeviceWasDisconnected`) and
  `AVCaptureDevice.wasDisconnectedNotification` came at once,
  `wasConnectedNotification` 17 s after plugging it in again; nothing
  crashed, and the session did not resume by itself. Hence the
  recorder ends the audio file on the unplug and starts a new session
  and file on the replug (D49).
- **An audio-only fragmented `.mov` carries a timecode track.**
  Tried (2026-11-16, the tests in `AudioFileWriterTests`):
  `AVAssetWriter` writes a timecode track with its reel name into a
  fragmented `.mov` that has only audio tracks, finalized and not
  finalized, and AVFoundation reads it back associated with every
  audio track. Whether DaVinci Resolve reads it is UNVERIFIED.
- **A plain executable no longer appears in the Screen Recording list**
  (macOS 26.1, called a bug by Apple); see "Permissions".
- **A build signed ad hoc is reported to lose its permissions with
  every rebuild.** That concerns the app started from Finder, which
  holds its own permissions (D5), not a run of these tests.

## Safeguards for the person's session

- A run records the Mac's own screens and audio inputs too. Its
  recording folders live in the scratch folder and are all kept, a
  passed scenario's too (D67); a failed one says its path.
- Before a run the driver writes to a restore file what the run may
  change: the screen arrangement, mirroring and the main screen;
  whether each of the Mac's own screens is on, with its mode and
  rotation; the default
  microphone and the default output; the sample rate and input volume
  of every BlackHole device; and, for the scenario set that changes
  them, the time zone, whether the time is set automatically and the
  time itself. It restores them after the run, after a failure and
  after Ctrl-C. If the driver itself is killed, `restore` as its only
  argument does the same from the restore file, and removes every
  virtual screen carrying the tests' vendor and product ID and every
  aggregate device carrying the tests' UID prefix (an aggregate device
  may outlive the helper that made it).
- The time is restored first, as the saved time plus the time elapsed
  since, read from a clock that counts sleep and that setting the time
  does not move; then the time zone and whether the time is set
  automatically. If the Mac restarted in between, the elapsed time is
  lost: `restore` restores the rest and says that the time is the
  person's to set, unless it is set automatically again. Untried (see
  "Unknowns").
- As built (D63): the restore file is `restore.json` in the scratch
  folder (`--scratch-folder`, by default `msr-end-to-end` in the
  temporary folder), with the processes the run started (`msr record`
  and the helpers), so `restore` ends them should the driver be killed;
  a run refuses to start while a restore file is left. The driver runs
  `restore` as a process of its own after each scenario and at the end;
  it puts back what an interface can put back, reads the state back and
  names every difference, keeping the restore file until there is none.
  Whether a screen is on and its rotation are only compared: putting
  them back needs BetterDisplay, which no scenario uses yet. The time,
  the time zone and whether the time is set automatically are not in it
  yet: no scenario set changes them. The helpers end when the driver
  ends in any way (their standard input closes).
- Virtual screens use a small fixed set of identities: macOS keeps an
  arrangement and a colour profile (owned by root, never removed) per
  identity; the scenarios use one, serial number 101 of the tests'
  vendor and product (`0x4D53`, `0x5254`), and the status window's
  capture two more, 201 and 202. The driver recognises its screens by
  that vendor and product ID. Each screen's name is display text only,
  realistic so the recorder's own screens' names look like a Mac's
  (D73): "Desk Monitor" (1600 × 900, serial number 201),
  "Portable Monitor" (1280 × 720, serial number 202, and the one
  the scenarios use, which starts at that size). `ManifestCheck`
  matches the recorder's names against the names of the screens a
  scenario connects, by their start, as macOS may append a counter.
- Nothing switches off the built-in screen: a helper killed while
  holding it off is reported to leave it off until logout.
- Nothing sends keystrokes or asks for the person's password.
- Whether the tones are heard on the Mac's speakers is unknown; the
  helper plays them into the loopback device, not the default output.

## Cost

No money beyond BetterDisplay Pro, which the owner has. The named
scenarios take about 2 minutes in the VM, combinations and random runs
as long as their time budget; the Mac stays usable during a run. Once:
the VM, 27 GB of disk and 3.5 minutes. Building the helper, the driver and the first
scenarios is the larger cost, estimated at one PR the size of the
skeleton PR; the pattern decoder is the uncertain part. The pipeline
compiles and unit-tests the tests' code with every push, which adds to
its run time; it does not run the scenarios (D67).

## Why not otherwise

- **The owner's Mac itself:** the Mac cannot be used during a run, and
  the permissions are the terminal's. A tart VM gives a clean start per
  run (D67); what needs real hardware or BetterDisplay stays on the
  owner's Mac. The guest has one screen and no USB audio, so screen
  changes use the same virtual screens, and the encoder under test is
  the guest's.
- **GitHub's hosted runners:** they ran the tests from D63 to D67 and
  stalled the video encoder at a virtual screen's mode switch ("Why the
  VM").
- **A self-hosted runner on the owner's Mac:** GitHub advises against
  one for a public repository; a pull request could run code on the
  Mac.
- **Hardware** (switchable HDMI or USB hubs): real unplugging, at a
  price and with wiring; revisit if virtual screens prove too far
  from real ones.
- **Faking ScreenCaptureKit and CoreAudio inside the unit tests:** fast
  and worth having for the recorder's logic, but it tests our idea of
  what macOS does, not what it does.
- **A driver in Python,** beside the other scripts (D32): its tests
  would reach `scripts/test` only through commands, and scenario, event
  and pattern would be defined twice, in Python for the driver
  and in Swift for the device helper. In Swift the compiler checks all
  of it, one test suite covers it, and an agent changing an event
  changes one definition.
- **The driver inside the Swift test suite,** as tests with a tag:
  `swift test` would then need screens, permissions and `ffmpeg` for
  some of its tests, and a random run with a seed and a time budget is
  a program with arguments, not a test case.
- **Starting the recorder through macOS (`open`)** so that the app
  holds the permissions: untried, and the driver would be expected to
  lose the recorder's process, exit status and messages; not needed
  once the app the run is started from may hold the permissions (the
  architect's reading in D35).
- **A second user account for the runs:** the owner is at the Mac for
  a run in any case (D35), and no source says ScreenCaptureKit works
  in a session that is not in front.
- **`displayplacer` and `SwitchAudioSource`:** the helper does what
  they do through the same public interfaces, with two tools fewer to
  install.

## Accepted risks

- `CGVirtualDisplay` is private: an update of macOS can break the
  helper. It is test equipment only and never ships in the app. The
  package compiles it with everything else, so its declarations of the
  private interface are its own and are looked up when it runs: a
  macOS or Xcode without the interface must still build the app.
- Fast connect and disconnect cycles are reported flaky in macOS
  itself; a failure there must be told apart from a recorder fault,
  and a flake is root-caused, never retried blindly.
- The tests are not a gate: a person runs them (D67), and a PR
  that touches the recorder or the driver may be ready without a run if
  nobody remembers; `AGENTS.md` says when they run. The VM's setup
  depends on the download sites of the base image, Packer's tart
  plugin, ffmpeg, BlackHole and Python being reachable.
- The pipeline does not gate the self-test (not built yet), which needs `ffmpeg` and
  runs on a Mac, before a run and when the driver changes. What it
  alone covers is whether an assertion still fails on real files
  broken on purpose; a change that breaks that is seen at the next
  run, not at the PR.

## Unknowns, each settled by a small experiment

Throwaway code, run by the owner or on the owner's go-ahead, before
this design is built:

- a virtual screen appears in ScreenCaptureKit and delivers a real
  picture. **Tried** (2026-11-13, macOS 26.7.1, five runs as the
  owner's user without `sudo`: three from an app without Screen
  Recording, then two by the owner from an app that holds it).
  Observed in the first three: a virtual screen of 1920 × 1080 was an active
  screen 0.3 to 0.4 s after it was created, at the left of the main
  screen; AppKit listed it as a screen about a second later in the
  run that handled the app's events, and not within 5 s in the two
  runs that did not; every run started with the Mac's two screens, so
  the virtual screen of the run before was gone by then; macOS's
  display ID was 5, 6 and 7 in the three runs, though the program
  gave the screen the same vendor, product and serial number each
  time. The capture part did not run in these: the program asks macOS
  whether Screen Recording is granted in the way that raises no
  prompt, and stopped. Observed in the owner's two runs (display ID 9
  and 10): ScreenCaptureKit listed three screens, the virtual one
  among them at 1920 × 1080; a screenshot of it showed the program's
  full-screen window, with the menu bar of macOS across the top; the
  window's magenta (sRGB 1, 0, 1) is in the saved screenshot exactly
  as shown, 255, 0, 255, tagged sRGB. The program itself printed
  1.00, 0.25, 1.00 for it: a fault in how the program read the pixel,
  not in the capture, and the first of the two runs stopped at it. In
  the second, a stream at 30 frames per second delivered
  150 buffers in 5 s, 63 of
  them complete frames, while the picture changed 50 times; the
  screen was gone 0.11 s after the program released it. **Tried
  again** (2026-11-15, macOS 26.7.1, about 35 runs of 3 to 25 s from
  the owner's terminal, which holds Screen Recording; the runs of the
  next four items belong to these). The virtual screens were left of
  the main screen and gone after each run; the Mac's own screens
  kept their display IDs, bounds and modes; one hung probe was killed,
  no process was left and no prompt showed. macOS may remember the
  arrangement and name for the serial numbers 101, 102, 111, 121, 301, 401
  and 501 (UNVERIFIED). A virtual screen's identity, its looks-like size
  and mode changes, its colour space and how to list it without
  AppKit are in the items below. Not tried: three or more screens;
- the identity of a screen. **Tried** (2026-11-15, 55 creations
  in the logs; the Mac's own screens were only read, twice). With the
  same vendor, product and serial number,
  `CGDisplayCreateUUIDFromDisplayID` gave the same UUID across
  reconnects, processes and runs; with a new serial number, a new
  UUID. The display ID was new every time (18 to 72). The name was not
  stable: "MSR Test", then "MSR Test (1)", then "(2)". Two virtual
  screens with the same vendor, product and serial number cannot
  exist at once (the initialiser returns nil). The Mac's own screens:
  a Dell with vendor 4268, model 41382 and serial 810828108, and a
  Wacom with vendor 23587, model 4217 and serial 0. A serial number
  can be 0, so the UUID is the candidate identity. Not tried: a real
  screen's UUID after it was unplugged (UNVERIFIED);
- the looks-like size and a mode change during a stream. **Tried**
  (2026-11-15; a HiDPI screen in two runs, a 1x screen in one). A
  screen that looks like 1920 × 1080 in HiDPI: `CGDisplayBounds` and
  the mode's width 1920 × 1080, pixel width 3840 × 2160, `SCDisplay`
  1920 × 1080, `pointPixelScale` 2. A default `SCStreamConfiguration`
  always delivered 1920 × 1080 in YCbCr; with the size in points set,
  frames of 1920 × 1080; with the size in pixels set, 3840 × 2160.
  A mode switch during a stream (configured 1920 × 1080,
  `scalesToFit`, `preservesAspectRatio`): no error, the frames stayed
  1920 × 1080 with the content scaled (`contentScale` 0.75 from HiDPI,
  1.5 from 1x), a 4:3 mode pillarboxed (`contentRect` 240, 0, 1440,
  1080), and `screenRect` followed the new bounds. It is not a
  reconnect: the display ID stayed the same, and the reconfiguration
  callback's flags were 0x1 then 0x100a; HiDPI to 1x at the same size
  gave 0x8 only. Connecting gave 0x111a and disconnecting 0x1220. Not
  tried: a mode switch on the screen that shows the wrong picture
  (the next item);
- the colour space of the frames. **Tried** (2026-11-15, one run; the
  virtual screen and both of the Mac's own screens). The ICC profile
  key was absent (`ICC=nil`) in every format; the frames carried a
  `CGColorSpace` attachment with no name, whose ICC description was the
  screen's name. BGRA carried no primaries, transfer or
  matrix keys; 420v and 420f carried BT.709 primaries, transfer and
  matrix. Red read back as BGRA 0, 0, 255, 255; 420v Y/Cb/Cr 63, 102,
  240; 420f 54, 99, 255 (what BT.709 gives for 255, 0, 0). Not tried:
  `colorSpaceName` and `colorMatrix`;
- listing screens without AppKit. **Tried** (2026-11-15, six runs).
  Polling `CGGetActiveDisplayList` saw a new screen 0.11 to 0.16 s
  after the helper started and `SCShareableContent` 0.17 to 0.23 s;
  the screen was gone after 0.02 to 0.18 s and 0.17 to 0.74 s
  respectively. The mean of an `SCShareableContent` fetch was 110 to 300 ms per run; single fetches took up to 731 ms.
  `CGDisplayRegisterReconfigurationCallback` never fired under
  `CFRunLoopRun` (two runs), `dispatchMain` (two runs) or
  `NSApplication.shared` with `CFRunLoopRun` (one run); it fired under
  `NSApplication.shared.run()` on the main thread (one run). So
  `msr record` would need to poll or run the AppKit loop;
- two virtual screens, one reconnects: does the wrong-screen fault
  show on this Mac. **Tried, and it does** (2026-11-13, one run by the
  owner, from an app that holds Screen Recording). Screen A showed
  red, screen B blue; A was released and created again three times,
  with the same vendor, product and serial number, and got screen
  IDs 11, 13, 14 and 15. Before any reconnect a screenshot and a
  stream of each screen showed its own colour, with the bytes
  exactly as shown (255, 0, 0 and 0, 0, 255). After each of the three
  reconnects: a screenshot of A showed red and one of B blue; a new
  stream on A delivered blue, B's picture; a new stream on B delivered
  blue. After reconnects 1 and 2, a further stream on A, started once
  those were stopped, also delivered blue. The screenshots' colour
  space had no name. A
  stream running on B from the start delivered blue throughout and
  never stopped. Each time A went, the stream on A stopped with error
  -3815 of ScreenCaptureKit's stream error domain, 0.16, 0.12 and
  0.24 s after. **Tried again** (2026-11-15, 13 runs, from the owner's
  terminal). A created before B and A created again: a new stream on A
  delivered B's picture in 8 runs, in 11 of 11 reconnects. B created
  before A: right in 3 runs, 7 of 7 reconnects. A alone: right in 1
  run, 2 of 2. In the faulty state a new stream on B was right, and a
  screenshot of A through its screen filter
  (`captureSampleBuffer`) was also wrong, 11 of 11, unlike the run of
  2026-11-13. Failed ways around it: fetching the shareable content
  again at once, after 1, 3 and 5 s and every 5 s to about 19 s; a
  filter that includes A's window (transparent black, B's rectangle);
  an `excludingApplications` filter; stopping all streams and
  restarting; a new serial number for each creation (2 reconnects); a
  fresh second process (1 run: the system holds the fault); switching
  A's mode and back; creating B again (1 run: A was right, and the new
  B then showed A's picture). What works: `SCScreenshotManager.captureImage(in:)`
  with `CGDisplayBounds` of A gave A's picture in 3 of 3 faulty runs
  (BGRA 0, 0, 255, 255); its cost at 30 frames per second is
  UNVERIFIED. What shows it: `SCStreamFrameInfo.screenRect` was the
  other screen's rectangle in every reconnect that showed the other
  screen's picture (11 of 11, one frame sampled per check), and with
  a filter that includes A's window the frame was transparent, at the
  other screen's rectangle; once a frame with a matching `screenRect`
  was black (cause not known, perhaps not yet painted). Not tried: the Mac's own screens (BetterDisplay can
  switch one off and on), three or more screens, a mode switch on B,
  the cause;
- an aggregate device created and removed is seen as an audio input
  appearing and vanishing; a change of its members arrives as a channel
  count change; it needs no administrator;
- BlackHole's drivers install side by side and each carries its own
  tone;
- BetterDisplay's command line returns only when the change is done;
- a tone played into the loopback device is, or is not, in system
  audio and on the speakers. **Tried** for the system audio
  (2026-11-19, two runs on the owner's Mac, macOS 27.2.1): the system
  audio's file held only zeros while the driver played the test tone
  into BlackHole, so it is not in the system audio; the speakers were
  not checked;
- the time can be put back after the clock scenario set: a clock that
  counts sleep and that setting the time does not move, and setting
  the time from the driver.

## Open questions

- Which items of the v1 gate these tests replace.
- Does the owner's BetterDisplay HiDPI mode work through virtual
  screens ("What research found for the recorder")?

## Sources

Research of 2026-11-13; the most load-bearing ones:

- Virtual screens: [go-macos/virtualdisplay](https://pkg.go.dev/github.com/go-macos/virtualdisplay)
  (measured on macOS 26), [Chromium's virtual screen utility](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_util_mac.mm),
  [Electron's multi-monitor testing](https://electronjs.org/docs/latest/development/multi-monitor-testing).
- The wrong-screen fault: [Apple developer forums 786829](https://developer.apple.com/forums/thread/786829),
  [BetterDisplay issue 4405](https://github.com/waydabber/BetterDisplay/issues/4405).
- BetterDisplay's command line: [reference](https://betterdisplay.pro/guide/integration/cli-reference/).
- Audio inputs: [BlackHole](https://github.com/ExistentialAudio/BlackHole),
  [Mozilla cubeb's device change tests](https://github.com/mozilla/cubeb-coreaudio-rs/blob/trailblazer/src/backend/tests/device_change.rs),
  [Apple developer forums 812061](https://developer.apple.com/forums/thread/812061)
  (a test audio driver).
- Permissions and signing: [Apple developer forums 795739](https://developer.apple.com/forums/thread/795739),
  [807898](https://developer.apple.com/forums/thread/807898).
- Virtual machines: [Parallels' limits for macOS guests](https://kb.parallels.com/en/128867),
  [Apple developer forums 825515](https://developer.apple.com/forums/thread/825515).
- Self-hosted runners: [GitHub's security guidance](https://docs.github.com/en/actions/reference/security/secure-use).
