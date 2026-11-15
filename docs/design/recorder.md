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
| `msr check [flags]` | Prints "What will be recorded", then runs the ready check and prints each item | 0 ready, 1 not ready |
| `msr record [flags] [--duration 1h30m]` | Not built yet (the recording core: B1 the displays, B2 the audio, D45). Without flags it does what Start in the window does, with the same settings file; it prints "What will be recorded" at its start, then runs the ready check, records until Ctrl-C, SIGTERM, SIGHUP, the duration or Stop in the Dock (below), and prints the recording folder at the start and a summary at the end. While it records, the app's Dock icon shows with its badge, and clicking it or Quit asks "Stop recording?" as in the app (D45) | 0 ok, 1 not ready, 3 ended with an error |
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
- The screen recording grant is proven, not just read: the check
  fetches the display list. The Microphone permission is read, and no
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
  included (B1 of the recording core builds this, D45).

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
    { "at": 1446.2, "event": "display disconnected", "display": "LG HDR 4K" },
    { "at": 2285.0, "event": "display frame size changed", "display": "Built-in Retina Display",
      "from": [1670, 1080], "to": [1662, 1080] }
  ]
}
```

`start`, `end` and `at` are seconds from the recording's start on the
shared clock. A display file's `displayUUID` is its display's identity (see
"Display identity"). The events: `display connected`, `display
disconnected`, `display frame size changed`, `display mirroring
started`, `display mirroring stopped`, `main display changed`,
`display stream failed`, `display shows another display's picture`,
`display file writer fell behind`, `disk full`, `sleep`, `wake`, and
for audio `audio input connected`, `audio input disconnected`, `system
audio started`, `system audio stopped`; each names its display or audio
source where it has one. `state` is `recording`, `finalized` or `not finalized`.
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
  refreshed whenever the ready check runs (D33): one table and a
  total line. The columns are Source, "Looks like", "Drawn at", "Records
  at" and GB/h, the last for every row and right-aligned. The widths of
  the columns after Source are measured at runtime from the widest
  possible content in the table's font ("8888×8888", "cannot be read",
  "not recorded" and so on, and the header), never from what is
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
    is dimmed and shows "not recorded": every input with the audio
    mode `none`; every input but the default one with
    `default-microphone`; with `wired` every input but the default one
    that is not built-in or wired; and the system audio row when it is
    off.
  - GB/h has one decimal; under 0.05 it shows "<0.1".
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
    cannot be read shows "cannot be read" in the Records at column (and "unknown" GB/h if it is recorded). The total line
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

- **Recording:** the window closes; the Dock icon shows a red badge with
  the elapsed minutes. Low disk space shows as a "!" badge and a
  bouncing Dock icon; no notification, which would need a third
  permission and is hidden by Focus modes.
- **Stop:** clicking the Dock icon or Quit asks "Stop recording?"
  [Stop] [Continue]. Stop finalizes, reveals the recording folder in
  Finder and quits the app: a recording is typically one shot (D45).
  Logout and shutdown finalize without asking. While a recording runs,
  the app does not quit when its last window closes, and the ready
  check does not run, also not when the app is activated.
  `msr record` shows the same Dock icon, badge and question; Stop there
  ends `msr record` as Ctrl-C does (D45).
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
loop and show the app's Dock icon (D45): macOS reports display changes
(`CGDisplayRegisterReconfigurationCallback`) only to a process running
`NSApplication.run()`, which the experiments of 2026-11-15 showed
([end-to-end-tests.md](end-to-end-tests.md), "What research found for
the recorder"). `msr record` stops on its signals through the same
path as Stop.

**Constant 30 fps (D11, D21).** Per display, a ScreenCaptureKit stream
delivers complete frames when the screen changes; the newest is kept.
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
display check (below).

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
guide tracks of every open display file. Which audio inputs are
recorded follows the audio mode (D44): `none` none, `default-microphone`
the default one, `wired` the default one plus every built-in and wired
one (transport type built-in, USB, FireWire, PCI, Thunderbolt, HDMI,
DisplayPort; Bluetooth, Bluetooth LE, virtual, aggregate, AirPlay,
Continuity capture, an unknown transport and one that cannot be read are
not wired), `all-inputs` every input. The default microphone is
recorded in every audio mode but `none`, whatever its transport. A
Bluetooth headset's microphone switches to call quality when recorded,
and a virtual microphone often carries a copy of other sound, so those
are recorded only under `all-inputs` or as the default microphone.

**Display identity.** A display is known by the UUID macOS gives it
(`CGDisplayCreateUUIDFromDisplayID`), never by its display ID, which
changes when a display comes back, nor by its name, which macOS may
change ("MSR Test (1)"). A display that comes back with the same UUID
keeps its number and its name in the file names for the whole
recording. Whether a real display keeps its UUID after it was
unplugged is UNVERIFIED (the owner's check on the first build).

**Displays coming and going (D14).** A display that appears gets a
stream and a display file (event `display connected`); one that
vanishes has its file finalized (event `display disconnected`). A
stream that fails finalizes its file and is restarted after 1 s,
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
crash markers, the version, the state file's content, the choice of
the crash report to offer, the new-issue link (and that the issue form
has the fields it fills), the name of a crash report's text copy, and
the text of the examples in this document, which the tests hold to the
code. `RecorderCoreTests` test
the output folder probe against scratch folders, and that this Mac's
audio inputs can be read and a listener for their changes registered,
which needs no permission and shows no prompt, the state file (missing,
saved, broken), the listing of the crash report folder (a missing one
is no crash reports, an unreadable one an error), the text copy of a
crash report, that an action
waiting for the main run loop's default mode runs only there, the
classification of Core Audio's transport types, and the ready check's
probes with stand-ins (the output folder's file access is off the main
thread). `AppTests` run the start window's model with stand-in probes
and a stand-in for the hold: one check per burst of device changes,
nothing applied while a menu is open, a stale queued refresh does
nothing, choices saved only when changed. `CommandTests` run
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

- Unproven until the owner's first real recording (D31): that DaVinci
  Resolve reads the timecode of an audio-only `.mov`, and how Kdenlive
  places the display files and audio files.
- What happens when the default microphone changes during a recording
  (the owner will rule).
- Whether `AVAssetWriter` writes a timecode track into an audio-only
  fragmented `.mov`.
- How drift between an audio device's clock and the tick grid is
  handled over hours. The drift is measured: up to 117 ppm (the Razer
  Seiren V3 Mini: 0.42 s slow after an hour; one of five inputs), and `AVCaptureSession`'s timestamps do not correct it ([end-to-end-tests.md](end-to-end-tests.md),
  "What research found for the recorder"); the design stays open.
- Two audio inputs with the same name.
- Characters in a device name that a file name cannot hold.
- The gain of the guide track "Microphones".

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
manifest, crash markers and the Dock badge; B2 the audio files, the
guide tracks, system audio and the default microphone followed. Until
B2, a display file has no guide tracks, and the window and `msr record`
say under the table "This build records the displays only; audio
comes with the next version."

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
