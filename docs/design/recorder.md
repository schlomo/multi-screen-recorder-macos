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
| `msr check [flags] [--debug]` | Prints "What will be recorded", then runs the ready check and prints each item; `--debug` adds detail on standard error and in the log | 0 ready, 1 not ready |
| `msr record [flags] [--duration 1h30m] [--debug]` | Records the displays and the audio sources (the recording core, D45, D49). Without flags it does what Start in the window does, with the same settings file; it prints "What will be recorded" at its start, then runs the ready check, records until Ctrl-C, SIGTERM, SIGHUP, the duration or Stop in the status window (below), and prints the recording folder at the start and a summary at the end: every file with its state and our process's CPU use, average and peak. It runs as a full AppKit app without a Dock icon (the `accessory` activation policy) until the ready check passed and the recording starts, then shows the icon; a run that is not ready shows none, and an icon macOS refuses is a problem, and the recording goes on (Ctrl-C stops it); while it records, the icon shows with its badge, and clicking it or Quit opens the status window as in the app (D45, D46). When it stops, for any reason, it first prints `Stopping the recording and finalizing the files…` on standard error, then finalizes and prints the summary; a Ctrl-C while it finalizes prints `Still finalizing the files…` and does nothing more. It prints every event of the recording manifest as one line on standard error (see "Logging"). `--debug` adds detail on standard error and in the log. `--duration` takes hours, minutes and seconds (`1h30m`, `45m`, `90s`); a number without a suffix is minutes (`90` is 90 minutes) | 0 ok (every file finalized, no file ended by a failure, D47), 1 not ready, 3 when the recording manifest's `result` is `problems`, the finalized manifest could not be written, or the recording could not start |
| `msr settings [flags]` | Without flags prints the effective settings as JSON (show); with any settings flag, `--auto` included, saves the run's effective settings into the settings file and prints them (change). The only command that writes the file; the window also writes it | 0, 1 when it cannot write the file |
| `msr version` | Prints the version and commit | 0 |

A usage error (unknown command or flag, invalid value) prints a usage
message and exits 64, the convention of Swift Argument Parser. Every
command that reads the settings (all but `msr version`) exits 78
(`EX_CONFIG`) when `HOME` is not set, and for nothing else: a settings
file is never refused (see "Settings file"), so `msr check` exiting 1
means only "not ready".

Each flag is a settings key in kebab case and changes it for this run;
a command without flags uses the settings file as it is. The flags are
the same for `msr settings`, `msr check` and `msr record`; only `msr
settings` saves them (D44):

| Flag | Values |
|---|---|
| `--auto` | no value: auto mode for this run, whatever the settings file says |
| `--resolution` | `native`, `4k`, `1440p`, `1200p`, `1080p`, `720p` |
| `--audio-mode` | `none`, `default-microphone`, `wired`, `all-inputs` |
| `--system-audio` | `on`, `off` |
| `--output-folder` | a folder |
| `--required-recording-hours` | a number |
| `--low-disk-warning-minutes` | a number |

`--resolution` and `--audio-mode` set a choice and so turn auto mode
off for the run; `--auto` together with either is a usage error (exit
64). `msr settings --resolution 1080p` writes `resolution: 1080p` and
`auto: false`, `msr settings --auto` writes `auto: true`: `msr settings`
with a flag writes the run's effective settings. There is no `--save`
(a usage error, exit 64): `msr settings` shows or changes.

`msr list` prints:

```
Displays
  1  Built-in Retina Display   looks like 1728×1117, drawn at 3456×2234  records at 1728×1116
  2  LG HDR 4K                 3840×2160                                 records at 3840×2160
Audio inputs
  MacBook Pro Microphone (default), 1 channel
  RØDE Wireless GO II RX, 2 channels
System audio: available
```

A display is described by what macOS calls "looks like" (its size in
points) and the size it is drawn at (its pixel size): `3840×2160` where
both are equal, `looks like 1728×1117, drawn at 3456×2234` where they
differ (a HiDPI mode). "records at" is the frame size, from the looks-like
size; the drawn-at size is never recorded (D44). It is the one of the
recording resolution the settings choose: Native with auto mode, the
default.

`msr check` first prints "What will be recorded": the window's one
table, the total line and "Files go to <output folder>", from the same
code (see "The app"; the window's last line, "Recording continues when
displays or audio sources change.", is not printed), then one line per
item of the ready check, `ok` or `FAIL`, a fix under each failure, and
`Ready.` or `Not ready.` last. For the devices of the `msr list` example,
the defaults and 3.1 GB free:

```
What will be recorded
  Source                            Looks like  Drawn at   Records at  GB/h
  1 Built-in Retina Display         1728×1117   3456×2234  1728×1116    1.0
  2 LG HDR 4K                       3840×2160   3840×2160  3840×2160    4.1
  ─────────────────────────────────────────────────────────────────────────
  MacBook Pro Microphone (default)                         1 channel    0.1
  RØDE Wireless GO II RX                                   2 channels   0.1
  System audio                                             stereo       0.1
  Total 5.3 GB/h. 2 hours need 10.7 GB, 3.1 GB free.
  Files go to ~/Movies/Multi Screen Recorder
```

then:

```
ok    Screen & System Audio Recording permission
ok    Microphone permission
ok    Displays: 2
ok    Audio: MacBook Pro Microphone (default), RØDE Wireless GO II RX, system audio
ok    Output folder: ~/Movies/Multi Screen Recorder
FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 10.7 GB needed for 2 hours
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

`~/Library/Application Support/Multi Screen Recorder/settings.json`
(D13, D19, D44). It is only read; nothing writes it until a person
saves, so a fresh Mac has none and the defaults apply:

```json
{
  "audioMode" : "wired",
  "auto" : true,
  "lowDiskWarningMinutes" : 20,
  "outputFolder" : "~/Movies/Multi Screen Recorder",
  "requiredRecordingHours" : 2,
  "resolution" : "native",
  "systemAudio" : true
}
```

- **Auto mode.** `auto` is on by default. With it on, a recording uses
  Native and the audio mode Wired whatever `resolution` and `audioMode`
  say, and system audio as its own switch says. The defaults of
  `resolution` (`native`) and `audioMode` (`wired`) are auto mode's
  choices, so turning auto off changes nothing until a slider is moved.
- **Read what is valid, never refuse.** A missing key takes its default;
  an unknown key and an invalid value are ignored (the key takes its
  default); a file that cannot be read, is no JSON or no JSON object
  gives the defaults. One line on standard error, from every command
  that reads the settings and by the app at its start, names what was ignored: `Settings file:
  ignored agc (unknown key), audioMode (invalid value, expected one of
  none, default-microphone, wired, all-inputs); using defaults for
  those.` Nothing is rewritten on read, no copy of the earlier file is
  kept, and the window says nothing about it. A file written before auto
  mode (`resolution: native`, `audioMode: default-microphone`) stays
  valid.
- **Written only when a person saves:** a choice changed in the window,
  or `msr settings` with a flag. The file is written whole, in its current
  form, with Apple's `JSONEncoder` (sorted keys, pretty printed); the
  state file and the recording manifest are written the same way. A
  write that fails is an error naming the file (exit 1 for `msr settings`
  with a flag; a red line in the window, the choice applies for the session).
- Exit status 78 stays for an unset `HOME` only.

## Ready check

Items, in this order: the Screen & System Audio Recording permission,
the Microphone permission (only when the recording records at least one
audio input: with no audio input present, or none recorded under the
audio mode, the item is left out and the permission is neither asked
nor read), the displays (at least one, each
readable), the chosen audio sources (each audio input the audio mode
records readable; another that cannot be read does not count; with an
audio mode but `none` the item says "no microphone" when no input is
recorded, such as on a Mac without any audio input, and passes: no
microphone works in every audio mode, the displays and the system audio
are recorded as usual, and the item then reads `Audio: no microphone,
system audio`, or `Audio: no microphone, no system audio` with system
audio off; an input that is recorded and whose channels cannot be read
fails it), the output
folder, and free disk space in the output folder for
`requiredRecordingHours`.

- A permission that was never asked for is requested, so macOS shows
  its prompt; a denied one is reported with the System Settings path.
- The screen recording grant is proven, not just read, and proven again
  by every check: at the app's start, on "Check again", in `msr check`
  and in `msr record`'s own check the check captures one small frame of
  one display (a ScreenCaptureKit screenshot), so macOS shows every
  prompt of a capture then and Start really starts (D46); the checks
  after a change (a device, a settings change, the app becoming active)
  only fetch the display list. Whether the screenshot brings the prompt
  the owner saw at Start ("requesting to bypass the system private
  window picker") is UNVERIFIED until the owner's next run. The Microphone permission is read, and no
  microphone is opened (D36): the app
  crashed inside macOS after the default microphone was unplugged
  (owner's Mac, 2026-11-13), and the capture session an earlier ready
  check opened for a moment on every run is the cause [ASSUMED]. With
  no microphone connected, the permission item is left out and the audio
  item passes, saying "no microphone", whatever the permission.
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
  is 5.3 GB per hour, 10.7 GB for 2 hours (the table in "The app" shows
  each file).
- One cause, one red item: when the output folder fails, or the
  displays, the audio inputs or an audio input the recording records
  cannot be read, the free disk space item is left out. With the audio
  mode `none`, audio inputs that cannot be read fail nothing.
- In the app the check runs when the window opens, when the app becomes
  active again (unless a check is still running), when a display
  comes, goes or changes, when an audio device comes or goes, when the
  default audio input changes, after every settings change, and on
  "Check again"; the table of what will be recorded follows with it.
  Other changes of an audio input, such as its channels, show with the
  next check. A burst of changes gives one check, 0.3 s after the last
  (*data*); a refresh queued for the window that a newer notice has
  overtaken does nothing (a refresh number, as the check has its own).
  The check's result is shown only when the main run loop
  is in its default mode, meant to hold the window's content still
  while a menu or a modal panel (the folder chooser) is open or a
  control is dragged. The app crashed on 2026-11-14 with an exception
  ("The window has been marked as needing another Layout Window pass,
  but it has already had more Layout Window passes than there are views
  in the window") thrown in a popup menu's own window, opened 1 to 7 s
  after a display's backing scale (HiDPI) was switched, not in the
  start window's layout [KNOWN, unified log]. Whether the hold kept the
  content still under the open menu is not shown by the log, and the
  owner saw the table change with the menu open [ASSUMED from the
  owner's words]. The hold stays. The start window has no popup menu:
  the audio mode and the recording resolution are sliders (D41, D44).
  The probes of the check (permissions, devices, the output folder) can
  be replaced in tests, and the output folder's file access runs off the
  main thread. It never runs while a recording is running, activation
  included (D45).

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
  "app": "Multi Screen Recorder 0.20261115.4 (a1b2c3d)",
  "state": "recording",
  "started": "2026-11-12T14:03:05.120+01:00",
  "ended": null,
  "result": null,
  "cpu": null,
  "settings": { "resolution": "1080p", "audioMode": "default-microphone", "systemAudio": true },
  "files": [
    {
      "name": "2026-11-12 14.03.05 Display 1 - Built-in Retina Display.mov",
      "display": "Built-in Retina Display",
      "displayUUID": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
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
      "displayUUID": "1E6E43E3-6E7B-4C2A-9F6B-2B0F4C1A9D11",
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
      "audioSourceUID": "BuiltInMicrophoneDevice",
      "channels": 1,
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording",
      "clockDriftPpm": null
    },
    {
      "name": "2026-11-12 14.03.05 System audio.mov",
      "audioSource": "System audio",
      "channels": "stereo",
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording",
      "clockDriftPpm": null
    },
    {
      "name": "2026-11-12 14.27.41 Display 2 - LG HDR 4K.mov",
      "display": "LG HDR 4K",
      "displayUUID": "1E6E43E3-6E7B-4C2A-9F6B-2B0F4C1A9D11",
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
      "displayUUID": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
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
    { "at": 812.4, "event": "audio input gap", "audioSource": "MacBook Pro Microphone", "length": 0.25 },
    { "at": 1446.2, "event": "display disconnected", "display": "LG HDR 4K" },
    { "at": 2285.0, "event": "display frame size changed", "display": "Built-in Retina Display",
      "from": [1670, 1080], "to": [1662, 1080] }
  ],
  "problems": [
    { "at": 600.0, "problem": "The free space in /Users/anna/Movies/Multi Screen Recorder cannot be read",
      "error": "The file “Multi Screen Recorder” couldn’t be opened." }
  ]
}
```

`start`, `end` and `at` are seconds from the recording's start on the
shared clock. A display file's `displayUUID` is its display's identity (see
"Display identity"). The events: `display connected`, `display
disconnected`, `display frame size changed`, `display mirroring
started`, `display mirroring stopped`, `main display changed`,
`display stream failed`, `display shows another display's picture`,
`display file writer fell behind`, `display file writer failed`, `disk
full`, `sleep`, `wake`, and for audio `audio input connected`, `audio
input disconnected`, `system audio started`, `system audio stopped`,
`default microphone changed`, `audio input gap`, `audio input failed`,
`system audio failed`, `audio file writer failed`, `audio file writer
fell behind`;
each names its display (`display`) or its audio source (`audioSource`)
where it is about one; `display` always means a display.
Their fields: `at`, `event`, `display` or `audioSource`; `from` and `to` (the old and
the new frame size) for `display frame size changed`, and the old and
the new default microphone for `default microphone changed` (either
absent where there was or is none); `mirrors` (the display mirrored)
for `display mirroring started`; `length` (seconds, to the
millisecond) for `audio input gap`; `error` (why) for `display stream
failed`, `display file writer failed`, `audio input failed`, `system
audio failed` and `audio file writer failed`. The
manifest's `state` is `recording` or `finalized`; a file's `state` is
`recording`, `finalized` or `not finalized`.
`ended` is the local end time, as `started`, and `result` is `ok` when
every file is finalized and no file was ended by a failure (`display
stream failed`, `display file writer failed`, `disk full`, `display
file writer fell behind`, `display shows another display's picture`,
`audio input failed`, `system audio failed`, `audio file writer
failed`, `audio file writer fell behind`; an unplugged audio input and
a gap are none), otherwise
`problems` (D47); `cpu` is our process's CPU use over the recording,
`averagePercent` and `peakPercent` in percent of one core as Activity
Monitor shows it, sampled every second, to one decimal (encoding and
capture in macOS's own processes, `VTEncoderXPCService`, `replayd`,
`WindowServer`, are not in it); all three are null until the
recording is finalized. `problems` lists every problem told to the
person, also those that leave `result` `ok`, each with `at`,
`problem` (what went wrong) and `error` (the full error text, or null).
`events` and `problems` are written in the order of their time.
An audio file's `audioSource` is the audio input's name (see "Audio
input names" below) or `System audio`; `audioSourceUID` the input's
Core Audio UID, absent for the system audio; `channels` the number of
its mono tracks, or `stereo` for the system audio; `clockDriftPpm` its
measured clock drift (see "Audio"), null until known. `files` lists the
display files and the audio files in the order of their start.

**Audio input names (D49).** In a file name, a reel name and a track
name, `/` and `:` in an audio input's name become `-`, as for a display;
two audio inputs with the same name get " (2)", " (3)" in the order they
appeared in the recording, and an input that comes back keeps its name.

**Metadata in every file (D46, D49).** The timecode track names the
source as its reel name (the source reference name of its format
description): `Display <n> - <name>` for a display file, the display's
name unchanged; `Microphone - <name>` or `System audio` for an audio
file. It is written with the track, so a file never finalized keeps it.
Each track is named in its user data full name (`©nam`), the one
track-level item `ffprobe` shows (as the stream's `title`, checked on
2026-11-16; items in the track's `mdta` metadata it does not show): a
display file's video track by the reel name, its guide tracks
`Microphones` and `System audio`, an audio file's tracks
`Microphone: <name>, channel <n>` or `System audio`. A display file's QuickTime
metadata items, all text, under `org.schapiro.multiscreenrecorder.`:
`displayUUID`, `displayNumber`, `displayName`, `frameSize`
(`1920x1080`), `recordingStarted` (as the manifest's `started`) and
`app` (as the manifest's `app`); an audio file's: `audioSource`,
`audioSourceUID` (not for the system audio), `channels` (as in the
manifest), `recordingStarted` and `app`; in every file the app also
under the standard `com.apple.quicktime.software`; the reel name also under
`com.apple.proapps.reel` and `com.apple.proapps.cameraName`, which
DaVinci Resolve may map to Reel Name or Camera # [CONJECTURE]. All
items, like the reel name, are in a file never finalized too. Whether
DaVinci Resolve's "detect clips from same camera" reads any of them is
UNVERIFIED (D46).

**Parallel recordings.** A recording claims its recording folder by
creating it and refuses if it already exists. Recordings into different
folders may run side by side (several `msr record`, or one beside the
app); the app itself runs one at a time.

**A recording that did not finish.** A recording manifest without
`ended` belongs to a recording that is running or did not finish, such
as after a crash or a power loss; its files are readable up to the last
2 seconds. Nothing is kept while recording to find it, and nothing is
checked, reported or rewritten at the next start (D47).

## The app

- **Start:** a small window. At the top, a section "What will be
  recorded", built from the settings and the devices connected now and
  refreshed whenever the ready check runs (D33): one table and a
  total line. The columns are Source, "Looks like", "Drawn at", "Records
  at" and GB/h, the last for every row and right-aligned. The widths of
  the columns after Source are measured at runtime from the widest
  possible content in the table's font ("8888×8888", "cannot be read",
  "888.8" and so on, and the header), never from what is
  connected, so no column moves when auto mode, a slider or the devices
  change; Source takes the rest of the window, which is as wide as the
  table, holds "MacBook Pro Microphone (default)" and truncates a longer
  name in the middle (the full name is its tooltip).
  - Display rows first: the number and name, "Looks like" (the size in
    points), "Drawn at" (the pixel size, shown also where both are
    equal), "Records at" (the frame size) and GB/h (the display file,
    its guide tracks included).
  - A thin divider, no second header, then the audio rows: the name of
    each audio input (the default one marked "(default)") in Source,
    Looks like and Drawn at empty, its number of channels in Records
    at ("1 channel", "2 channels", "cannot be read"), and GB/h (the
    audio file); the last row is "System audio" with "stereo". A source not recorded
    is dimmed and its GB/h is 0 (D46): every input with the audio
    mode `none`; every input but the default one with
    `default-microphone`; with `wired` every input but the default one
    that is not built-in or wired; and the system audio row when it is
    off.
  - GB/h is numbers only (D46), with one decimal; under 0.05 it shows
    "<0.1", and "?" when the rate cannot be told (an input whose
    channels cannot be read).
  - The total line: "Total <x> GB/h. <requiredRecordingHours> hours
    need <y> GB, <z> GB free.", without the free part while the free
    space is unknown (the ready check has not finished yet, or its
    output folder item failed).
  - Below, the output folder and "Recording continues when displays or
    audio sources change." If the displays cannot be read, that error
    stands as a red line above the table, which then has no display
    rows; if the audio inputs cannot be read, "The audio inputs cannot
    be read: <reason>" stands as a red line above the table too, which
    then has the system audio row only; an audio input whose channels
    cannot be read shows "cannot be read" in the Records at column (and "?" GB/h if it is recorded). The total line
    appears only when the displays and every recorded audio input can
    be read. The ready check's items stay as they are.

  Then a switch "Auto", on by default: the two sliders are always shown, so
  that the switch shifts nothing: on, they are disabled (grayed out) and
  show auto mode's choices, Native and Wired, not the saved values, and
  a caption says what auto mode records (every display at Native, the
  audio mode Wired); off, they are enabled and show the saved values: the recording resolution (over 720p,
  1080p, 1200p, 1440p, 4K, Native, smallest to largest) and the audio
  mode (over None, Default microphone, Wired, All), each with the chosen
  one's name beside it. Under the audio mode slider the window says:
  "Bluetooth and virtual microphones are recorded only under All, or
  when they are the default microphone: recording a Bluetooth headset's
  microphone switches it to call quality, and a virtual microphone
  often carries a copy of other sound." Then system audio and output
  folder, which stay as they are; the ready check, with "Check again";
  and Start. A change of a choice is saved at once; if the settings file
  cannot be written, a red line says so. The window has no "Reset to
  defaults": a settings file is never refused.
  The table and the total line are the same data that `msr check`
  prints as text.
   All green,
  the ready check is one line, "Ready to record", that expands on click
  to its items; any red item shows every item, with the fix under each
  red one. Start is disabled while the ready check fails. For the
  devices of the `msr list` example, the defaults and the free space
  of the `msr check` example, the section shows:

| Source | Looks like | Drawn at | Records at | GB/h |
|---|---|---|---|---|
| 1 Built-in Retina Display | 1728×1117 | 3456×2234 | 1728×1116 | 1.0 |
| 2 LG HDR 4K | 3840×2160 | 3840×2160 | 3840×2160 | 4.1 |
| MacBook Pro Microphone (default) |  |  | 1 channel | 0.1 |
| RØDE Wireless GO II RX |  |  | 2 channels | 0.1 |
| System audio |  |  | stereo | 0.1 |

Total 5.3 GB/h. 2 hours need 10.7 GB, 3.1 GB free.

- **Recording:** the window closes; the Dock icon has no badge while
  all is well, no timer (D47). Low disk space shows as a "!" badge and a
  bouncing Dock icon; no notification, which would need a third
  permission and is hidden by Focus modes. A recording problem (the
  recording manifest cannot be written, the displays or the free space
  cannot be read, a display file's or an audio file's writer fails, an
  audio source's capture fails) shows the same way,
  and the status window lists it in red; `msr record` also names each
  on standard error.
- **Status window (D46):** clicking the Dock icon while recording opens
  a small window, and Quit opens it too: a table with a row per display,
  then a row per audio source the recording records or recorded (the
  audio inputs by name, the system audio last), and the columns Source,
  "Records at" (a display's frame size; an audio source's `1 channel`,
  `2 channels` or `stereo`), Files, "GB written" (its files on disk) and
  State (`recording`, `waiting`, `failed, retrying`, `shows another
  display`, `disk full`, `mirroring`, `disconnected`, `asleep`, and for
  an audio input no longer in the audio mode, such as the default
  microphone before a change, `not recorded`); under it the line
  "Recording 1:07:00 · 1.3 GB in 3 files · 120.4 GB free", the elapsed
  time as `h:mm:ss` (D47); then "CPU 23 %", our process's CPU use in
  percent of one core as Activity Monitor shows it, sampled every
  second, with the line "Encoding and capture also run in macOS's own
  processes (VTEncoderXPCService, replayd, WindowServer), which this
  number does not include."; the problems in red, with the command for
  the log (see "Logging"); and [Stop] [Continue]. It refreshes every second
  while open; Continue closes it. A display file whose size cannot be
  read makes its display's GB written `?`, and the line's data written
  `? GB`. Free space that the volume does not report is a problem as a
  failing read is. A problem goes into the
  recording manifest, which is written at once (unless writing it is
  the problem); one that repeats, such as the free space that cannot be
  read on every check, is told once (one manifest entry, one red line,
  one line on standard error, one bounce) until it clears, and again if
  it comes back.
- **Stop:** Stop in the status window finalizes, opens the recording folder itself
  in Finder (D46) and quits the app: a recording is typically one shot (D45).
  Logout, restart and shutdown finalize without asking, told apart from
  a Quit by the quit Apple event's reason (`kAEQuitReason`); one that
  comes while Stop is in progress waits for it. A failing writer and a
  full disk are a recording problem also when no display file had
  started. While a recording runs,
  the app does not quit when its last window closes, and the ready
  check does not run, also not when the app is activated.
  `msr record` shows the same Dock icon, badge and status window; Stop
  there ends `msr record` as Ctrl-C does (D45).
- **About:** version, licence, the purpose (the opening paragraph of the
  README, one string in the code), and a link to GitHub Issues that
  opens in the browser (D15, D26). The credit to the former upstream is
  in the README.
- **Crash report offer:** when the app starts, after the window is
  shown, it looks for the newest crash report of `msr`
  (`~/Library/Logs/DiagnosticReports/msr-YYYY-MM-DD-HHMMSS.ips`, top
  level only). If its name is greater than `lastOfferedCrashReport` in
  the state file (nothing there: any crash report), a dialog "Multi
  Screen Recorder quit unexpectedly" offers [Report on GitHub] [Not
  Now], and the name is stored whatever the answer, so a crash is
  offered once; a crash whose name sorts before the last offered one is
  not offered (causes: the clock was set back, the daylight-saving
  fall-back hour, a time-zone change; the names carry local time
  [ASSUMED]). The state file is
  `~/Library/Application Support/Multi Screen Recorder/state.json`
  (`HOME` decides), beside the settings file but apart from it: app
  state the person never edits, written atomically, never touched by
  `msr settings`. "Report on GitHub" copies the
  crash report to `Crash Reports/msr-….txt` in the same folder (GitHub
  refuses `.ips` files), opens the browser on a new issue of the
  repository with the form `.github/ISSUE_TEMPLATE/crash-report.yml`,
  its title, app version and macOS version filled in (the title keeps
  the `.ips` name), and shows the text copy in Finder for the person
  to drag into the issue; GitHub takes no file through a link. The app
  opens no connection itself (D15, D40). A crash report folder or a
  state file that cannot be read or decoded, or a failed write
  shows an alert "Cannot offer the crash report" with the error, and
  nothing is offered that start; a failed text copy (the dialog was
  already answered) shows "Cannot copy the crash report" with the
  error; a browser that cannot be opened shows
  an alert with the address.

## How the recorder works

**Shared clock.** Everything runs on one clock that counts sleep
(`mach_continuous_time`). The recording's start t0 is one instant on
it; every timestamp in every file and in the manifest is an offset from
t0. The host clock that frames and audio buffers are stamped with does
not advance while the Mac sleeps, so a buffer's time is converted by
the difference of the two clocks, read at the start and again at every
wake; no file spans a sleep (see "Displays coming and going"), so the
conversion within a file is exact. A file starting after a wake so
keeps its place on the timeline and its timecode the time of day.

**Event loop.** The app and `msr record` run the same AppKit event
loop and show the app's Dock icon, `msr record` once the recording
starts (D45, D46): macOS reports display changes
(`CGDisplayRegisterReconfigurationCallback`) only to a process running
`NSApplication.run()`, which the experiments of 2026-11-15 showed
([end-to-end-tests.md](end-to-end-tests.md), "What research found for
the recorder"). Both start it from `main` itself, at the same
synchronous point, with `msr record`'s arguments parsed before: an
event loop started inside a main-queue job, such as after the first
`await` of an `async` `main`, never drains the main queue again, so no
task, signal source or display change would reach the recorder.
`msr record` stops on its signals through the same path as Stop.

**Constant 30 fps (D11, D21).** Per display, a ScreenCaptureKit stream
delivers complete frames when the screen changes; the newest is kept.
The mouse pointer is recorded.
Tick k is at t0 + k/30 s, computed, never accumulated. Every tick
writes the newest frame captured before it, with exactly the tick's
timestamp: a frame appears at the first tick after its capture time,
never early. No tick is ever dropped: when the encoder is not ready, the
tick is written late with its correct timestamp and counted in
`framesRepeatedForLateness`. A tick written late carries the newest
frame captured before the tick's own time, never one captured while it
waited, so its picture is right and only its writing is late. At most
2 s of ticks wait (*data*); a writer further behind ends its display
file with the event `display file writer fell behind`, and a new
display file starts, as after a failing stream. The v1 gate's clock
recording checks this from outside the recorder. A display file starts
at the first tick after its stream's first frame that passes the
display check (below), and never before the stream's own start. When a
display file ends, the ticks due are written, then those still waiting,
for at most the late-tick bound (2 s) on a clock that does not count
sleep, and the file is finalized also when the writer fell behind or
the wait ran out; what failed is in the manifest.

**Timecode (D21, D31).** Every display file and every audio file
carries a timecode track: local time of day at 30 fps, non-drop, the
clock time also on a day with a daylight saving change. A display
file's timecode track has one sample, at its first tick, as is the
convention; the writer finishes that track at once, so a file
that is never finalized still carries its timecode (tested). An audio
file's timecode track is the same: `AVAssetWriter` writes it into an
audio-only fragmented `.mov`, and AVFoundation and `ffprobe` read it
back with its reel name, finalized or not (the proof of 2026-11-15,
tested). All files share t0 and the tick grid, so their timecodes
agree to the frame and an editor can place every file, also a
later-starting one, by timecode. Unproven until the owner's first real
recording with audio: that DaVinci Resolve reads the timecode of an
audio-only `.mov`, and how Kdenlive places the files (see "Open
questions").

**Encoding (D21, values are *data*).** HEVC 8-bit through the hardware
encoder in `.mov`; keyframe every 2 s; quality-targeted variable bit
rate with a ceiling. Audio AAC-LC at 48 kHz: in an audio file
128 kbit/s per mono track and 192 kbit/s for the system audio's stereo
track; in a display file 64 kbit/s for the guide track "Microphones"
and 96 kbit/s for the guide track "System audio". Every display is
recorded in SDR, also one
in HDR mode, with its colour space tagged so editors show the colours
unchanged (D24): the stream delivers 420v frames, which carry BT.709
(the experiment of 2026-11-15), and the display file is tagged BT.709
for primaries, transfer and matrix. Apple's `SCRecordingOutput` is not used:
it writes a variable frame rate with its own track layout.

**Crash safety (D14, D21).** Files are written in fragments of 2 s
(*data*; independent of the keyframe interval), so a crash loses at
most the last 2 s.

**Frame size (D11, D30, D44).** A display file's frame size is the
display's looks-like size (what macOS shows as "looks like", in points)
fitted into the recording resolution box: proportions kept, never
enlarged, each side rounded down to an even number. The size the
display is drawn at (its pixels) is never recorded: a HiDPI mode that
looks like 1920×1080 on a 3840×2160 display records at 1920×1080. The
box turns with a portrait display (taller than wide): at 1080p a
2160×3840 display records at 1080×1920 (D25). Examples: the built-in
display, looks like 1728×1117, drawn at 3456×2234, records at Native
1728×1116 and at 1080p 1670×1080; a 4K display without HiDPI records at
Native 3840×2160. While a display's frame size stays the same, its file
continues, whatever else changed about the display, a switch of its
HiDPI mode that keeps its looks-like size included. When the frame size
changes, the display's current file ends and a new file starts at the
new frame size, like after a reconnect, with the event `display frame
size changed` (the display, the old and the new frame size) in the
manifest. At `native` the frame size is the looks-like size rounded
down to even numbers, so nearly every looks-like size change is such a
change; at `1080p` a change from 3840×2160 to 5120×2880 is not (both
give 1920×1080), while 3440×1440 to 1920×1080 is (1920×802 to
1920×1080).
The cost: a gap of under one second at the change in that display's
video and guide tracks only; the audio files and the other displays'
files continue unbroken; a display that flaps between modes makes many
short display files, each valid.

**Audio (D12, D22, D31, D49).** One audio file per recorded audio
source, beside the display files. Each recorded audio input gets its
own audio file, a `.mov` with one mono track per channel, named
`Microphone: <device>, channel <n>`; the system audio gets its own
audio file with one stereo track, named `System audio`. Every audio
file carries the timecode track with the source as its reel name and
the metadata items (see "Output on disk").

- **Sources.** Each recorded audio input has an `AVCaptureSession` of
  its own (D49), its PCM converted to 32-bit float at 48 kHz by the
  session's output; the system audio comes from a ScreenCaptureKit
  stream of its own on the main display, with `capturesAudio`, our own
  process's audio excluded, its video at 2×2 pixels and one frame a
  second and dropped, so a failing display stream never takes the
  audio with it. The stream reads the main display each time it
  starts, never an older reading. When the system audio's display goes,
  its stream starts again on the new main display, with the events
  `system audio stopped` and `system audio started`. Which audio inputs are recorded
  follows the audio mode (D44): `none` none, `default-microphone` the
  default one, `wired` the default one plus every built-in and wired one
  (transport type built-in, USB, FireWire, PCI, Thunderbolt, HDMI,
  DisplayPort; Bluetooth, Bluetooth LE, virtual, aggregate, AirPlay,
  Continuity capture, an unknown transport and one that cannot be read
  are not wired), `all-inputs` every input. The default microphone is
  recorded in every audio mode but `none`, whatever its transport, and
  followed (D34): when the default input changes, the event `default
  microphone changed` (`from` and `to`, the old and the new default
  microphone) is written, the old one's file ends if the audio mode no
  longer records it, and the new one starts after the settle time. A
  Bluetooth headset's microphone switches to call quality when
  recorded, and a virtual microphone often carries a copy of other
  sound, so those are recorded only under `all-inputs` or as the
  default microphone. Audio inputs are known by their Core Audio UID,
  which is also `AVCaptureDevice`'s `uniqueID`; one whose UID cannot be
  read cannot be recorded, which is a problem.
- **Coming and going.** The recorder reads the audio inputs again
  whenever Core Audio reports a change of the devices or of the
  default input. An audio input that appears starts its audio file
  after the settle time (event `audio input connected`); one that
  disappears ends its file (event `audio input disconnected`). An
  unplugged input stops its session with
  `AVCaptureSession.runtimeErrorNotification` (-11808) and
  `AVCaptureDevice.wasDisconnectedNotification`, at once; the session
  does not resume by itself, so its file ends and a replug starts a new
  session and a new audio file ([end-to-end-tests.md](end-to-end-tests.md),
  "What research found for the recorder"). An unplug is no failure.
  One whose channel count changes ends its audio file and starts a new
  one. A display event never touches an audio file, but sleep ends
  every audio file and wake starts new ones, as for display files.
- **Placement.** An audio file starts at the first tick after its first
  buffer, and the samples before that tick are trimmed, so its timecode
  is exact; from there every sample is placed by sample count, not by
  its timestamp. A buffer whose timestamp is more than 32 ms (*data*;
  one buffer of 512 samples is about 10.7 ms) ahead of the position its
  sample count gives is a gap, the event `audio input gap` with its
  `length` in seconds: a gap up to 1 s (*data*) is filled with silence
  of exactly its length; a longer one ends the audio file and a new one
  starts (D46 point 7). A buffer behind that position is written by its
  sample count and is no gap.
- **Clock drift.** An audio input runs on its own clock, up to 117 ppm
  off the host clock (measured), and `AVCaptureSession`'s timestamps
  follow its sample count, so drift shows as no gap. Each audio file's
  drift is measured, not corrected (a later PR): `clockDriftPpm` in the
  recording manifest, the samples written against the shared clock's
  time between the host times at which the file's first and latest
  buffers arrived, positive when the source's clock runs fast (more
  samples than time passed), to a tenth of a ppm; null until two
  buffers arrived apart.
- **Failures.** A failing audio capture or writer and a full disk are
  handled for an audio file as for a display file (below): the file
  ends, the event (`audio input failed`, `system audio failed`, `audio
  file writer failed` with its `error`, `audio file writer fell behind`
  when the writer took none of the last 2 s of samples, or `disk full`)
  and a problem are told, the capture is started again with the same
  back-off, and after a full disk a new audio file starts once there is
  room. Such an end makes the recording's `result` `problems` (D47); an
  unplug and a gap do not. As for a display, a source lost a second
  time while it is still listed and recorded, with no change of the
  audio devices (an audio input) or of the displays (the system audio)
  in between, is a failure: `audio input failed` or `system audio
  failed` with that as its `error`, a problem and the back-off. When an
  audio file ends, the samples still waiting for its writer are
  written for at most 2 s; its `end` counts only what the writer took,
  and samples left over are told as lost in a problem.
- **Guide tracks.** For playback and waveform sync, every display file
  also carries guide tracks: "Microphones", one mono mix of all recorded
  audio input channels, their sum divided by √n for n channels, clamped
  to ±1, unless the audio mode is `none`; "System audio", stereo, unless
  system audio is off. The two are never mixed together. Each source
  is placed by its own timestamps, the mix runs 200 ms (*data*) behind
  real time so every source's buffers have arrived, and a source that
  is missing is silence in its guide track. The mix is handed to every
  open display file every 100 ms (*data*); a display file's guide tracks
  cover exactly its own time, so a frame size change gives them the
  same gap as the video. A display file's guide tracks may end up to
  300 ms early, the 200 ms delay plus up to one 100 ms hand-over: the
  samples not yet handed over when it ends. The audio files themselves
  are complete.

**Display identity.** A display is known by the UUID macOS gives it
(`CGDisplayCreateUUIDFromDisplayID`), never by its display ID, which
changes when a display comes back, nor by its name, which macOS may
change ("MSR Test (1)"). A display that comes back with the same UUID
keeps its number and its name in the file names for the whole
recording. Whether a real display keeps its UUID after it was
unplugged is UNVERIFIED (the owner's check on the first build). In a
file name, `/` and `:` in a display's name become `-`, so a name never
stops a display from recording. A display reached through another port
(a monitor with two USB-C inputs) may be another display, with its own
UUID and number: macOS treats it so, and so does the recorder (D46).

**Displays coming and going (D14).** A display that appears gets a
stream and a display file (event `display connected`); one that
vanishes has its file finalized (event `display disconnected`). A
display that is asleep counts as disconnected; that macOS's display
change callback fires when a display falls asleep is [ASSUMED]. When
a display is unplugged, its stream ends first, with ScreenCaptureKit's
`noCaptureSource` (-3815), and macOS's display-change notice may come
seconds later (8 s for the Wacom One, observed in the owner's run of
2026-11-15, `--debug` log). That stream end is no failure: the display
file ends as on a disconnect, with no `display stream failed` event and
no back-off; the event `display disconnected` comes with the notice. A
display still listed one settle time after such a stream end gets a new
stream, as after any change, without a failure event. Only the first
such end is free: if the stream ends with `noCaptureSource` again with
no display-change notice for that display in between, it is a failure
(`display stream failed` with its error, back-off, and a problem told),
so a display that stays listed but cannot be captured never goes
unrecorded silently. Any other stream error is a failure: a stream that fails finalizes its file and is restarted after 1 s,
backing off to 10 s (*data*), for as long as the display exists. Each
gap is an event in the manifest. A display's stream starts, or starts
again, only once the display has been unchanged for the settle time,
1 s (*data*): a mode change that macOS reports as a disconnect and a
reconnect, or modes switched through quickly, so make no burst of
short display files. When a mode change gives a new frame size, the
current display file runs on through the settle time, with the picture
scaled to the old frame size, and then ends; the stream is stopped and
a new one started at the new frame size, the same path as a reconnect
(`updateConfiguration` is not used: never tried). The gap is the
restart only.
- **Mirroring:** a display that starts mirroring another
  (`CGDisplayMirrorsDisplay`) ends its display file with the event
  `display mirroring started` (the display and the one it mirrors);
  when mirroring stops, a new display file starts with `display
  mirroring stopped`. The display keeps its number.
- **Main display:** a change of the main display is the event `main
  display changed`; the numbers stay.
- **Sleep and wake:** at sleep every file ends (event `sleep`); at wake
  (event `wake`) new files start, the displays after the settle time.

**Display check (D45).** Every frame is checked before it is kept: the
rectangle ScreenCaptureKit attaches to it (`SCStreamFrameInfo.screenRect`)
must be its display's bounds (`CGDisplayBounds`, held in memory and
read again when the displays change). It reads no pixels. A frame that
fails is never written, and its tick repeats the last frame that
passed. Why: after a display reconnects, ScreenCaptureKit can deliver
another display's picture on its stream, and a restart does not clear
it (the experiments of 2026-11-13 and 2026-11-15 with virtual displays,
[end-to-end-tests.md](end-to-end-tests.md), "What research found for
the recorder"); a frame then carries the other display's rectangle.
After 30 failing frames in a row (*data*), not counting those within
the settle time after a display change, the display file ends with the
event `display shows another display's picture`, the Dock badge shows
"!", `msr record` names the display on standard error, and the display
is tried again only after its next change. Its limit: a frame whose
rectangle is right can still be black (seen once, cause unknown); the
check cannot see that. That `screenRect` and `CGDisplayBounds` are
comparable as they are, in points and the same coordinates, is
[ASSUMED]; the builder checks it with real frames.

**Disk (D14).** Below the warning threshold: the warning. A writer that
fails on a full disk ends its file, readable up to the last fragment;
the recorder checks free space every 5 s and starts new display files
and audio files once there is room. The low disk warning threshold
counts every display's newest display file and every audio source's
newest audio file. Nothing written is ever deleted.

**Keep awake (D14).** A power assertion against idle system and
display sleep while recording.

## Logging

No log file of our own (D46). The app and `msr` write every event of
the recording manifest and every problem to the macOS unified log, subsystem
`org.schapiro.multiscreenrecorder`, at `.notice` (problems at
`.error`), levels macOS keeps on disk, with names (displays, folders)
public, not redacted. `msr record` also prints each event as one line on
standard error: the local time, the offset from the recording's start,
the event and its display, and the details it has, such as
`22:14:40 +9.2s display connected: Wacom One 13T` or
`22:15:32 +61.3s display stream failed: LG (-3811)`. `--debug` (for
`msr record` and `msr check`) adds detail lines (the tracker's actions,
the displays as read, files started and ended, the ready check's facts)
on standard error and at `.debug` in the log. The log of the last 2
hours, of the app and `msr` only (the tests log under the same
subsystem on a developer's Mac):

```sh
log show --last 2h --predicate 'subsystem == "org.schapiro.multiscreenrecorder" and process == "msr"'
```

The crash report form has an optional field for its output, and the
crash report dialog, the status window (with a problem) and the README
name the command.

## Code layout

```
Package.swift             Swift 6 language mode, macOS 26, arm64
Sources/RecorderLogic/    pure logic, Foundation only, fully unit-tested
Sources/RecorderCore/     ScreenCaptureKit, AVFoundation and Core Audio adapters
Sources/msr/              entry point: the command line and the app
Tests/RecorderLogicTests/ Swift Testing, as all tests
Tests/RecorderCoreTests/  the adapters that need no device or permission
Tests/AppTests/           the start window's model, with stand-in probes
Tests/CommandTests/       msr and the scripts in scripts/, run as commands
Resources/                Info.plist, entitlements
assets/icon/              the app icon (SVG source, derived PNG) and artwork; see its README.md
scripts/                  see delivery.md
```

Swift Package Manager and bundling scripts rather than an Xcode
project, whose project file cannot be reviewed by hand. One dependency:
Swift Argument Parser, Apple's own package for command lines.

## Tests

`scripts/test` runs the unit tests of `RecorderLogic`: the tick grid
(which frame lands on which tick, still periods of 60 s and more, late
ticks), geometry for every recording resolution (and their slider order) and change case,
Native as the looks-like size, auto mode's effective choices, the audio
modes and which input each records (every transport type), settings read
leniently with the line for standard error, flags (`--auto` against
`--resolution` and `--audio-mode`) and their errors, the text `msr check`
prints for "What will be recorded", file naming, manifest states,
the display tracker (numbers, the settle time, frame
size changes, mirroring, the main display, back-off, the display check's
fault, a full disk, sleep and wake), the display check, the shared clock,
the timecode (also on a daylight saving day and at a second frame rate),
`--duration`, the summary of `msr record`, the Dock badge and the
problems of a recording, the audio tracker (the audio modes, inputs
coming and going, an unplug told once, a replug, the default
microphone followed, failures with the back-off, the system audio
moving to the new main display, a full disk, a channel count change,
two inputs with the same name, sleep and wake), the audio file's
placement on the tick grid (trimming, gaps filled or ending the file,
jitter within 32 ms) and its `clockDriftPpm`, splitting interleaved and
non-interleaved PCM, the guide track mixes, audio file names and
metadata, our process's CPU use, the status window's rows, the version, the state file's content, the choice of
the crash report to offer, the new-issue link (and that the issue form
has the fields it fills), the name of a crash report's text copy, and
the text of the examples in this document, which the tests hold to the
code. `RecorderCoreTests` test
the output folder probe against scratch folders, and that this Mac's
audio inputs can be read and a listener for their changes registered,
which needs no permission and shows no prompt, the state file (missing,
saved, broken), the listing of the crash report folder (a missing one
is no crash reports, an unreadable one an error), the text copy of a
crash report, display files written from synthetic frames and read
back (constant frame rate, timecode, BT.709, fragments, a file never
finalized, the guide tracks), audio files written from synthetic PCM
and read back (a mono track per channel or one stereo track, the bit
rates, the timecode with its reel name, the metadata, a filled gap
decoding as silence, a file never finalized), the proof that an
audio-only fragmented `.mov` carries a timecode track, a display file's
ticks with a stand-in writer (a failing writer, one that fell behind, a
slow end, guide samples placed from the file's first tick), a stream stopped while it
starts, that an action
waiting for the main run loop's default mode runs only there, the
classification of Core Audio's transport types, and the ready check's
probes with stand-ins (the output folder's file access is off the main
thread). `AppTests` run the start window's model with stand-in probes
and a stand-in for the hold: one check per burst of device changes,
nothing applied while a menu is open, a stale queued refresh does
nothing, choices saved only when changed, no ready check while
recording, Start only when ready, and which quit finalizes without
asking. `CommandTests` run
the built `msr` with a scratch `HOME` (`msr settings`, with flags and
`--auto`, and `msr version`, which prompt for nothing; also through a
symbolic link into an app bundle), `scripts/version` in scratch git repositories and
`scripts/unpack-app` on scratch archives (some written byte by byte, as
no tar would write them from a file system), `scripts/sign-app` and
`scripts/smoke-test` on a scratch bundle, and
`scripts/publish-snapshot-release` against a stub `gh`;
`scripts/smoke-test` runs the built app's `msr` the same way in the
pipeline.
Capture itself cannot run in CI, which has
no way to grant the permissions [ASSUMED]; it is verified on a Mac by
end-to-end tests, which drive `msr record` and examine the recording
folder, and by the v1 gate. The design of the end-to-end tests is
[end-to-end-tests.md](end-to-end-tests.md) (D37).

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
- **Sequenced after v0** (D18, D44, `backlog.md`): AGC.
- **A settings file refused, repaired on read or kept as a copy:** a
  settings file is read, what is invalid is ignored and named on
  standard error, and nothing is written until a person saves (D44).
- **A "Reset to defaults" in the window, an `--auto on` / `--auto off`
  value, a repair of the file on read:** the settings file is not
  something people deal with by hand (the owner, D44).
- **Every audio source in every display file** (D12): one audio file
  per source instead, with guide tracks in the display files (D31).
  Joining the files into one without re-encoding is deferred
  (`backlog.md`).
- **The command line driving the running app**, so a terminal needs no
  permissions of its own: deferred (`backlog.md`).
- **Screenshots as a fallback** for a display that shows another
  display's picture (`SCScreenshotManager`, right in 3 of 3 faulty
  runs, its cost at 30 frames per second unknown): a second capture
  path; deferred (`backlog.md`, D45).
- **Choosing audio inputs one by one** with auto mode off (open in
  D34): the audio mode `all-inputs` records every input, virtual ones
  included, which the end-to-end tests use; deferred (`backlog.md`).

## Open questions

- Unproven until the owner's first real recording with audio (D31):
  that DaVinci Resolve reads the timecode of an audio-only `.mov`, and
  how Kdenlive places the display files and audio files.
- How the drift between an audio device's clock and the tick grid is
  corrected over hours. It is measured per audio file
  (`clockDriftPpm`, D49): up to 117 ppm (the Razer Seiren V3 Mini:
  0.42 s slow after an hour; one of five inputs), and
  `AVCaptureSession`'s timestamps do not correct it
  ([end-to-end-tests.md](end-to-end-tests.md), "What research found for
  the recorder"); correcting it is a later PR.

## Build state

Built (skeleton PR): `msr list`, `msr check`, `msr settings`,
`msr version`, the ready check and the app window with it ("What will
be recorded", "Check again", Start always disabled, "This build cannot
record yet."), the About window, the code layout above, and the tests of
the disk estimate, the ready check, the output folder probe, the audio
input listing, "What will be recorded", `msr list`, the version, the
exit codes and the scripts.

Built (settings and auto mode, PR A, D44): the settings file read
leniently and written only on save with `JSONEncoder`, auto mode, Native
as the looks-like size, the four audio modes (the audio inputs' transport
types read from Core Audio), the switch "Auto" and the two sliders in the
window, `--auto` and "What will be recorded" in `msr check`, the ready
check's probes with a seam and the window's refresh with its tests. It
captures nothing. The recording core builds the rest, in two PRs
(D45): B1 `msr record`, Start and Stop, the display files with their
timecode, display changes and the display check, the recording
manifest and the Dock badge; B2 the audio files, the
guide tracks, system audio and the default microphone followed.

Built (the recording core's displays, B1, D45): `msr record` with
`--duration`, Start and Stop in the app, the Dock icon, its badge and
the status window also for `msr record`, the app quitting after Stop
and not on its last window closing while it records, the ready check
held while recording, the recording folder claim, the recording manifest with
its display files and events, the shared clock, the tick grid with late
ticks, display files (HEVC, fragments of 2 s, the timecode track,
BT.709), the frame size, display identity by UUID, the settle time,
displays coming and going, failing streams with back-off, mirroring, the
main display, sleep and wake, the display check, a full disk and the
free space check, and keep awake. The frame rate is one value
(*data*); the tick grid, the timecode, the keyframe interval, the
late-tick bound (2 s) and the display check's limit (1 s of frames)
derive from it. Tested without a screen: the logic by unit tests, and
display files written from synthetic frames and read back (a constant
frame rate, the timecode, BT.709, a file never finalized readable up to
its last fragment). A finalized display file is a regular movie:
Apple's writer joins the fragments when it finalizes [KNOWN, the
tests]. Live capture is verified on the owner's Mac.

Built in B1 where this document leaves the detail open, provisional and
for the architect to settle: the encoder's quality target (0.5) and
ceiling (4 times the estimated rate); `msr record` prints `Recording
into <folder>` at its start and, at its end, how long it recorded, each
file with its state, each failure event and each problem; it ends with
an error (exit 3) when the manifest's `result` is `problems` (D47): a
file is not finalized or a file was ended by a failure, and
when the finalized manifest could not be written (the problem is told,
the app shows an alert after the person's Stop, never at logout, restart or shutdown, and the file on disk keeps no `ended`); `at` is rounded to
the millisecond; a display file whose name is taken (a new file within
the same second) gets " (2)"; the timecode of tick 0 is t0's time of
day rounded to the nearest frame; after a full disk, new display files
start once the free space is above the low disk warning threshold;
low disk space bounces the Dock icon until the app is activated; a
frame's rectangle passes the display check within 0.5 points of its
display's bounds.

Built (the recording core's audio, B2, D49): an `AVCaptureSession` per
recorded audio input, following the audio mode and the default
microphone; an unplug ending the audio file and a replug starting a new
one; a new audio file on a channel count change; the system audio from
a ScreenCaptureKit stream on the main display, moving with it; audio
files placed on the tick grid, gaps up to 1 s filled with silence, a
longer one ending the file; `clockDriftPpm` per audio file; the guide
tracks "Microphones" and "System audio" in every display file; audio
sources in the status window and the summary; audio files counted in
the low disk warning threshold; our process's CPU use in the status
window, the summary and the manifest. Tested without a microphone or a
screen: the logic by unit tests, audio captures with a stand-in source
and writer, audio files and guide tracks written from synthetic PCM and
read back. Live audio capture is UNVERIFIED until the owner's run.

Built in B2 where this document leaves the detail open, decided by the
architect on review: the failure events are named `audio input failed`,
`system audio failed`, `audio file writer failed` and `audio file
writer fell behind`; an event about an audio source names it in
`audioSource`, never in `display`; an audio source the audio mode
records but that has no file yet shows the state `not recorded`; an
audio input is recorded only when Core Audio gives its UID, which
`AVCaptureDevice` opens it by; the beginning of a recording tells no
`default microphone changed` or `audio input connected` events; the
system audio's stream asks for 2×2 pixels at 1 frame per second and
drops them; a display file's guide tracks may end up to 300 ms before
its last tick; the video track's name is written as QuickTime user
data `©nam`, which ffprobe shows as `title` (track-level metadata items
do not show and are not written; the file-level items are); `msr
record`'s summary ends with the line `CPU N % on average, N % at the
peak, of one core (this process only)`.

Open, for the owner's live run to answer: the system audio's timestamps
may follow the host clock rather than its sample count; then the
output device's clock drift would show as `audio input gap` events of
about 32 ms at a steady interval, each filled with silence. The gap
events of the run show whether it does.

Details the design left open, as built and confirmed by the owner
(D25, D28, D44): a key missing from the settings file takes its default;
the output folder must start with `/` or `~`; the two number settings
must be greater than 0 (an invalid one is ignored, see "Settings file").
`msr version` prints the full
version string and the commit, such as `0.20261115.2-dev+a1b2c3d (a1b2c3d)`,
from the bundle's Info.plist keys `MSRVersion` and `MSRCommit`;
outside a bundle it prints `development build (not bundled)`. The
settings file is found through `HOME`. The disk estimate follows its
rule, file by file (10.7 GB in the `msr check` example above). The
recording resolution box turns with a portrait display (1080×1920 for a
2160×3840 display at 1080p).

Further details, as built and decided by the architect for PR #1: an
unset `HOME` exits 78; `msr` that cannot re-execute
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

The owner ruled that a Mac without an audio input is ready in every
audio mode (D44, point 5).

Decided while building PR A, within D44, for the owner to confirm:
`msr check` prints "What will be recorded" before the ready check's
items, separated by a blank line, without the window's line "Recording
continues …"; a settings file that cannot be read as a whole is named
"the whole file" in the line on standard error; an input's transport
that cannot be read is not wired; `msr settings` with a flag that cannot
write exits 1; the window shows a red line when a save fails.
