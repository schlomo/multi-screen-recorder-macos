# End-to-end tests

**Status: proposed, not signed off, nothing built or tried.** The owner
asked for this document (2026-11-13) after ruling that automated
end-to-end tests run on the owner's Mac first (D34). It stays on its
work branch until the owner signs it off; merging it is that sign-off,
and the same change then records it in the decisions log.

Every statement about what a tool or macOS does comes from web
research of 2026-11-13 (sources at the end) and is UNVERIFIED on this
project's Mac until the experiments under "Unknowns" have run.

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

**Three parts, kept apart:**

1. **Device helper,** a Swift executable in the package, never in the
   app bundle. It makes the events and the known picture and sound.
   Each virtual display lives in a process of its own, so ending the
   process disconnects it.
2. **Driver,** a Python program (standard library only, as the scripts
   of D32): reads a scenario, starts the helper and the recorder,
   fires the events on a clock, stops the recorder, runs the
   assertions, prints one line per failed assertion and exits non-zero
   on any. It requires `ffprobe` and `ffmpeg` on the `PATH` up front.
3. **Assertions,** part of the driver. They read the recording folder,
   as a person would have it afterwards, and what the driver itself
   saw: the recorder's exit status and messages, and the crash marker
   under the scratch `HOME`.

**Each assertion is first seen failing** against a file or folder
broken on purpose (a frame removed, a track swapped, a file missing
from the manifest), and those broken samples stay as the assertions'
own tests in `scripts/test`.

**The Mac's own devices do not leak into the result.** The driver
lists displays and audio inputs before a run and asserts exactly only
on the virtual ones it adds; for the Mac's own it asserts only that
their files are readable and listed.

**Started by a person, in that person's session.** A run adds
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
- **Sound:** a virtual audio input carries a tone and a click once a
  second, played into it by the helper.

Limits of the sound, which the assertions respect: one loopback device
(BlackHole) gives one signal, so several virtual audio inputs built on
it carry the same tone and cannot be told apart by content; the Mac's
own microphone records the room and is asserted only as "not silent";
whether a tone played into a loopback device also lands in system
audio is unknown. Telling several audio inputs apart by content needs
a test audio driver that generates a tone per device; see "Unknowns".

### Error classes

| Error class | Events that provoke it | Assertions that detect it |
|---|---|---|
| **A file is lost or unreadable** | kill the recorder (`kill -9`), also while it finalizes; full disk; output folder made unwritable or its volume removed; sleep; a display or audio input vanishing | every file in the recording folder opens and decodes to its last complete fragment (fragments of 2 s, [recorder.md](recorder.md)); nothing recorded more than one fragment before the event is missing |
| **Wrong picture** | displays connect and reconnect (a reported macOS fault then delivers another display's picture), mirroring, main display change, many displays at once | the identity decoded from each display file is that file's display; no black stretch; the pattern's counter keeps advancing |
| **Wrong sound** | audio inputs appear and vanish, default microphone changes, channel count and sample rate change | a virtual audio input's audio file holds the tone, on every track; no silent stretch in it; each guide track is present in every display file |
| **Wrong timing** | still picture for 60 s, load on the processor, a stalled recorder (`SIGSTOP`, then `SIGCONT`), long random runs | every display file has 30 frames for each second of its length; the time shown in each recorded frame is that frame's time within one frame (a still or late picture is repeated by design, D11, D21, so the counter may repeat but never runs backwards or ahead); the manifest's `framesRepeatedForLateness` matches the repeats seen; the timecode of every file matches its start; the click sits at the frame that shows its time |
| **A change handled wrongly** | every display and audio event below | the right file ends and the right one begins; a frame size change leaves under one second without picture (D30); the audio files have no gap across it; a display keeps its number; an unchanged frame size continues the file |
| **The recording manifest is wrong** | all of them | `recording.json` lists exactly the files in the folder; each event the recorder design defines appears once, in order, at the scenario's time; its state is right after Stop and after a kill |
| **Resources run out** | a small disk image as output folder, filled during a recording, then given room again; processor and memory pressure; more displays than the Mac has hardware encoder sessions | what was written stays readable; the recorder keeps retrying and continues in new files once there is room (D14); nothing is discarded |
| **The process ends badly** | `kill -9`, `SIGTERM`, a second recording into the same recording folder, a recording into another folder in parallel (D20) | the crash marker is left and the next start reports the unfinished recording; the second recording into the same folder is refused; parallel recordings do not disturb each other |
| **Settings and start** | old, damaged and empty settings files; auto mode on and off (D34) | a settings file is never refused; the recording folder holds what the settings ask for |

### Events

| Event | How it is made | Needs |
|---|---|---|
| Display connects, disconnects | the helper creates a virtual display through Apple's private `CGVirtualDisplay` interface; ending its process removes it | private interface |
| Frame size changes, HiDPI | the helper replaces a virtual display by one of another size (a mode switch on a virtual display is reported to leave it unremovable); on a real display, a mode change through the public interface | |
| Mirroring, arrangement, main display | the helper, through the public display configuration interface | |
| Rotation; a real display switched off and on | BetterDisplay's command line | BetterDisplay Pro, a paid licence (the owner: "I have BetterDisplay Pro if it helps we can use it"); scenarios using it are skipped, and say so, where it is absent |
| Audio input appears, vanishes, changes its channel count | the helper creates and removes an aggregate device around BlackHole through the public CoreAudio interface | BlackHole installed once (administrator) |
| Sample rate, input volume | the helper sets them on BlackHole | |
| Default microphone changes | the helper, through the public CoreAudio interface | |
| Display sleep, sleep and wake | `pmset` | wake is reported unreliable |
| Kill, stall, full disk, unwritable folder, volume removed, load | `kill`, a small disk image, `chmod`, `memory_pressure` | |
| A real USB microphone is pulled; the clock, the date or the time zone changes | the helper captures the USB device so the Mac loses it; the system clock is set | administrator; a separate scenario set, never in the default run; the USB capture is unproven on macOS 26 |

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

The two permissions are granted once by a person. Two things are open
and decide how a run is started:

- **Who holds them.** A `msr` started from a terminal is attributed to
  the terminal app ([recorder.md](recorder.md), "Command line"), so the
  terminal app holds Screen Recording and Microphone, and so does
  every program started in it, an agent's shell included. That is a
  security cost. Proposed: the driver starts the recorder through
  macOS (`open`, with the arguments for `record`), so that the app
  holds the permissions and the terminal needs none. Whether that
  attribution works is an experiment.
- **Whether they survive a rebuild.** With one signing certificate they
  should (D5), which D5 itself marks unverified until the owner's check
  on PR #1. A build signed ad hoc is reported to lose them with every
  rebuild, so a run always uses a build signed with the certificate.

## What research found for the recorder

For the recorder PR's design, each UNVERIFIED here:

- **ScreenCaptureKit can deliver the wrong display** after a virtual
  display reconnects when two or more exist (Apple feedback
  FB17797423; BetterDisplay works around it). The recorder should
  verify which display a stream delivers. Whether the owner's
  BetterDisplay HiDPI mode works through virtual screens, and so meets
  this fault in daily use, is a question for the owner.
- **A plain executable no longer appears in the Screen Recording list**
  (macOS 26.1, called a bug by Apple); see "Permissions".
- **A build signed ad hoc loses its permissions with every rebuild;**
  see "Permissions".

## Safeguards for the person's session

- A run records the person's real displays and microphone too. Its
  recording folders live in a scratch folder, are deleted after a run
  that passes, and kept after one that fails, which the driver says
  with the path.
- Before a run the driver writes the display arrangement, the default
  microphone and the default output to a state file; it restores them
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
skeleton PR; the pattern decoder is the uncertain part.

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
- **`displayplacer` and `SwitchAudioSource`:** the helper does what
  they do through the same public interfaces, with two tools fewer to
  install.

## Accepted risks

- `CGVirtualDisplay` is private: an update of macOS can break the
  helper. It is test equipment only and never ships in the app.
- Fast connect and disconnect cycles are reported flaky in macOS
  itself; a failure there must be told apart from a recorder fault,
  and a flake is root-caused, never retried blindly.

## Unknowns, each settled by a small experiment

Throwaway code, run by the owner or on the owner's go-ahead, before
this design is built:

- a virtual display appears in ScreenCaptureKit and delivers a real
  picture;
- two virtual displays, one reconnects: does the wrong-display fault
  show on this Mac;
- an aggregate device created and removed is seen as an audio input
  appearing and vanishing; a change of its members arrives as a channel
  count change; it needs no administrator;
- a recorder started through `open` is attributed to the app, not the
  terminal;
- BetterDisplay's command line returns only when the change is done;
- a tone played into the loopback device is, or is not, in system
  audio and on the speakers.

## Open questions

- Is the driver Python, or part of the Swift test suite with a tag?
  Proposed: Python, beside the other scripts.
- The folder: [recorder.md](recorder.md) names `scripts/acceptance/`,
  while "acceptance tests" is what the v1 gate calls a person's
  checks. Proposed: `scripts/end-to-end-test` for the driver, and
  "acceptance test" kept for the v1 gate.
- Which items of the v1 gate these tests replace.
- A test audio driver (an AudioServerPlugIn installed once by an
  administrator) that presents several audio inputs, each with its own
  tone: worth building, or is one virtual audio input enough?
- May a run change the default microphone and add displays in the
  person's own session, or does it need a second user account (no
  source says ScreenCaptureKit works in a session that is not in
  front)?

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
