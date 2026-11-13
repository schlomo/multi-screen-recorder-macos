# End-to-end tests

**Status: proposed, not signed off, nothing built or tried.** The owner
asked for this document (2026-11-13) after ruling that automated
end-to-end tests run on the owner's Mac first (D34). Every statement
about what a tool or macOS does comes from web research of 2026-11-13
(sources at the end) and is UNVERIFIED on this project's Mac until the
experiments under "Steps" have run.

## What this covers

How the recorder is tested as a whole, automatically, on one Mac:
displays and audio inputs change, things fail, and a program checks
the files afterwards. What the recorder does is in
[recorder.md](recorder.md). The unit tests and the pipeline are in
[recorder.md](recorder.md) "Tests" and [delivery.md](delivery.md). What
a person still checks by hand is the v1 gate in
[backlog.md](../../backlog.md).

## The goal

The owner: "important that automated tests cover error classes to help
us cover more ground quickly than by manual testing".

So the tests are organised by **error class**: a kind of thing that
goes wrong with a recording. For each class there are events that
provoke it and checks that detect it. One run covers every class in
minutes; a person covers a handful of cases in an afternoon.

## The proposed design

**The recorder under test is the built app, as shipped.** A test starts
the bundled `msr record` with a scratch `HOME` and a scratch output
folder, and stops it the way a person does. The recorder has no test
mode and no test-only code path. The build is signed with the
project's signing certificate, so the two permissions, granted once by
a person, hold across rebuilds (D5).

**A test is a scenario:** a list of timed events while a recording
runs, followed by the checks. The events come from a small fixed
vocabulary (below). Because every check is an invariant that must hold
after any scenario, three kinds of scenario use the same code:

- **Named scenarios,** one per event and per error class, a few
  seconds each: the regression suite.
- **Combinations,** generated: every pair of events, in both orders
  and overlapping, because most failures need two things to happen
  close together.
- **Random runs:** a seeded random sequence of events for a chosen
  time (minutes to hours). A failure prints its seed, and the seed
  replays the same sequence. This is what covers ground no one thought
  of.

**Three parts, kept apart:**

1. **Device helper,** a Swift executable in the package, never in the
   app bundle. It makes the events: virtual displays, virtual audio
   inputs, known picture and known sound. Each virtual display lives
   in a process of its own, so ending the process disconnects it.
2. **Driver,** a Python program (standard library only, as the scripts
   of D32): reads a scenario, starts the helper and the recorder,
   fires the events on a clock, stops, runs the checks, prints one
   line per failed check and exits non-zero on any.
3. **Checks,** part of the driver: they read only what a person would
   have afterwards, the recording folder, with `ffprobe` and `ffmpeg`
   from the `PATH`.

**Started by a person, in that person's session.** A run moves windows,
adds displays and changes the default microphone for its duration. An
agent never starts one unasked (`AGENTS.md`, "Facts that bite"). Not
part of `scripts/test`, not part of the pipeline.

### Known content

Checks can only detect a wrong picture or sound if they know what was
shown and played.

- **Picture:** the helper shows a full-screen pattern on every display:
  blocks that encode the display's identity, a frame counter and the
  time in milliseconds, large enough to survive scaling and HEVC. A
  check decodes them from the recorded frames.
- **Sound:** every virtual audio input gets its own tone frequency and
  a click once a second; system audio gets a third. A check finds
  which tone is in which audio track and where the clicks are.

### Error classes

| Error class | Events that provoke it | Checks that detect it |
|---|---|---|
| **A file is lost or unreadable** | kill the recorder (`kill -9`), full disk, output volume removed, sleep, a display or audio input vanishing | every file in the recording folder opens and decodes to its last complete fragment; nothing recorded before the event is missing |
| **Wrong picture** | displays connect and reconnect (a known macOS fault then delivers another display's picture), mirroring, main display change | the identity decoded from each display file is that file's display; no black or frozen stretch while the counter was running |
| **Wrong sound** | audio inputs appear and vanish, default microphone changes, channel count and sample rate change | each audio track holds its own input's tone and no other; no silent stretch; the "Microphones" guide track holds the microphones, the "System audio" one the system audio |
| **Wrong timing** | still picture for 60 s, load on the processor, long random runs | 30 frames a second with none missing or doubled (from the frame counter); the timecode of every file matches its start; picture and click line up within one frame; clicks an hour apart are an hour apart |
| **A change handled wrongly** | every display and audio event below | the right file ends and the right one begins; a frame size change leaves under one second without picture and none without sound (D30); a display keeps its number; an unchanged frame size continues the file |
| **The recording manifest is wrong** | all of them | `recording.json` lists exactly the files in the folder; its events match the scenario's events in order and time; its state is right after Stop and after a kill |
| **Resources run out** | small disk image as output folder filled during a recording; processor and memory pressure | the recording stops or warns as designed (D14), files stay readable, the exit status and the message say why |
| **The process ends badly** | `kill -9`, `SIGTERM`, a second recording into the same folder, a recording into another folder in parallel (D20) | crash marker left and found; the next start reports the unfinished recording; parallel recordings do not disturb each other |
| **Settings and start** | old, damaged and empty settings files; auto mode on and off (D34) | what `msr list` says will be recorded is what the recording folder holds; a settings file is never refused |

### Events

| Event | How it is made | Needs |
|---|---|---|
| Display connects, disconnects | the helper creates a virtual display through Apple's private `CGVirtualDisplay` interface; ending its process removes it | private interface |
| Frame size changes, HiDPI | the helper replaces a virtual display by one of another size (a mode switch on a virtual display leaves it unremovable); on a real display, a mode change through the public interface | |
| Mirroring, arrangement, main display | the helper, through the public display configuration interface | |
| Rotation; a real display switched off and on | BetterDisplay's command line | BetterDisplay Pro (the owner has it) |
| Audio input appears, vanishes, changes its channel count | the helper creates and removes an aggregate device around BlackHole through the public CoreAudio interface | BlackHole installed once (administrator) |
| Sample rate, input volume | the helper sets them on BlackHole | |
| Default microphone changes | the helper, through the public CoreAudio interface | |
| A real USB microphone is pulled | the helper, run as administrator, captures the USB device so the Mac loses it, and releases it | unproven on macOS 26; optional |
| Display sleep, sleep and wake, screen lock | `pmset`, a keystroke | wake is reported unreliable |
| Kill, full disk, volume removed, load | `kill`, a small disk image, `memory_pressure` | |

### What these tests cannot do

They say so in their output rather than implying coverage. These stay
with a person (the v1 gate):

- closing the lid, a cable pulled from the Mac's own port;
- a Bluetooth headset switching to call quality, an iPhone as
  microphone, AirPlay;
- the permission prompts of a first start, and the monthly "continue to
  allow" prompt of macOS, which nothing can suppress on a Mac without
  device management;
- whether an editor (DaVinci Resolve, Kdenlive) places the files right;
- a real display's own behaviour (HDR, variable refresh rate), since
  virtual displays have none.

Virtual displays are drawn by the same window server and captured by
the same ScreenCaptureKit, so what they prove about the recorder's
handling of changes holds; what they prove about real hardware does
not.

## What research found that changes the recorder

For the recorder PR's design, each UNVERIFIED here:

- **ScreenCaptureKit can deliver the wrong display** after a virtual
  display reconnects when two or more exist (Apple feedback
  FB17797423; BetterDisplay works around it). The owner uses
  BetterDisplay's virtual screens, so the recorder must check which
  display a stream delivers.
- **The first movie fragment must come after one second,** not Apple's
  default of ten, or a file killed early does not play.
- **A plain executable no longer appears in the Screen Recording list**
  (macOS 26.1, called a bug by Apple). `msr` started from a terminal is
  attributed to the terminal app, which then needs the permission.
- **A build signed ad hoc loses its permissions with every rebuild;**
  one signed with a certificate keeps them. Tests always run the build
  signed with the certificate.

## Safeguards for the person's session

- Virtual displays use a small fixed set of identities: macOS keeps an
  arrangement and a colour profile (owned by root, never removed) per
  identity.
- The driver records the display arrangement, the default microphone
  and the default output before a run and restores them after it, also
  after a failure or Ctrl-C; ending the helper removes every virtual
  display and aggregate device.
- Nothing switches off the built-in display: a helper killed while
  holding it off leaves it off until logout.
- A run that needs administrator rights (the USB capture) is a
  separate scenario set, never part of the default run.

## Cost

Nothing is paid for. A default run of the named scenarios should take
minutes of the Mac's time, during which the person cannot use it
comfortably; random runs take as long as asked. Once: installing
BlackHole and `ffmpeg`, about 100 MB. Building the helper, the driver
and the first scenarios is the larger cost, estimated at one PR the
size of the skeleton PR; the pattern decoder is the uncertain part.

## Steps

1. **Experiments,** each a few lines of throwaway code, run by the
   owner or on the owner's go-ahead, before anything is designed
   further:
   - a virtual display appears in ScreenCaptureKit and delivers a real
     picture;
   - two virtual displays, one reconnects: does the wrong-display fault
     show on this Mac;
   - an aggregate device created and removed: is it seen as an audio
     input appearing and vanishing, and does a change of its members
     arrive as a channel count change;
   - BetterDisplay's command line: does a command return only when the
     change is done.
2. **With the recorder PR:** the helper with virtual displays and the
   pattern, the driver, the checks for lost files, the manifest and
   changes handled wrongly, and the named scenarios for displays and
   for `kill -9`.
3. **After it:** virtual audio inputs and the sound checks; then
   combinations and random runs; then resources and timing over an
   hour.

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

## Accepted risks

- `CGVirtualDisplay` is private: an update of macOS can break the
  helper. It is test equipment only and never ships in the app.
- Fast connect and disconnect cycles are reported flaky in macOS
  itself; a failure there must be told apart from a recorder fault,
  and a flake is root-caused, never retried blindly.
- BlackHole is licensed under GPL-3; the tests use it as an installed
  program and ship nothing of it [the architect's reading].

## Open questions

- Is the driver Python, or part of the Swift test suite with a tag?
  Proposed: Python, beside the other scripts.
- The folder: [recorder.md](recorder.md) names `scripts/acceptance/`,
  while "acceptance tests" is what the v1 gate calls a person's checks.
  Proposed: `scripts/end-to-end-test` for the driver, "end-to-end
  test" in the glossary, "acceptance test" kept for the v1 gate.
- Which checks of the v1 gate these tests replace, and which stay with
  a person.
- Whether a test may change the default microphone and add displays in
  the person's session at all, or needs a second user account (no
  source says ScreenCaptureKit works in a session that is not in
  front).

## Sources

Research of 2026-11-13; the most load-bearing ones:

- Virtual displays: [go-macos/virtualdisplay](https://pkg.go.dev/github.com/go-macos/virtualdisplay)
  (measured on macOS 26), [Chromium's virtual display utility](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_util_mac.mm),
  [Electron's multi-monitor testing](https://electronjs.org/docs/latest/development/multi-monitor-testing).
- The wrong-display fault: [Apple developer forums 786829](https://developer.apple.com/forums/thread/786829),
  [BetterDisplay issue 4405](https://github.com/waydabber/BetterDisplay/issues/4405).
- BetterDisplay's command line: [reference](https://betterdisplay.pro/guide/integration/cli-reference/).
- Audio inputs: [BlackHole](https://github.com/ExistentialAudio/BlackHole),
  [Mozilla cubeb's device change tests](https://github.com/mozilla/cubeb-coreaudio-rs/blob/trailblazer/src/backend/tests/device_change.rs).
- Permissions and signing: [Apple developer forums 795739](https://developer.apple.com/forums/thread/795739),
  [807898](https://developer.apple.com/forums/thread/807898).
- Movie fragments: [`initialMovieFragmentInterval`](https://developer.apple.com/documentation/avfoundation/avassetwriter/initialmoviefragmentinterval).
- Virtual machines: [Parallels' limits for macOS guests](https://kb.parallels.com/en/128867),
  [Apple developer forums 825515](https://developer.apple.com/forums/thread/825515).
- Self-hosted runners: [GitHub's security guidance](https://docs.github.com/en/actions/reference/security/secure-use).
