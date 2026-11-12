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
| `msr list` | Shows displays, audio inputs and system audio | 0, 1 when a display or audio input cannot be read |
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
  1  Built-in Retina Display   3456×2234  records at 1670×1080
  2  LG HDR 4K                 3840×2160  records at 1920×1080
Audio inputs
  MacBook Pro Microphone (default), 1 channel
  RØDE Wireless GO II RX, 2 channels
System audio: available
```

`msr check` prints one line per item, `ok` or `FAIL`, a fix under each
failure, and `Ready.` or `Not ready.` last:

```
ok    Screen & System Audio Recording permission
ok    Microphone permission
ok    Displays: 2
ok    Audio: MacBook Pro Microphone (default), system audio
ok    Output folder: ~/Movies/Multi Screen Recorder
FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 3.7 GB needed for 2 hours
      Fix: free up space, or lower --required-recording-hours
Not ready.
```

Started from a terminal, macOS attributes the permissions to the
terminal app, not to Multi Screen Recorder; the README says so.

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
displays (at least one, each readable), the chosen audio sources, the
output folder, and free disk space in the output folder for
`requiredRecordingHours`.

- A permission that was never asked for is requested, so macOS shows
  its prompt; a denied one is reported with the System Settings path.
- A grant is proven, not just read: the check fetches the display list
  and opens the default microphone. With the Microphone permission
  granted but no microphone connected, there is nothing to open: the
  permission item passes and the audio item alone fails, with "no
  microphone".
- Output folder: the check creates it with its parents if it is
  missing, then writes and deletes a file in it; a failure names the
  path and the reason.
- Free disk space is measured on the output folder itself. Disk
  estimate (*data*): 1 GB per display per hour at 1080p, scaled by the
  frame's pixel count of each display at the recording resolution.
- One cause, one red item: when the output folder fails or the
  displays cannot be read, the free disk space item is left out.
- In the app the check runs when the window opens, when the app becomes
  active again (unless a check is still running), after every settings
  change, and on "Check again".

## Output on disk

One recording folder per recording, named by its local start time
(D20):

```
~/Movies/Multi Screen Recorder/2026-11-12 14.03.05/
  2026-11-12 14.03.05 Display 1 - Built-in Retina Display.mov
  2026-11-12 14.03.05 Display 2 - LG HDR 4K.mov
  2026-11-12 14.27.41 Display 2 - LG HDR 4K.mov    ← back after a reconnect
  recording.json
```

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
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording",
      "audioTracks": [
        "Microphone: RØDE Wireless GO II RX, channel 1",
        "Microphone: RØDE Wireless GO II RX, channel 2",
        "System audio"
      ],
      "framesRepeatedForLateness": 0
    }
  ],
  "events": [
    { "at": 1446.2, "event": "display disconnected", "display": "LG HDR 4K" }
  ]
}
```

`start`, `end` and `at` are seconds from the recording's start on the
shared clock. `state` is `recording`, `finalized` or `not finalized`.

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

- **Start:** a small window. At the top, three lines say what Start
  records, built from the settings and the devices connected now: every
  display (named, at the recording resolution), the audio sources, the
  output folder, and that recording continues when displays or audio
  sources change. Then the recording resolution, audio mode, system
  audio and output folder; the ready check, with "Check again"; and
  Start. All green, the ready check is one line, "Ready to record",
  that expands on click to its items; any red item shows every item,
  with the fix under each red one. Start is disabled while the ready
  check fails.
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

**Timecode (D21).** Each display file carries a timecode track: local
time of day at 30 fps, non-drop. All files share t0 and the tick grid,
so their timecodes agree to the frame and an editor can place a
later-starting file by timecode.

**Encoding (D21, values are *data*).** HEVC 8-bit through the hardware
encoder in `.mov`; keyframe every 2 s; quality-targeted variable bit
rate with a ceiling. Audio AAC-LC at 48 kHz, 128 kbit/s per mono track,
192 kbit/s for system audio. Every display is recorded in SDR, also one
in HDR mode, with its colour space tagged so editors show the colours
unchanged (D24). Apple's `SCRecordingOutput` is not used:
it writes a variable frame rate with its own track layout.

**Crash safety (D14, D21).** Files are written in fragments of 2 s
(*data*; independent of the keyframe interval), so a crash loses at
most the last 2 s.

**Frame size (D11).** Fixed when a display file starts: the display's
pixel size shrunk into the recording resolution box, proportions kept,
never enlarged, each side rounded down to an even number. The box turns
with a portrait display (taller than wide): at 1080p a 2160×3840
display records at 1080×1920 (D25). A display
that changes mid-file keeps the frame size: a larger picture is shrunk
to fit, a smaller or reshaped one is centred with black borders.

**Audio (D12, D22).** Every channel of an audio input is its own mono
track, named `Microphone: <device>, channel <n>`; system audio is one
stereo track. Each display file gets the tracks of every source present
when it starts; a source that disappears is padded with silence. The
microphone comes from an `AVCaptureSession` on the default input; system
audio from a ScreenCaptureKit stream of its own, so a failing display
stream never takes the audio with it. Buffers are placed on the shared
clock and written to every open display file.

**Displays coming and going (D14).** A display that appears gets a
stream and a display file; one that vanishes has its file finalized. A
stream that fails finalizes its file and is restarted after 1 s,
backing off to 10 s (*data*), for as long as the display exists. Each
gap is an event in the manifest.

**Disk (D14).** Below the warning threshold: the warning. A writer that
fails on a full disk ends its file, readable up to the last fragment;
the recorder checks free space every 5 s and starts new display files
once there is room. Nothing written is ever deleted.

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
Tests/CommandTests/       msr, scripts/version, scripts/unpack-app and scripts/sign-app, run as commands
Resources/                Info.plist, entitlements
scripts/                  see delivery.md
Tools/                    unpack_app.py, the archive checks of scripts/unpack-app (Python, standard library only)
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
the output folder probe against scratch folders. `CommandTests` run
the built `msr` with a scratch `HOME` (`msr settings` and
`msr version`, which prompt for nothing; also through a symbolic link
into an app bundle), `scripts/version` in scratch git repositories and
`scripts/unpack-app` on scratch archives (some written byte by byte, as
no tar would write them from a file system), `scripts/sign-app` on a
scratch bundle; `scripts/smoke-test` runs the
built app's `msr` the same way in the pipeline.
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
- **Mixing an input down to mono or stereo:** channels may carry
  different people (D22).
- **A notification for low disk space:** see "The app".
- **Recording HDR displays as HDR:** files of mixed kinds on one
  timeline, larger files, and weak support outside DaVinci Resolve, for
  content that is rarely HDR (D24).
- **Sequenced after v0** (D18, `backlog.md`): audio mode `all-inputs`,
  the audio file for a late audio source (until then a source that
  appears mid-recording is logged as an event and joins at the next new
  display file), AGC.
- **The command line driving the running app**, so a terminal needs no
  permissions of its own: deferred (`backlog.md`).

## Open questions

None.

## Build state

Built (skeleton PR): `msr list`, `msr check`, `msr settings`,
`msr version`, the settings file, the ready check and the app window
with it (the summary of what Start records, "Check again", Start
always disabled, "This build cannot record yet."), the About window,
the code layout above except `scripts/acceptance/`, and the tests of
settings, geometry, the disk estimate, the ready check, the output
folder probe, the window's summary, `msr list`, the version, the exit
codes and `scripts/version`. The recorder PR builds the rest:
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
rule, scaled by each frame's pixel count (3.7 GB in the `msr check`
example above). The recording resolution box turns with a portrait
display (1080×1920 for a 2160×3840 display at 1080p).

Further details, as built and decided by the architect for PR #1: an
unset `HOME` exits 78 like an unusable settings file; `msr` that cannot re-execute
itself at its real path exits 71. When the displays cannot be read,
the free disk space item is left out, as when the output folder fails.
The ready check reads only the default microphone's name, not its
channels. When the free space cannot be read, the fix says "choose an
output folder on another disk".
