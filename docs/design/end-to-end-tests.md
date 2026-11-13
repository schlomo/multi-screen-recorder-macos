# End-to-end tests

**Status: proposed, not signed off, nothing built.** The owner asked
for this document (2026-11-13) after ruling that automated end-to-end
tests run on the owner's Mac first (D34), and has since ruled on five
of its open questions (D35). It stays on its work branch until the
owner signs it off; merging it is that sign-off. The same change then
records the sign-off in the decisions log and removes "proposed" here,
in [recorder.md](recorder.md) "Tests", in the backlog's item and in
the glossary.

Every statement about what a tool or macOS does comes from web
research of 2026-11-13 (sources at the end) and is UNVERIFIED on this
project's Mac, except what "Unknowns" marks as tried.

## What this covers

How the recorder is tested as a whole, automatically, on one Mac:
displays and audio inputs change, things fail, and a program examines
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

## The proposed design

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
`scripts/end-to-end-test` is a few lines that build and start it;
`scripts/` holds scripts only, so the tests' code and data live in the
package (D35).

1. **Device helper.** It makes the events and the known picture and
   sound. Each virtual display lives in a process of its own, a
   subcommand of the executable, so ending the process disconnects it.
2. **Driver:** reads a scenario, starts the helper and the recorder,
   fires the events on a clock, stops the recorder, runs the
   assertions, prints one line per failed assertion and exits non-zero
   on any. It requires `ffprobe` and `ffmpeg` on the `PATH` up front.
3. **Assertions,** part of the driver. They read the recording folder,
   as a person would have it afterwards, and what the driver itself
   saw: the recorder's exit status and messages, and the crash marker
   under the scratch `HOME`. They read the recording manifest and the
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
lists displays and audio inputs before a run and asserts exactly only
on the virtual ones it adds; for the Mac's own displays and audio
inputs it asserts only that their files are readable and listed.

**Started by a person, in that person's own session** (D35). A run adds
displays, covers every display with a pattern and changes the default
microphone: the Mac cannot be used meanwhile. An agent never starts
one unasked (`AGENTS.md`, "Facts that bite"). Not part of
`scripts/test`, not part of the pipeline.

### Known content

An assertion can only detect a wrong picture or sound if it knows what
was shown and played.

- **Picture:** the helper shows a full-screen pattern on every display:
  blocks that encode the display's identity, a frame counter and the
  time in milliseconds, large enough to survive scaling and HEVC.
  The blocks are black and white and are read by brightness, because
  HEVC stores colour at a lower resolution than brightness. Tried (see
  "Unknowns"): the menu bar of macOS covers the top of a virtual
  display, so the blocks stay below it.
  Colour is asserted on its own. The owner: "shouldn't we also check
  colors to ensure that no problem creeps in with colors? After all,
  all screen content is colored". So the pattern also carries large
  colour fields (red, green, blue, their mixes) and grey steps from
  black to white, and an assertion compares them, decoded from the
  display file, with what was shown. That detects a wrong or missing
  colour space tag and a wrong range, where black comes back grey and
  white dull (always SDR with the colour space tagged, D24). The
  tolerance is calibrated on the first recordings.
- **Sound:** a virtual audio input carries a tone and a click once a
  second, played into it by the helper.

Limits of the sound, which the assertions respect: one loopback device
(BlackHole) gives one signal, so several virtual audio inputs built on
it carry the same tone and cannot be told apart by content; the Mac's
own microphone records the room and is asserted only as "not silent";
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
| **A file is lost or unreadable** | kill the recorder (`kill -9`), also while it finalizes; full disk; output folder made unwritable or its volume removed; sleep; a display or audio input vanishing | every file in the recording folder opens and decodes to its last complete fragment (fragments of 2 s, [recorder.md](recorder.md)); nothing recorded more than one fragment before the event is missing |
| **Wrong picture** | displays connect and reconnect (a reported macOS fault then delivers another display's picture), mirroring, main display change, many displays at once | the identity decoded from each display file is that file's display; no black stretch; the pattern's counter keeps advancing; the colour fields and grey steps come back as shown, within a tolerance, black as black and white as white |
| **Wrong sound** | audio inputs appear and vanish, default microphone changes, channel count and sample rate change | a virtual audio input's audio file holds the tone, on every track; no silent stretch in it; each guide track is present in every display file |
| **Wrong timing** | still picture for 60 s, load on the processor, a stalled recorder (`SIGSTOP`, then `SIGCONT`), long random runs | every display file has 30 frames for each second of its length; the time shown in each recorded frame is that frame's time within one frame (a still or late picture is repeated by design, D11, D21, so the counter may repeat but never runs backwards or ahead); the timecode of every file matches its start; the click sits at the frame that shows its time |
| **A change handled wrongly** | every display and audio event below | the right file ends and the right one begins; a frame size change leaves under one second without picture (D30); the audio files have no gap across it; a display keeps its number; an unchanged frame size continues the file |
| **The recording manifest is wrong** | all of them | `recording.json` lists exactly the files in the folder; each event the recorder design defines appears once, in order, at the scenario's time; its state is right after Stop and after a kill |
| **Resources run out** | a small disk image as output folder, filled during a recording, then given room again; processor and memory pressure; more displays than the Mac has hardware encoder sessions | what was written stays readable; the recorder keeps retrying and continues in new files once there is room (D14); nothing is discarded |
| **The process ends badly** | `kill -9`, `SIGTERM`, a second recording into the same recording folder, a recording into another folder in parallel (D20) | the crash marker is left and the next start reports the unfinished recording; the second recording into the same folder is refused; parallel recordings do not disturb each other |
| **Settings and start** | old, damaged and empty settings files; auto mode on and off (D34) | a settings file is never refused; the recording folder holds what the settings ask for |

### Events

| Event | How it is made | Needs |
|---|---|---|
| Display connects, disconnects | the helper creates a virtual display through Apple's private `CGVirtualDisplay` interface; ending its process removes it | private interface |
| Frame size changes, HiDPI | the helper replaces a virtual display by one of another size (a mode switch on a virtual display is reported to leave it unremovable); on one of the Mac's own displays, a mode change through the public interface | |
| Mirroring, arrangement, main display | the helper, through the public display configuration interface | |
| Rotation; one of the Mac's own displays switched off and on | BetterDisplay's command line | BetterDisplay Pro, a paid licence (the owner: "I have BetterDisplay Pro if it helps we can use it"); a scenario set of its own, asked for by name, which stops with an error where BetterDisplay is missing |
| Audio input appears, vanishes, changes its channel count | the helper creates and removes an aggregate device around BlackHole through the public CoreAudio interface | BlackHole installed once (administrator) |
| Sample rate, input volume | the helper sets them on BlackHole | |
| Default microphone changes | the helper, through the public CoreAudio interface | |
| Display sleep; sleep and wake | `pmset` | display sleep locks the Mac where macOS is set to ask for the password after it; wake is reported unreliable, and the Mac may wake locked; a locked Mac needs the person: a scenario set of its own, asked for by name, with the person present |
| Kill, stall, full disk, unwritable folder, volume removed, load | `kill`, a small disk image, `chmod`, `memory_pressure` | |
| A real USB microphone is pulled; the clock, the date or the time zone changes | the helper captures the USB device so the Mac loses it; the system clock is set | administrator; a scenario set of its own, asked for by name; the USB capture is unproven on macOS 26 |

### What these tests cannot do

Their output names what a run did not cover. These stay with a person
(the v1 gate):

- the app itself: Start in the window, the Dock icon, Stop, Quit,
  finalizing at logout (the tests drive `msr record` only);
- closing the lid, a cable pulled from the Mac's own port, a real
  display's own behaviour (HDR, variable refresh rate);
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

A virtual display is drawn by the same window server and captured
through the same ScreenCaptureKit as a real one, so these tests should
show how the recorder handles a change. That removing a virtual
display looks to the recorder like pulling a cable is an assumption,
UNVERIFIED.

### What the recorder design must provide

The assertions need these, and [recorder.md](recorder.md) does not
have them yet; they go into the recorder PR's design:

- an expected result, and a manifest event, for: a display connecting,
  mirroring switched on and off, the main display changing, the default
  microphone changing, sleep and wake;
- the gap allowed in a display file's guide tracks across a frame size
  change;
- on the command line, which displays and audio inputs a recording
  will record, as the window's tables show it (D13: every feature in
  both front ends);
- with auto mode off, a way to choose audio inputs (open in D34):
  without it a virtual audio input is recorded only while it is the
  default microphone.

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

- **ScreenCaptureKit delivers the wrong display** after a virtual
  display reconnects when two exist (reported as Apple feedback
  FB17797423; BetterDisplay is said to work around it). Tried, and it
  shows on the owner's Mac (see "Unknowns"): after display A came
  back, every new stream on A delivered display B's picture, in three
  reconnects of three, while a screenshot of A through the same
  ScreenCaptureKit display was right. The recorder must verify which
  display a stream delivers, and its design needs a way to get the
  right one, which no experiment has found yet. Not tried: whether
  this happens with the Mac's own displays or only with virtual ones.
  Whether the owner's BetterDisplay HiDPI mode works through virtual
  screens, and so meets this fault in daily use, is a question for
  the owner.
- **A stream is told when its display goes.** Tried (see "Unknowns"):
  the stream on a virtual display stopped with error -3815 of
  ScreenCaptureKit's stream error domain 0.12 to 0.24 s after the
  display went, in three cases of three; a stream on the other display
  kept delivering throughout.
- **macOS's display ID is not a display's identity.** Tried (see
  "Unknowns"): the same virtual display got a new display ID each time
  it was created. A display that comes back during a recording may
  so have another display ID; the recorder's stable identity for a
  display (`backlog.md`, recorder PR) cannot be the display ID alone.
- **AppKit may not list a new screen to a program that does not handle
  the app's events.** Tried (see "Unknowns"): not listed within 5 s
  without, listed after about a second with. The recorder lists
  displays through AppKit today; `msr record` from the command line
  must be shown to see a display that connects during a recording.
- **A plain executable no longer appears in the Screen Recording list**
  (macOS 26.1, called a bug by Apple); see "Permissions".
- **A build signed ad hoc is reported to lose its permissions with
  every rebuild.** That concerns the app started from Finder, which
  holds its own permissions (D5), not a run of these tests.

## Safeguards for the person's session

- A run records the Mac's own displays and audio inputs too. Its
  recording folders live in a scratch folder, are deleted after a run
  that passes, and kept after one that fails, which the driver says
  with the path.
- Before a run the driver writes the display arrangement, the default
  microphone, the default output and, for the scenario set that
  changes them, the time zone and whether the time is set
  automatically, to a state file; it restores them
  after the run, after a failure and after Ctrl-C. If the driver
  itself is killed, `restore` as its only argument does the same from
  the state file, and removes every virtual display and aggregate
  device carrying the tests' name prefix (an aggregate device may
  outlive the helper that made it).
- Virtual displays use a small fixed set of identities: macOS keeps an
  arrangement and a colour profile (owned by root, never removed) per
  identity.
- Nothing switches off the built-in display: a helper killed while
  holding it off is reported to leave it off until logout.
- Nothing sends keystrokes or asks for the person's password.
- Whether the tones are heard on the Mac's speakers is unknown; the
  helper plays them into the loopback device, not the default output.

## Cost

No money beyond BetterDisplay Pro, which the owner has. The named
scenarios should take minutes, combinations and random runs as long as
their time budget; the Mac is not usable during a run. Once: installing
BlackHole and `ffmpeg`. Building the helper, the driver and the first
scenarios is the larger cost, estimated at one PR the size of the
skeleton PR; the pattern decoder is the uncertain part. The pipeline
compiles and unit-tests the tests' code with every push, which adds to
its run time.

## Why not otherwise

- **A macOS virtual machine** (Parallels Desktop, Tart): the guest has
  one display, one sound device tied to the host's default microphone,
  no USB audio and no hardware HEVC encoder, so display changes need
  the same virtual displays as on the Mac itself, and the encoder under
  test is another one. It would give a clean start and permissions
  granted once in an image; the owner's Mac has both without it.
  Parallels adds nothing over free tools here.
- **GitHub's hosted runners:** deferred (`backlog.md`); permissions are
  granted there by writing into the permission database, which breaks
  with macOS versions.
- **A self-hosted runner on the owner's Mac:** GitHub advises against
  one for a public repository; a pull request could run code on the
  Mac.
- **Hardware** (switchable HDMI or USB hubs): real unplugging, at a
  price and with wiring; revisit if virtual displays prove too far
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
  `swift test` would then need displays, permissions and `ffmpeg` for
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
- The pipeline does not gate the self-test, which needs `ffmpeg` and
  runs on a Mac, before a run and when the driver changes. What it
  alone covers is whether an assertion still fails on real files
  broken on purpose; a change that breaks that is seen at the next
  run, not at the PR.

## Unknowns, each settled by a small experiment

Throwaway code, run by the owner or on the owner's go-ahead, before
this design is built:

- a virtual display appears in ScreenCaptureKit and delivers a real
  picture. **Tried** (2026-11-13, macOS 26.7.1, five runs as the
  owner's user without `sudo`: three from an app without Screen
  Recording, then two by the owner from an app that holds it).
  Observed in the first three: a virtual display of 1920 × 1080 was an active
  display 0.3 to 0.4 s after it was created, at the left of the main
  display; AppKit listed it as a screen about a second later in the
  run that handled the app's events, and not within 5 s in the two
  runs that did not; every run started with the Mac's two displays, so
  the virtual display of the run before was gone by then; macOS's
  display ID was 5, 6 and 7 in the three runs, though the program
  gave the display the same vendor, product and serial number each
  time. The capture part did not run in these: the program asks macOS
  whether Screen Recording is granted in the way that raises no
  prompt, and stopped. Observed in the owner's two runs (display ID 9
  and 10): ScreenCaptureKit listed three displays, the virtual one
  among them at 1920 × 1080; a screenshot of it showed the program's
  full-screen window, with the menu bar of macOS across the top; the
  window's magenta (sRGB 1, 0, 1) is in the saved screenshot exactly
  as shown, 255, 0, 255, tagged sRGB. The program itself printed
  1.00, 0.25, 1.00 for it: a fault in how the program read the pixel,
  not in the capture, and the first of the two runs stopped at it. In
  the second, a stream at 30 frames per second delivered
  150 buffers in 5 s, 63 of
  them complete frames, while the picture changed 50 times; the
  display was gone 0.11 s after the program released it. Not tried:
  two virtual displays at once, a mode change, a HiDPI mode;
- two virtual displays, one reconnects: does the wrong-display fault
  show on this Mac. **Tried, and it does** (2026-11-13, one run by the
  owner, from an app that holds Screen Recording). Display A showed
  red, display B blue; A was released and created again three times,
  with the same vendor, product and serial number, and got display
  IDs 11, 13, 14 and 15. Before any reconnect a screenshot and a
  stream of each display showed its own colour, with the bytes
  exactly as shown (255, 0, 0 and 0, 0, 255). After each of the three
  reconnects: a screenshot of A showed red and one of B blue; a new
  stream on A delivered blue, B's picture, as did a second new stream
  on A started a second later; a new stream on B delivered blue. A
  stream running on B from the start delivered blue throughout and
  never stopped. Each time A went, the stream on A stopped with error
  -3815 of ScreenCaptureKit's stream error domain, 0.16, 0.12 and
  0.24 s after. Not tried: more than one run, a longer wait before
  the new stream, the Mac's own displays, any way around the fault;
- an aggregate device created and removed is seen as an audio input
  appearing and vanishing; a change of its members arrives as a channel
  count change; it needs no administrator;
- BlackHole's drivers install side by side and each carries its own
  tone;
- BetterDisplay's command line returns only when the change is done;
- a tone played into the loopback device is, or is not, in system
  audio and on the speakers.

## Open questions

- Which items of the v1 gate these tests replace.
- Does the owner's BetterDisplay HiDPI mode work through virtual
  screens ("What research found for the recorder")?

## Sources

Research of 2026-11-13; the most load-bearing ones:

- Virtual displays: [go-macos/virtualdisplay](https://pkg.go.dev/github.com/go-macos/virtualdisplay)
  (measured on macOS 26), [Chromium's virtual display utility](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_util_mac.mm),
  [Electron's multi-monitor testing](https://electronjs.org/docs/latest/development/multi-monitor-testing).
- The wrong-display fault: [Apple developer forums 786829](https://developer.apple.com/forums/thread/786829),
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
