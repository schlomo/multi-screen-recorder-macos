# Recorder, app and command line

## What this covers

Everything a person types, reads or finds on disk when using Multi
Screen Recorder, and how the recorder core produces it. Delivery
(pipeline, versions, signing) is in [delivery.md](delivery.md). Terms
are defined in [../glossary.md](../glossary.md).

Built so far: see "Build state" at the end. Values marked *data* are
starting points, calibrated at the v1 gate (`backlog.md`).

## Command line

The app's own executable is the command line (D19): with arguments it
runs headless, without arguments it is the app. One binary means one
code signature and one set of permissions.

`/Applications/Multi Screen Recorder.app/Contents/MacOS/msr`; the
README shows how to link it into a folder on the `PATH`. Started
through a symbolic link, `msr` re-executes itself at its fully resolved
real path with the same arguments, so it finds its app bundle (version,
signature); if that fails it exits 71 (`EX_OSERR`).

| Command | Does | Exit code |
|---|---|---|
| `msr list` | Shows displays, audio inputs and system audio | 0, 1 when the displays, the audio inputs or an audio input the settings record cannot be read |
| `msr check [flags]` | Runs the ready check and prints each item | 0 ready, 1 not ready |
| `msr record [flags] [--duration 1h30m]` | Ready check, then records until Ctrl-C, SIGTERM, SIGHUP or the duration; prints the recording folder at the start and a summary at the end | 0 ok, 1 not ready, 3 ended with an error |
| `msr settings [flags] [--save]` | Prints the effective settings as JSON; `--save` writes the flags into the settings file | 0 |
| `msr version` | Prints the version and commit | 0 |

A usage error (unknown command or flag, invalid value) prints a usage
message and exits 64, the convention of Swift Argument Parser. Every
command that reads the settings (all but `msr version`) exits 78
(`EX_CONFIG`) when the settings file cannot be used or `HOME` is not
set, so `msr check` exiting 1 means only "not ready".

Each flag is a settings key in kebab case and overrides it for this run
only:

| Flag | Values |
|---|---|
| `--resolution` | `native`, `4k`, `1440p`, `1200p`, `1080p`, `720p` |
| `--audio-mode` | `none`, `default-microphone` (`all-inputs` arrives with that feature) |
| `--system-audio` | `on`, `off` |
| `--output-folder` | a folder |
| `--required-recording-hours` | a number |
| `--low-disk-warning-minutes` | a number |

`msr list` prints:

```
Displays
  1  Built-in Retina Display   looks like 1728×1117, drawn at 3456×2234  records at 1670×1080
  2  LG HDR 4K                 3840×2160                                 records at 1920×1080
Audio inputs
  MacBook Pro Microphone (default), 1 channel
  RØDE Wireless GO II RX, 2 channels
System audio: available
```

A display is described by what macOS calls "looks like" (its size in
points) and its pixel size: `3840×2160` where both are equal, `looks
like 1728×1117, drawn at 3456×2234` where they differ (a HiDPI mode).
"records at" is the frame size from the pixel size.

`msr check` prints one line per item, `ok` or `FAIL`, a fix under each
failure, and `Ready.` or `Not ready.` last:

```
ok    Screen & System Audio Recording permission
ok    Microphone permission
ok    Displays: 2
ok    Audio: MacBook Pro Microphone (default), system audio
ok    Output folder: ~/Movies/Multi Screen Recorder
FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 4.3 GB needed for 2 hours
      Fix: free up space, or lower --required-recording-hours
Not ready.
```

Started from a terminal, macOS attributes the permissions to the
terminal app, not to Multi Screen Recorder; the README says so.

Seen on the owner's Mac (macOS 26.7.1): the microphone permission
allowed in the prompt counted at once; allowed later in System
Settings, it counted only after Multi Screen Recorder was quit and
started again, while the screen recording permission counted without
that. So the microphone item's fix line asks for the restart, and the
screen recording item's asks for it only if the permission is still
missing.

## Settings file

`~/Library/Application Support/Multi Screen Recorder/settings.json`,
written with the defaults on first start (D13, D19):

```json
{
  "resolution": "1080p",
  "audioMode": "default-microphone",
  "systemAudio": true,
  "outputFolder": "~/Movies/Multi Screen Recorder",
  "requiredRecordingHours": 2,
  "lowDiskWarningMinutes": 20
}
```

An unknown key or an invalid value stops with an error naming the key;
the app shows it and offers "Reset to defaults". A key appears only
once its feature exists (no `agc` key until AGC is built).

## Ready check

Items, in this order: the Screen & System Audio Recording permission,
the Microphone permission (unless the audio mode is `none`), the
displays (at least one, each readable), the chosen audio sources (each
audio input the audio mode records readable; another that cannot be
read does not count), the output folder, and free disk space in the output folder for
`requiredRecordingHours`.

- A permission that was never asked for is requested, so macOS shows
  its prompt; a denied one is reported with the System Settings path.
- The screen recording grant is proven, not just read: the check
  fetches the display list. The Microphone permission is read, and no
  microphone is opened (D36, waiting for the owner's yes): the app
  crashed inside macOS after the default microphone was unplugged
  (owner's Mac, 2026-11-13), and the capture session an earlier ready
  check opened for a moment on every run is the cause [ASSUMED]. With
  the permission granted but no microphone connected, the permission
  item passes and the audio item alone fails, with "no microphone".
  The audio inputs are read from Core Audio's device list, which
  creates no capture object; if that list, the default audio input or
  the name of an audio input cannot be read, the audio item fails with
  the reason and `msr list` stops with it.
- Output folder: the check creates it with its parents if it is
  missing, then writes and deletes a file in it; a failure names the
  path and the reason.
- Free disk space is measured on the output folder itself. Disk
  estimate, file by file at the encoding rates (*data*, see "Encoding"):
  a display file is its video, 1 GB per hour at 1080p scaled by the
  pixel count of its frame size, plus its guide tracks; an audio file is
  its tracks' bit rates. The item compares the total of every file the
  recording would write, for `requiredRecordingHours`, with the free
  space. For the devices of the `msr list` example at the defaults that
  is 2.2 GB per hour, 4.3 GB for 2 hours (the tables in "The app" show
  each file).
- One cause, one red item: when the output folder fails, or the
  displays, the audio inputs or an audio input the recording records
  cannot be read, the free disk space item is left out. With the audio
  mode `none`, audio inputs that cannot be read fail nothing.
- In the app the check runs when the window opens, when the app becomes
  active again (unless a check is still running), when a display
  comes, goes or changes, when an audio device comes or goes, when the
  default audio input changes, after every settings change, and on
  "Check again"; the tables of what will be recorded follow with it.
  Other changes of an audio input, such as its channels, show with the
  next check. A burst of changes gives one check, 0.3 s after the last
  (*data*). While a menu of the app or a modal panel (the folder
  chooser) is open or a control is dragged, the window's content does
  not change by itself; the check's result shows when it closes (that
  AppKit signals all three the way the app relies on is not observed
  yet, [ASSUMED] until the owner's re-test). The
  app crashed in AppKit's window layout, with a menu open, after HiDPI
  was switched; the cause is one of two candidates [ASSUMED], a change
  of the content under the menu or the window's sizing by layout
  constraints, and both are changed. It never
  runs while a recording is running, activation included (for the
  recorder PR to honour).

## Output on disk

One recording folder per recording, named by its local start time
(D20):

```
~/Movies/Multi Screen Recorder/2026-11-12 14.03.05/
  2026-11-12 14.03.05 Display 1 - Built-in Retina Display.mov
  2026-11-12 14.03.05 Display 2 - LG HDR 4K.mov
  2026-11-12 14.03.05 Microphone - MacBook Pro Microphone.mov
  2026-11-12 14.03.05 System audio.mov
  2026-11-12 14.27.41 Display 2 - LG HDR 4K.mov    ← back after a reconnect
  2026-11-12 14.41.10 Display 1 - Built-in Retina Display.mov    ← new frame size after a mode change
  recording.json
```

One file per source, each named by its own start time (D31): a display
file per display, an audio file per recorded audio input
(`<date time> Microphone - <device name>.mov`) and one for system audio
(`<date time> System audio.mov`). The manifest below lists exactly
these files.

Display 1 is the main display; the others are numbered left to right,
later arrivals in order of appearance. A display keeps its number for
the whole recording.

`recording.json` is the recording manifest, rewritten atomically on
every change:

```json
{
  "app": "Multi Screen Recorder 0.4.0 (a1b2c3d)",
  "state": "recording",
  "started": "2026-11-12T14:03:05.120+01:00",
  "settings": { "resolution": "1080p", "audioMode": "default-microphone", "systemAudio": true },
  "files": [
    {
      "name": "2026-11-12 14.03.05 Display 1 - Built-in Retina Display.mov",
      "display": "Built-in Retina Display",
      "frameSize": [1670, 1080],
      "start": 0.0,
      "end": 2285.0,
      "timecode": "14:03:05:04",
      "state": "finalized",
      "guideTracks": ["Microphones", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.03.05 Display 2 - LG HDR 4K.mov",
      "display": "LG HDR 4K",
      "frameSize": [1920, 1080],
      "start": 0.0,
      "end": 1446.2,
      "timecode": "14:03:05:04",
      "state": "finalized",
      "guideTracks": ["Microphones", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.03.05 Microphone - MacBook Pro Microphone.mov",
      "audioSource": "MacBook Pro Microphone",
      "channels": 1,
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording"
    },
    {
      "name": "2026-11-12 14.03.05 System audio.mov",
      "audioSource": "System audio",
      "channels": "stereo",
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording"
    },
    {
      "name": "2026-11-12 14.27.41 Display 2 - LG HDR 4K.mov",
      "display": "LG HDR 4K",
      "frameSize": [1920, 1080],
      "start": 1476.0,
      "end": null,
      "timecode": "14:27:41:04",
      "state": "recording",
      "guideTracks": ["Microphones", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.41.10 Display 1 - Built-in Retina Display.mov",
      "display": "Built-in Retina Display",
      "frameSize": [1662, 1080],
      "start": 2285.0,
      "end": null,
      "timecode": "14:41:10:04",
      "state": "recording",
      "guideTracks": ["Microphones", "System audio"],
      "framesRepeatedForLateness": 0
    }
  ],
  "events": [
    { "at": 1446.2, "event": "display disconnected", "display": "LG HDR 4K" },
    { "at": 2285.0, "event": "display frame size changed", "display": "Built-in Retina Display",
      "from": [1670, 1080], "to": [1662, 1080] }
  ]
}
```

`start`, `end` and `at` are seconds from the recording's start on the
shared clock. `state` is `recording`, `finalized` or `not finalized`.
An audio file's `channels` is the number of its mono tracks, or
`stereo` for system audio.

**Parallel recordings.** A recording claims its recording folder by
creating it and refuses if it already exists. Recordings into different
folders may run side by side (several `msr record`, or one beside the
app); the app itself runs one at a time.

**Crash marker.** While recording, a process keeps
`~/Library/Application Support/Multi Screen Recorder/active-recordings/<process id>.json`
naming its recording folder. On the next start, the app and `msr check`
report each marker whose process is gone ("Recording <folder> was not
finalized; its files are readable up to the last 2 seconds"), set that
manifest's state to `not finalized` and remove the marker.

## The app

- **Start:** a small window. At the top, a section "What will be
  recorded", built from the settings and the devices connected now and
  refreshed whenever the ready check runs (D33): two tables and a
  total line.
  - Displays: the number and name, "Looks like" (the size in points),
    "Drawn at" (the pixel size, shown also where both are equal),
    "Records at" (the frame size) and GB/h (the display file, its
    guide tracks included).
  - Audio: one row per audio input (its name, the default one marked
    "(default)", and its number of channels), then one row "System
    audio" (stereo), with GB/h (the audio file). A source not recorded
    is dimmed and shows "not recorded": every input with the audio
    mode `none`, every input but the default one with
    `default-microphone`, and the system audio row when it is off.
  - GB/h has one decimal; under 0.05 it shows "<0.1".
  - The total line: "Total <x> GB/h. <requiredRecordingHours> hours
    need <y> GB, <z> GB free.", without the free part while the free
    space is unknown (the ready check has not finished yet, or its
    output folder item failed).
  - Below, the output folder and "Recording continues when displays or
    audio sources change." If the displays cannot be read, that error
    stands in place of the Displays table; if the audio inputs cannot
    be read, "The audio inputs cannot be read: <reason>" stands above
    the Audio table, which then has the system audio row only; an audio
    input whose
    channels cannot be read shows "cannot be read" in the Channels
    column (and "unknown" GB/h if it is recorded). The total line
    appears only when the displays and every recorded audio input can
    be read. The ready check's items stay as they are.

  Then the recording resolution, audio mode, system audio and output
  folder; the ready check, with "Check again"; and Start. All green,
  the ready check is one line, "Ready to record", that expands on click
  to its items; any red item shows every item, with the fix under each
  red one. Start is disabled while the ready check fails. For the
  devices of the `msr list` example, the defaults and the free space
  of the `msr check` example, the section shows:

| Display | Looks like | Drawn at | Records at | GB/h |
|---|---|---|---|---|
| 1 Built-in Retina Display | 1728×1117 | 3456×2234 | 1670×1080 | 0.9 |
| 2 LG HDR 4K | 3840×2160 | 3840×2160 | 1920×1080 | 1.1 |

| Audio | Channels | GB/h |
|---|---|---|
| MacBook Pro Microphone (default) | 1 | 0.1 |
| RØDE Wireless GO II RX | 2 | not recorded |
| System audio | stereo | 0.1 |

Total 2.2 GB/h. 2 hours need 4.3 GB, 3.1 GB free.

- **Recording:** the window closes; the Dock icon shows a red badge with
  the elapsed minutes. Low disk space shows as a "!" badge and a
  bouncing Dock icon; no notification, which would need a third
  permission and is hidden by Focus modes.
- **Stop:** clicking the Dock icon or Quit asks "Stop recording?"
  [Stop] [Continue]. Stop finalizes, then reveals the recording folder
  in Finder. Logout and shutdown finalize without asking.
- **About:** version, licence, the purpose (the opening paragraph of the
  README, one string in the code), and a link to GitHub Issues that
  opens in the browser (D15, D26). The credit to the former upstream is
  in the README.

## How the recorder works

**Shared clock.** Everything runs on the host clock. The recording's
start t0 is one host time; every timestamp in every file is an offset
from t0.

**Constant 30 fps (D11, D21).** Per display, a ScreenCaptureKit stream
delivers complete frames when the screen changes; the newest is kept.
Tick k is at t0 + k/30 s, computed, never accumulated. Every tick
writes the newest frame captured before it, with exactly the tick's
timestamp: a frame appears at the first tick after its capture time,
never early. No tick is ever dropped: when the encoder is not ready, the
tick is written late with its correct timestamp and counted in
`framesRepeatedForLateness`.

**Timecode (D21, D31).** Every display file and every audio file
carries a timecode track: local time of day at 30 fps, non-drop. All
files share t0 and the tick grid, so their timecodes agree to the frame
and an editor can place every file, also a later-starting one, by
timecode. Unproven until the owner's first real recording: that
DaVinci Resolve reads the timecode of an audio-only `.mov`, and how
Kdenlive places the files (see "Open questions").

**Encoding (D21, values are *data*).** HEVC 8-bit through the hardware
encoder in `.mov`; keyframe every 2 s; quality-targeted variable bit
rate with a ceiling. Audio AAC-LC at 48 kHz: in an audio file
128 kbit/s per mono track and 192 kbit/s for the system audio's stereo
track; in a display file 64 kbit/s for the guide track "Microphones"
and 96 kbit/s for the guide track "System audio". Every display is
recorded in SDR, also one
in HDR mode, with its colour space tagged so editors show the colours
unchanged (D24). Apple's `SCRecordingOutput` is not used:
it writes a variable frame rate with its own track layout.

**Crash safety (D14, D21).** Files are written in fragments of 2 s
(*data*; independent of the keyframe interval), so a crash loses at
most the last 2 s.

**Frame size (D11, D30).** A display file's frame size is the
display's pixel size fitted into the recording resolution box:
proportions kept, never enlarged, each side rounded down to an even
number. The box turns with a portrait display (taller than wide): at
1080p a 2160×3840 display records at 1080×1920 (D25). While a
display's frame size stays the same, its file continues, whatever
else changed about the display. When the frame size changes, the display's current file ends and a new file starts at the
new frame size, like after a reconnect, with the event `display frame
size changed` (the display, the old and the new frame size) in the
manifest. At `native` the frame size is the pixel size rounded down
to even numbers, so nearly every pixel-size change is such a change; at
`1080p` a change from 3840×2160 to 5120×2880 is not (both give
1920×1080), while 3440×1440 to 1920×1080 is (1920×802 to 1920×1080).
The cost: a gap of under one second at the change in that display's
video and guide tracks only; the audio files and the other displays'
files continue unbroken; a display that flaps between modes makes many
short display files, each valid.

**Audio (D12, D22, D31).** One audio file per source, beside the
display files. Each recorded audio input gets its own audio file, a
`.mov` with one mono track per channel, named
`Microphone: <device>, channel <n>`; system audio gets its own audio
file with one stereo track. Both carry the timecode track. An audio
file starts on a tick of the shared grid, so its timecode is exact. An
audio input that appears starts its audio file then (event `audio
input connected`); one that disappears ends its file (event `audio
input disconnected`); one whose channel count changes ends its audio
file and starts a new one. System audio's file has the events `system
audio started` and `system audio stopped`. An audio file is never
padded with silence, and a display event never touches an audio file.
A failing audio stream and a full disk are handled for an audio file as
for a display file (below): the file ends, the stream is restarted
with the same back-off, and a new audio file starts once there is
room. For playback and waveform
sync, every display file also carries guide tracks: "Microphones", one
mono mix of all recorded microphone channels, unless the audio mode is
`none`; "System audio", stereo, unless system audio is off. The two are
never mixed together, and a source that is missing is silence in its
guide track. The microphone comes from an `AVCaptureSession` on the
default input (to be tried before it is built: the app crashed after
the microphone was unplugged, and the ready check's short-lived
capture sessions are the cause [ASSUMED], see "Ready check"); system audio from a ScreenCaptureKit stream of its own,
so a failing display stream never takes the audio with it. Buffers are
placed on the shared clock and written to the audio files and the
guide tracks of every open display file.

**Displays coming and going (D14).** A display that appears gets a
stream and a display file; one that vanishes has its file finalized. A
stream that fails finalizes its file and is restarted after 1 s,
backing off to 10 s (*data*), for as long as the display exists. Each
gap is an event in the manifest.

**Disk (D14).** Below the warning threshold: the warning. A writer that
fails on a full disk ends its file, readable up to the last fragment;
the recorder checks free space every 5 s and starts new display files
and audio files once there is room. Nothing written is ever deleted.

**Keep awake (D14).** A power assertion against idle system and
display sleep while recording.

## Code layout

```
Package.swift             Swift 6 language mode, macOS 26, arm64
Sources/RecorderLogic/    pure logic, Foundation only, fully unit-tested
Sources/RecorderCore/     ScreenCaptureKit, AVFoundation and Core Audio adapters
Sources/msr/              entry point: the command line and the app
Tests/RecorderLogicTests/ Swift Testing, as all tests
Tests/RecorderCoreTests/  the adapters that need no device or permission
Tests/CommandTests/       msr and the scripts in scripts/, run as commands
Resources/                Info.plist, entitlements
scripts/                  see delivery.md
```

Swift Package Manager and bundling scripts rather than an Xcode
project, whose project file cannot be reviewed by hand. One dependency:
Swift Argument Parser, Apple's own package for command lines.

## Tests

`scripts/test` runs the unit tests of `RecorderLogic`: the tick grid
(which frame lands on which tick, still periods of 60 s and more, late
ticks), geometry for every recording resolution and change case,
settings and flags and their errors, file naming, manifest states,
crash markers, the version, and the text of the examples in this
document, which the tests hold to the code. `RecorderCoreTests` test
the output folder probe against scratch folders, and that this Mac's
audio inputs can be read and a listener for their changes registered,
which needs no permission and shows no prompt, and that an action
waiting for the main run loop's default mode runs only there. The
window's refresh on device changes has no test yet (`backlog.md`,
recorder PR). `CommandTests` run
the built `msr` with a scratch `HOME` (`msr settings` and
`msr version`, which prompt for nothing; also through a symbolic link
into an app bundle), `scripts/version` in scratch git repositories and
`scripts/unpack-app` on scratch archives (some written byte by byte, as
no tar would write them from a file system), `scripts/sign-app` and
`scripts/smoke-test` on a scratch bundle, and
`scripts/publish-snapshot-release` against a stub `gh`;
`scripts/smoke-test` runs the built app's `msr` the same way in the
pipeline.
Capture itself cannot run in CI, which has
no way to grant the permissions [ASSUMED]; it is verified on a Mac with
`scripts/acceptance/`, which drives `msr record` and checks the files
with `ffprobe`, and by the v1 gate.

## Not covered, and rejected

- **Rust**, also as a core under a Swift shell: every framework call
  would be `unsafe` through generated bindings (D17).
- **One JSON file per display file** (the reference implementation):
  with a constant frame rate on a shared clock a file needs only its
  start offset.
- **A global "one recording at a time" lock:** folder claims allow
  parallel recordings at no extra cost (D20).
- **Mixing an input down to mono or stereo in its audio file:**
  channels may carry different people (D22); only the guide track
  "Microphones" is a mix, for playback and sync (D31).
- **A notification for low disk space:** see "The app".
- **Recording HDR displays as HDR:** files of mixed kinds on one
  timeline, larger files, and weak support outside DaVinci Resolve, for
  content that is rarely HDR (D24).
- **Sequenced after v0** (D18, `backlog.md`): audio mode `all-inputs`,
  AGC.
- **Every audio source in every display file** (D12): one audio file
  per source instead, with guide tracks in the display files (D31).
  Joining the files into one without re-encoding is deferred
  (`backlog.md`).
- **The command line driving the running app**, so a terminal needs no
  permissions of its own: deferred (`backlog.md`).

## Open questions

- Unproven until the owner's first real recording (D31): that DaVinci
  Resolve reads the timecode of an audio-only `.mov`, and how Kdenlive
  places the display files and audio files.
- What happens when the default microphone changes during a recording
  (the owner will rule).
- Whether `AVAssetWriter` writes a timecode track into an audio-only
  fragmented `.mov`.
- How drift between an audio device's clock and the tick grid is
  handled over hours.
- Two audio inputs with the same name.
- Characters in a device name that a file name cannot hold.
- The gain of the guide track "Microphones".

## Build state

Built (skeleton PR): `msr list`, `msr check`, `msr settings`,
`msr version`, the settings file, the ready check and the app window
with it ("What will be recorded", "Check again", Start
always disabled, "This build cannot record yet."), the About window,
the code layout above except `scripts/acceptance/`, and the tests of
settings, geometry, the disk estimate, the ready check, the output
folder probe, the audio input listing, "What will be recorded",
`msr list`, the frame size rule, the version, the exit codes and the scripts. The recorder PR builds the rest:
`msr record`, recording, the recording manifest, crash markers,
timecode, the Dock badge and Stop.

Details the design left open, as built and confirmed by the owner
(D25, D28): a key missing from the settings file takes its default; the
output folder must start with `/` or `~`; the two number settings must
be greater than 0; a settings file that cannot be used makes every
command that reads the settings exit 78. `msr version` prints the full
version string and the commit, such as `0.2.0-dev+a1b2c3d (a1b2c3d)`,
from the bundle's Info.plist keys `MSRVersion` and `MSRCommit`;
outside a bundle it prints `development build (not bundled)`. The
settings file is found through `HOME`. The disk estimate follows its
rule, file by file (4.3 GB in the `msr check` example above). The recording resolution box turns with a portrait
display (1080×1920 for a 2160×3840 display at 1080p).

Further details, as built and decided by the architect for PR #1: an
unset `HOME` exits 78 like an unusable settings file; `msr` that cannot re-execute
itself at its real path exits 71. When the displays cannot be read,
the free disk space item is left out, as when the output folder fails.
The ready check reads each audio input by itself, so the disk estimate
counts the default microphone's channels; when the channels of an input
the audio mode records cannot be read, the audio item fails with
"reconnect the audio inputs, then check again", and an input that is not
recorded and whose channels cannot be read never fails the check or
`msr list`. A device without input channels is not read further. The
audio inputs as a whole cannot be read when the device list, the name
of an audio input or, with at least one audio input, the default audio
input cannot be read. The app does not start, with the reason in an
alert, when it cannot register for changes of the audio devices. When the free space cannot be read, the fix says "choose an
output folder on another disk".
