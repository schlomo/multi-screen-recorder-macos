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
| `msr list` | Prints "What will be recorded" as `msr check` does, from the settings and the devices, without the ready check and without asking for any permission, then whether the program running `msr` may record the system audio | 0, 1 when the screens, the audio inputs or an audio input the settings record cannot be read |
| `msr check [flags] [--debug]` | Prints the banner and "What will be recorded", then runs the ready check and prints each item; `--debug` also prints the detail lines on standard error (and at `.debug` in the unified log) | 0 ready, 1 not ready |
| `msr record [flags] [--duration 1h30m] [--debug \| --quiet]` | Records the screens, the cameras and the audio sources (the recording core, D45, D49, D74). Without flags it does what Start in the window does, with the same settings file; it prints the banner (as `msr check`) and "What will be recorded" at its start, then runs the ready check, records until Ctrl-C, SIGTERM, SIGHUP, the duration or Stop in the status window (below), and prints the recording folder at the start and a summary at the end (the summary: every file with its state, the screens' by number, then the cameras' by number, then the audio sources' by number with the system audio first, and our process's CPU use, average and peak, and, when it exits 3, the link to report it and the files to attach, see "Problem report offer"). It runs as a full AppKit app without a Dock icon (the `accessory` activation policy) until the ready check passed and the recording starts, then shows the icon; a run that is not ready shows none, and an icon macOS refuses is a problem, and the recording goes on (Ctrl-C stops it); while it records, the icon shows with its badge, and clicking it or Quit opens the status window as in the app (D45, D46). When it stops, for any reason, it first prints `Stopping the recording and finalizing the files…` on standard error, then finalizes and prints the summary; a Ctrl-C while it finalizes prints `Still finalizing the files…` and does nothing more. It prints every event of the recording manifest as one line on standard error, a failure's repeats counted instead (see "Logging"). `--debug` also prints the detail lines on standard error (and at `.debug` in the unified log); the recording log has them always (see "Logging"). **Output split:** standard output carries exactly one line, the recording folder's bare path, when recording starts; everything for people goes to standard error (the banner, "What will be recorded", the ready check, `Recording into <path>`, events, the status line, the summary, detail lines), all of it, and every other line this code writes on standard error (the settings file note, `Error:` lines, detail lines; ArgumentParser writes its own usage errors, before any status line exists), through one writer so nothing prints into the middle of the status line; a failed write to standard error, SIGPIPE included, is ignored, as there is nowhere left to report it, and `msr record` ignores SIGPIPE for the whole process from its start, before it writes anything, so a closed reader of standard output does not end it. **Status line:** only when standard error is a terminal whose `TERM` is set, not empty and not `dumb`, with no option: one line redrawn once a second (`\r`, the text, `ESC[K`). Its text, joined by ` · ` as the window's line is: `<n> problems` (`1 problem`) first when there are any, counting every time a problem was told in the run (one that comes back after it ended counts again, though the window shows a kind's repeats on one line; an audio input out of the guide track is not counted, D79; low disk space and a screen showing another screen's picture are not problems, though they set the Dock badge), nothing when there are none; then the text of the window's line (time with seconds, size written, files, free space), the CPU use when known, and `<n> screens, <m> audio` for the sources being recorded (`1 screen`; a stalled camera counts, as its file is still written), with `<k> cameras` between them when cameras are recorded (`2 screens, 1 camera, 5 audio`), such as `1 problem · Recording 0:12:34 · 1.2 GB in 7 files · 143.8 GB free · CPU 23 % · 2 screens, 5 audio`. It is cut to the terminal's width minus 1, taking 80 columns when the width is unknown, so it does not wrap. An event or detail line clears it, prints, and it is drawn again, all in one write; at the end it is cleared and the summary follows. Not a terminal: no status line and no escape code. **`--quiet`:** no output for people (no banner, table, passing ready check, events, status line or summary); still written are the path on standard output and, on standard error, a failing ready check, `Error:` lines, the settings file note, each failure and problem as it happens (a failure's event line, or the problem's own line when no event tells it) with the count of a failure's repeats, and the summary of a run that exits 3; exit codes are unchanged; with `--debug` it is a usage error. `--duration` takes hours, minutes and seconds (`1h30m`, `45m`, `90s`); a number without a suffix is minutes (`90` is 90 minutes) | 0 ok (every file finalized, no file ended by a failure, no camera stalled, D47), 1 not ready, 3 when the recording manifest's `result` is `problems`, the finalized manifest could not be written, or the recording could not start |
| `msr settings [flags]` | Without flags prints the effective settings as JSON (show); with any settings flag, `--auto` included, saves the run's effective settings into the settings file and prints them (change). The only command that writes the file; the window also writes it | 0, 1 when it cannot write the file |
| `msr timeline <folder>` | Writes the recording folder's timeline file (see "Output on disk") from its `recording.json`, replacing an older one, and prints its path. Reads no settings. Writes nothing else and deletes nothing. A file without an end gets its length from the media file | 0, 1 with the error on standard error when `recording.json` or a file's length cannot be read, or the file cannot be written |
| `msr version` | Prints the version and commit | 0 |

A usage error (unknown command or flag, invalid value) prints a usage
message and exits 64, the convention of Swift Argument Parser. Every
command that reads the settings (all but `msr version` and `msr timeline`) exits 78
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
| `--resolution` | `native`, `4k`, `1440p`, `1200p`, `1080p`, `720p`, `none` (audio only) |
| `--audio-mode` | `none`, `default-microphone`, `wired`, `all-inputs` |
| `--camera-mode` | `none`, `default-camera`, `real`, `all-cameras` |
| `--system-audio` | `on`, `off` |
| `--output-folder` | a folder |
| `--required-recording-hours` | a number |
| `--low-disk-warning-minutes` | a number |

`--resolution`, `--audio-mode` and `--camera-mode` set a choice and so
turn auto mode off for the run; `--auto` together with any of them is a
usage error (exit
64). `msr settings --resolution 1080p` writes `resolution: 1080p` and
`auto: false`, `msr settings --auto` writes `auto: true`: `msr settings`
with a flag writes the run's effective settings. There is no `--save`
(a usage error, exit 64): `msr settings` shows or changes.

`msr list` prints the table of "What will be recorded" that `msr check`
and `msr record` print (below), the same code, from the settings and the
devices connected now; it runs no ready check and asks for no
permission. Under the table it says whether the system audio can be
recorded, which depends on the program running `msr` (a terminal app),
not on the app: without the permission it says `System audio: not
available, the program running msr (a terminal app) lacks the Screen &
System Audio Recording permission`. For the devices below:

```
What will be recorded
  Settings: Auto (resolution Native, audio mode Wired, camera mode All real), system audio on, limit cameras on
  Source                                      Looks like  Drawn at   Records at  GB/h max
  ───────────────────────────────────────────────────────────────────────────────────────
  Screen 1 - Built-in Retina Display          1728×1117   3456×2234  1728×1116        1.0
  Screen 2 - LG HDR 4K                        3840×2160   3840×2160  3840×2160        4.1
  ───────────────────────────────────────────────────────────────────────────────────────
  Camera 1 - FaceTime HD Camera (default)                            1920×1080        1.1
  ───────────────────────────────────────────────────────────────────────────────────────
  Audio 0 - System                                                   stereo           0.1
  Audio 1 - MacBook Pro Microphone (default)                         1 channel        0.1
  Audio 2 - RØDE Wireless GO II RX                                   2 channels       0.1
  ───────────────────────────────────────────────────────────────────────────────────────
  Total                                                                               6.4
  2 hours need 12.8 GB.
  Files go to ~/Movies/Multi Screen Recorder
System audio: available
```

The settings line says the effective settings, flags applied: `Auto
(resolution Native, audio mode Wired, camera mode All real)` in auto
mode, otherwise `resolution 1080p, audio mode …, camera mode …`; at the
recording resolution None it adds that no screen and no camera is
recorded (`resolution None (no screen and no camera is recorded)`),
under the audio modes None and Default microphone why the inputs are
not recorded (`audio mode None (no audio input is recorded)`), and
under the camera modes None and Default camera why the cameras are not
(`camera mode None (no camera is recorded)`, `camera mode Default camera
(only the default camera is recorded)`). The screens are listed by
number, then the cameras by number (D74), the recorded ones first, then
those not recorded in device order, then the
audio sources by number, the system audio (0) first, then the audio
inputs not recorded in device order (the system audio too, last, when it
is off), so the numbers read 0, 1, 2 … without a gap. A source not
recorded keeps the column of the other names with the `Audio <n> - ` part
blank (at the recording resolution None the screens, with the
`Screen <n> - ` part blank and `-` in Records at too, D62), shows `-` in
GB/h max, and an audio input not recorded says why in
parentheses after its name, from the rule that leaves it out: under
Wired, the connection of an input that is not the default one and not
wired: `(virtual)`, `(Bluetooth)` (also Bluetooth LE), `(aggregate)`,
`(AirPlay)`, `(Continuity Capture)`, `(unknown connection)` for an
unknown transport or one that cannot be read; with any audio mode that
includes the input, `(no device ID)` when it has no Core Audio ID, as
the recording opens an input by it; under None and
Default microphone nothing, as the settings line gives the reason,
except that a default input without a Core Audio ID still says `(no
device ID)` under Default microphone. An input whose channels
cannot be read shows `cannot be read (<reason>)` in Records at. A camera
not recorded shows its name with the `Camera <n> - ` part blank and `-`
in Records at and GB/h max; it says `(virtual)` or `(Continuity
Camera)` when the camera modes Default camera and All real leave out a
virtual or an iPhone camera, `(no
format)` when it offers no format to record, `(suspended)` when the
camera mode would record it but it is suspended, and `(no Camera
permission)` when the camera mode would record it but the Camera
permission is denied (`msr list` reads the permission without asking); under None, at the
recording resolution None, and for a real camera not the default under
Default camera nothing, as the settings line gives the reason. A
camera's Records at is the frame size of its chosen format (see
"Cameras") fitted into the camera's box, the recording resolution's
limited to 1920×1080; Looks like and Drawn at stay empty.

In the table the "Looks like" column is what macOS calls "looks like" (a
screen's size in points) and "Drawn at" the size it is drawn at (its
pixel size), equal for most screens and different in a HiDPI mode (a
screen with a looks-like size of 1728×1117 draws 3456×2234 pixels);
"Records at" is the frame size, from the looks-like size, the one of the
recording resolution the settings choose: Native with auto mode, the
default. The drawn-at size is never recorded (D44). `--debug` shows a
screen as `looks like 1728×1117, drawn at 3456×2234`, or by its size
alone where both are equal.

`msr check` first prints a banner, the name with the version as
`msr version` shows it and the build date, such as `Multi Screen
Recorder 0.20261116.42 (9dc9443), built 2026-11-16`, then the
homepage's address and an empty line (`msr record` prints the same
banner first). Then it prints "What will be recorded": the window's
one table with its header row and total row, the line of what the
required recording hours need, and "Files go to <output folder>", from
the same code (see "The app"; the window's last line, "Recording
continues when screens, cameras or audio sources change.", is not printed), then
one line per item of the ready check, `ok` or `FAIL`, a fix under each
failure and under a denied Camera permission (wrapped at 80 columns, its continuation lines under its first
line's text), and `Ready.` or `Not ready.` last. For the devices of the
`msr list` example, the defaults and 3.1 GB free:

```
What will be recorded
  Settings: Auto (resolution Native, audio mode Wired, camera mode All real), system audio on, limit cameras on
  Source                                      Looks like  Drawn at   Records at  GB/h max
  ───────────────────────────────────────────────────────────────────────────────────────
  Screen 1 - Built-in Retina Display          1728×1117   3456×2234  1728×1116        1.0
  Screen 2 - LG HDR 4K                        3840×2160   3840×2160  3840×2160        4.1
  ───────────────────────────────────────────────────────────────────────────────────────
  Camera 1 - FaceTime HD Camera (default)                            1920×1080        1.1
  ───────────────────────────────────────────────────────────────────────────────────────
  Audio 0 - System                                                   stereo           0.1
  Audio 1 - MacBook Pro Microphone (default)                         1 channel        0.1
  Audio 2 - RØDE Wireless GO II RX                                   2 channels       0.1
  ───────────────────────────────────────────────────────────────────────────────────────
  Total                                                                               6.4
  2 hours need 12.8 GB, 3.1 GB free.
  Files go to ~/Movies/Multi Screen Recorder
```

then:

```
ok    Screen & System Audio Recording permission
ok    Microphone permission
ok    Camera permission
ok    Screens: 2
ok    Audio: system audio, MacBook Pro Microphone (default), RØDE Wireless GO II RX
ok    Output folder: ~/Movies/Multi Screen Recorder
FAIL  Free disk space: 3.1 GB in ~/Movies/Multi Screen Recorder, 12.8 GB needed for 2 hours
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
  "cameraMode" : "real",
  "limitCameras" : true,
  "lowDiskWarningMinutes" : 20,
  "outputFolder" : "~/Movies/Multi Screen Recorder",
  "requiredRecordingHours" : 2,
  "resolution" : "native",
  "systemAudio" : true
}
```

- **Auto mode.** `auto` is on by default. With it on, a recording uses
  Native, the audio mode Wired and the camera mode All real whatever
  `resolution`, `audioMode` and `cameraMode` say, and the system audio
  and the cameras' limit as their own switches say. The defaults of `resolution` (`native`),
  `audioMode` (`wired`) and `cameraMode` (`real`) are auto mode's
  choices, so turning auto off changes nothing until a slider is moved.
- **Camera mode (D74).** `cameraMode` chooses the cameras recorded:
  `none`, `default-camera` (the default camera only, if it is real),
  `real` (every real camera) or `all-cameras` (every camera, the
  virtual ones too). `limitCameras` (`--limit-cameras on|off`, the
  window's checkbox "Cameras at most 1080p", on by default): on, a
  camera's box is the recording resolution's limited to 1920×1080; off,
  the recording resolution's alone (see "Cameras").
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

Items, in this order: the Screen & System Audio Recording permission
(only when the recording records a screen or the system audio: audio
only without the system audio, the microphone alone, leaves the item
out and the permission is neither asked nor proven, D62), the
Microphone permission (only when the recording records at least one
audio input: with no audio input present, or none recorded under the
audio mode, the item is left out and the permission is neither asked nor
read), the Camera permission (D74: only when the camera mode records a
camera that is connected; without one the item is left out and the
permission is neither asked nor read; denied, it passes as `Camera
permission denied: no camera is recorded`, with its fix shown all the
same: allow it, or record no camera by turning off Auto and moving the
Camera mode slider to None, `--camera-mode none`; the recording then
records no camera, and the disk estimate counts none), the screens (at least one, each readable; at the recording
resolution None, where the free disk space counts no screen file, only
with the system audio, which is captured through the main screen:
`Screens: 2, none recorded (the system audio needs the main screen)`,
failing without a main screen or when the screens cannot be read, with
the fix to connect a screen or turn off the system audio; without the
system audio no screens item, and the screens fail nothing, D62), the chosen audio
sources, listed from the same model and in the same order as the table of what will be recorded (each audio input the audio mode records readable; another that
cannot be read does not count; with an audio mode but `none` the item
says "no microphone recorded" when no input is recorded, such as on a
Mac without any audio input or with only inputs the audio mode leaves
out or that have no Core Audio UID, and passes: no microphone works in
every audio mode, the screens and the system audio are recorded as
usual, and the item then reads `Audio: system audio, no microphone
recorded`, or `Audio: no microphone recorded, no system audio` with system
audio off; an input that is recorded and whose channels cannot be read
fails it), at the recording resolution None with no system audio and no
audio input recorded the item `Nothing to record: the recording resolution None
records no screen, and no audio source is recorded`, which fails (a
recording with neither screens nor audio refuses to start, D62), the
output folder, and free disk space in the output folder for
`requiredRecordingHours`.

- A permission that was never asked for is requested, so macOS shows
  its prompt; a denied one is reported with the System Settings path.
- The screen recording grant is proven, not just read, and proven again
  by every check: at the app's start, on "Check again", in `msr check`
  and in `msr record`'s own check the check captures one small frame of
  one screen (a ScreenCaptureKit screenshot), so macOS shows every
  prompt of a capture then and Start really starts (D46); the checks
  after a change (a device, a settings change, the app becoming active)
  only fetch the screen list. Whether the screenshot brings the prompt
  the owner saw at Start ("requesting to bypass the system private
  window picker") is UNVERIFIED until the owner's next run. The Microphone permission is read, and no
  microphone is opened (D36): the app
  crashed inside macOS after the default microphone was unplugged
  (owner's Mac, 2026-11-13), and the capture session an earlier ready
  check opened for a moment on every run is the cause [ASSUMED]. With
  no microphone connected, the permission item is left out and the audio
  item passes, saying "no microphone recorded", whatever the
  permission.
  The audio inputs are read from Core Audio's device list, which
  creates no capture object; if that list, the default audio input or
  the name of an audio input cannot be read, the audio item fails with
  the reason and `msr list` stops with it.
  The Camera permission is read the same way, and no camera is opened
  by the check; the cameras are read from AVFoundation's device list
  (D74).
- Output folder: the check creates it with its parents if it is
  missing, then writes and deletes a file in it; a failure names the
  path and the reason.
- Free disk space is measured on the output folder itself. Disk
  estimate, file by file at the encoding rates (*data*, see "Encoding"):
  a screen file is its video, 1 GB per hour at 1080p scaled by the
  pixel count of its frame size, plus its guide tracks; a camera file
  is estimated as a screen file of its frame size; an audio file is
  its tracks' bit rates. The item compares the total of every file the
  recording would write, for `requiredRecordingHours`, with the free
  space. For the devices of the `msr list` example at the defaults that
  is 6.4 GB per hour, 12.8 GB for 2 hours (the table in "The app" shows
  each file).
- One cause, one red item: when the output folder fails, or the
  screens, the audio inputs or an audio input the recording records
  cannot be read, the free disk space item is left out. With the audio
  mode `none`, audio inputs that cannot be read fail nothing.
- In the app the check runs when the window opens, when the app becomes
  active again (unless a check is still running), when a screen
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
  after a screen's backing scale (HiDPI) was switched, not in the
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
  2026-11-12 14.03.05 Screen 1 - Built-in Retina Display.mov
  2026-11-12 14.03.05 Screen 2 - LG HDR 4K.mov
  2026-11-12 14.03.05 Camera 1 - FaceTime HD Camera.mov
  2026-11-12 14.03.05 Audio 1 - MacBook Pro Microphone.mov
  2026-11-12 14.03.05 Audio 0 - System.mov
  2026-11-12 14.27.41 Screen 2 - LG HDR 4K.mov    ← back after a reconnect
  2026-11-12 14.41.10 Screen 1 - Built-in Retina Display.mov    ← new frame size after a mode change
  recording.json
  recording.log
  2026-11-12 14-03-05.otio    ← the timeline file
```

One file per source, each named by its own start time and the
source's label (D31, D55): a screen file per screen, a camera file per
recorded camera (D74), an audio file per recorded audio input and one
for system audio, each
`<date time> <label>.mov`. The manifest below lists exactly these
files; `recording.log`, the recording log, is next to it (see
"Logging").

**The timeline file (D68).** `<folder name>.otio` is an OpenTimelineIO
file, plain JSON written by our own code, in the form DaVinci Resolve 21.2
exports and reads: File > Import > Timeline loads every file of the
recording on its own track, in place by its timecode, at 30 frames per
second. Its name is the folder's name with every `.` replaced by `-`, and
every character outside printable ASCII and `/` and `:` too, since Resolve
names the imported timeline after the file name up to its first dot. It
is derived, rewritten whole every time and never read back. It is written
at Stop, by the app and by `msr record`, from the final `recording.json`
once that is written; if writing it fails the recording is unaffected, and
the error is told like a problem after the end, on standard error and in
the unified log (the recording log is closed by then). `msr timeline
<folder>` writes it from a folder's `recording.json`. A file without an
`end` (an unfinished recording) is measured from the media file itself.
Media are linked by file name only, relative to the timeline file.

- **Lengths** are the file's `end - start` in frames, rounded down, never
  up: Resolve drops the channel mapping of a clip one frame longer than
  its file. A file's first frame is its timecode in frames; the timeline
  starts at the smallest of them. A file after midnight is placed a day
  later than its timecode says, so it follows the earlier files; its clip
  keeps its own timecode (the files' own timecodes across midnight stay
  deferred). A file of zero frames gets no clip and no gap.
- **Tracks:** a video track per screen (the guide tracks are left off),
  V1 the longest of the screen files that start first (an audio file
  may start earlier), then the others by number; then a video track per
  camera by number, placed as the screens' (D74); then the audio tracks by source
  number: one stereo track for the system audio, and for an audio input
  with n channels n mono tracks, `<label>` for one and `<label>, channel
  <k>` for more. The channels of one file are a linked group in Resolve.
  A gap fills each space before a clip, none follows the last clip. A
  clip that starts before its track's previous clip ends, by a frame's
  rounding or an audio delay, leaves out its overlapping head, so what
  it plays stays at its own time.
- **Audio delay (D77, D80):** an audio file with `delays` is split at
  each entry's `at` into one clip per stretch, each placed earlier by
  its entry's `delay` less the smallest of the files' latest `delay`
  (never above 0, the anchor's; a file never measured and the system
  audio are not moved), so the earliest input is at 0, the
  stretch before the first entry by the first
  (the best known), rounded to the nearest frame, as the timeline
  places every clip at a whole frame, so up to 17 ms remain; a clip that
  would then start before the timeline's start, or before its source's
  previous clip ends, begins there instead, its first frames left out
  of its source range (its available range stays the whole file), so
  what it plays stays at its own time; a stretch placed later than the
  one before leaves a gap. Each stretch of a file with several channels
  is its own linked group. The audio files keep their sound as recorded.
- **Markers,** all on the timeline: the first, red, at frame 0, says in its
  name the resolution to set (the largest video file's frame size, which
  Resolve's reader has no key for) and in its note when it was recorded, how
  to read the markers and the problems; then one per frame that has events,
  blue if one of them is about a screen, else green, its note the events'
  lines; an event on frame 0 is added to the first marker's note.

**Labels (D55).** Every recorded source has a label,
`<kind> <n> - <name>`: `Screen <n> - <screen name>` for a screen,
`Camera <n> - <device name>` for a camera (D74),
`Audio <n> - <device name>` for an audio input, and always
`Audio 0 - System` for the system audio. The numbers count per kind
from 1. Screen 1 is the main screen; the others are numbered left to
right, later arrivals in order of appearance. Audio inputs are
numbered in the order they are first recorded, those at the start in
Core Audio's order. Cameras are numbered in the order they are first
recorded, those at the start the default camera first, then in
AVFoundation's order. A source keeps its number for the whole recording,
also when it comes back: a screen by its UUID, a camera by its
AVFoundation unique ID, an audio input by its Core Audio UID. So two audio inputs with the same name have different
numbers and nothing else tells them apart in a name.

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
  "settings": { "resolution": "1080p", "audioMode": "default-microphone", "systemAudio": true, "cameraMode": "real", "limitCameras": true },
  "files": [
    {
      "name": "2026-11-12 14.03.05 Screen 1 - Built-in Retina Display.mov",
      "screen": "Built-in Retina Display",
      "screenUUID": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
      "frameSize": [1670, 1080],
      "start": 0.0,
      "end": 2285.0,
      "timecode": "14:03:05:04",
      "state": "finalized",
      "guideTracks": ["Audio inputs", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.03.05 Screen 2 - LG HDR 4K.mov",
      "screen": "LG HDR 4K",
      "screenUUID": "1E6E43E3-6E7B-4C2A-9F6B-2B0F4C1A9D11",
      "frameSize": [1920, 1080],
      "start": 0.0,
      "end": 1446.2,
      "timecode": "14:03:05:04",
      "state": "finalized",
      "guideTracks": ["Audio inputs", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.03.05 Camera 1 - FaceTime HD Camera.mov",
      "camera": "FaceTime HD Camera",
      "cameraUniqueID": "47B4B64B70674B9CAD2BAE273A71F4B5",
      "frameSize": [1920, 1080],
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording",
      "guideTracks": ["Audio inputs", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.03.05 Audio 1 - MacBook Pro Microphone.mov",
      "audioSource": "MacBook Pro Microphone",
      "audioSourceUID": "BuiltInMicrophoneDevice",
      "channels": 1,
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording",
      "clockDriftCorrection": null,
      "clockDriftPpm": null,
      "inputVolume": 0.757,
      "delays": []
    },
    {
      "name": "2026-11-12 14.03.05 Audio 0 - System.mov",
      "audioSource": "System audio",
      "channels": "stereo",
      "start": 0.0,
      "end": null,
      "timecode": "14:03:05:04",
      "state": "recording",
      "clockDriftCorrection": null,
      "clockDriftPpm": null,
      "delays": []
    },
    {
      "name": "2026-11-12 14.27.41 Screen 2 - LG HDR 4K.mov",
      "screen": "LG HDR 4K",
      "screenUUID": "1E6E43E3-6E7B-4C2A-9F6B-2B0F4C1A9D11",
      "frameSize": [1920, 1080],
      "start": 1476.0,
      "end": null,
      "timecode": "14:27:41:04",
      "state": "recording",
      "guideTracks": ["Audio inputs", "System audio"],
      "framesRepeatedForLateness": 0
    },
    {
      "name": "2026-11-12 14.41.10 Screen 1 - Built-in Retina Display.mov",
      "screen": "Built-in Retina Display",
      "screenUUID": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
      "frameSize": [1662, 1080],
      "start": 2285.0,
      "end": null,
      "timecode": "14:41:10:04",
      "state": "recording",
      "guideTracks": ["Audio inputs", "System audio"],
      "framesRepeatedForLateness": 0
    }
  ],
  "events": [
    { "at": 812.4, "event": "audio input gap", "audioSource": "MacBook Pro Microphone", "length": 0.25 },
    { "at": 1021.7, "event": "audio input volume changed", "audioSource": "MacBook Pro Microphone",
      "from": 0.757, "to": 0.5 },
    { "at": 1446.2, "event": "screen disconnected", "screen": "LG HDR 4K" },
    { "at": 2285.0, "event": "screen frame size changed", "screen": "Built-in Retina Display",
      "from": [1670, 1080], "to": [1662, 1080] }
  ],
  "problems": [
    { "at": 600.0, "problem": "The free space in /Users/anna/Movies/Multi Screen Recorder cannot be read",
      "error": "The file “Multi Screen Recorder” couldn’t be opened because there is no such file. (NSCocoaErrorDomain 260; reason: The file doesn’t exist.): The operation couldn’t be completed. No such file or directory (NSPOSIXErrorDomain 2; reason: No such file or directory)",
      "errorDetail": { "domain": "NSCocoaErrorDomain", "code": 260,
        "description": "The file “Multi Screen Recorder” couldn’t be opened because there is no such file.",
        "reason": "The file doesn’t exist.",
        "underlying": [ { "domain": "NSPOSIXErrorDomain", "code": 2,
          "description": "The operation couldn’t be completed. No such file or directory",
          "reason": "No such file or directory", "underlying": [] } ] } }
  ]
}
```

`start`, `end` and `at` are seconds from the recording's start on the
shared clock. A screen file's `screenUUID` is its screen's identity (see
"Screen identity"). A camera file (D74) has the keys of a screen file,
with `camera` (the camera's device name) and `cameraUniqueID`
(AVFoundation's unique ID of the camera, its identity) in place of
`screen` and `screenUUID`; `settings.cameraMode` is the camera mode, and
a manifest written before cameras, without it, reads as `none`. The events: `screen connected`, `screen
disconnected`, `screen frame size changed`, `screen mirroring started`,
`screen mirroring stopped`, `main screen changed`, `screen stream
failed`, `screen shows another screen's picture`, `screen file writer
fell behind`, `screen file writer failed`, for cameras (D74) `camera
connected`, `camera disconnected`, `camera frame size changed`,
`camera orientation changed` (D76),
`default camera changed`, `camera stream failed`, `camera stalled`, `camera stall ended`, `camera file
writer fell behind`, `camera file writer failed`, then `disk full`, `sleep`, `wake`,
and for audio `audio input connected`, `audio input disconnected`,
`system audio started`, `system audio stopped`, `default microphone
changed`, `audio input gap`, `audio input failed`, `system audio
failed`, `audio file writer failed`, `audio file writer fell behind`,
`audio input volume changed`, `no audio started`, `no audio stopped`,
`audio input left the guide track`;
each names its screen (`screen`), its camera (`camera`) or its audio
source (`audioSource`) where it is about one; `screen` always means a
screen. `audio file
writer fell behind` comes in two shapes: without `error` when a capture
ended because its writer fell behind, and with `error` when samples were
lost at a file's end, so one recording can have it twice for the same
file. Their fields: `at`, `event`, `screen`, `camera` or `audioSource`; `from` and
`to` (the old and the new frame size) for `screen frame size changed`,
the old and the new default microphone for `default microphone
changed`, the old and the new frame size for `camera frame size
changed` and `camera orientation changed`, and the old and the new default camera for `default camera
changed` (either absent where there was or is none), and the old and
the new input volume, 0 to 1, for `audio input volume changed` (D69);
`mirrors` (the
screen mirrored) for `screen mirroring started`; `length` (seconds, to
the millisecond) for `audio input gap` and `camera stall ended` (from
the camera's last frame before the stall to its next); `offset` (the
file's distance in seconds from the staying group's earliest input,
negative when earlier, to 0.0001 s) for `audio input left the guide track` (D79); `error` (why, as one line) and
`errorDetail` (the same error as its full chain, below) for `screen stream
failed`, `screen file writer failed`, `camera stream failed`, `camera
stalled`, `camera file writer failed`, `audio input failed`, `system
audio failed`, `audio file writer failed`, and `audio file writer fell
behind` when samples were lost at a file's end. The manifest's `state`
is `recording` or `finalized`; a file's `state` is `recording`,
`finalized` or `not finalized`. `ended` is the local end time, as
`started`, and `result` is `ok` when every file is finalized, no file
was ended by a failure and no camera stalled, as a stall loses picture
(`screen stream failed`, `screen file writer
failed`, `disk full`, `screen file writer fell behind`, `screen shows
another screen's picture`, `camera stream failed`, `camera stalled`,
`camera file writer failed`, `camera file writer fell behind`, `audio
input failed`, `system audio failed`, `audio file writer failed`,
`audio file writer fell behind`; an unplugged audio input, a gap, a
change of the input volume and no audio are none), otherwise `problems`
(D47);
`cpu` is our process's CPU use over the recording, `averagePercent` and
`peakPercent` in percent of one core as Activity Monitor shows it,
sampled every second, to one decimal (encoding and capture in macOS's
own processes, `VTEncoderXPCService`, `replayd`, `WindowServer`, are not
in it); all three are null until the recording is finalized. `problems`
lists every problem told to the person, also those that leave `result`
`ok`, each with `at`, `problem` (what went wrong), `error` (the full
error text, or null) and `errorDetail` (the error detail, or null when
`error` is null). The **error detail** (D64) is the error with its full
chain: `domain` and `code` (as macOS gives them, such as
`AVFoundationErrorDomain` `-11800`), `description`, `reason` and
`suggestion` where macOS gives them, and `underlying`, the error detail
of every underlying error (`NSUnderlyingErrorKey`,
`NSMultipleUnderlyingErrorsKey`), 8 levels deep at most; the last level
kept has `"truncated": true` when it has more (left out otherwise). The recorder's own errors have
the domain `MultiScreenRecorder` (or their type's, such as
`RecorderCore.VideoFileWriterError`) with the system's error under them,
such as `cannot write <file>` with AVFoundation's error underneath.
`error` is the error detail as one line: each level's description, then
in parentheses the domain and code (left out for the recorder's own),
with a code that is a four-character code also as one (`1852797029
('nope')`), the reason and the suggestion, then `: ` and the underlying
errors, and line breaks become `⏎`. A problem made from an event has the event's name as its error
detail's description, with the event's error detail under it. A failure is told while recording, at its event's
time; when the file it ended also had a writer error, that error is a
second problem, the file's. A `result` of `problems` never comes with empty `problems` (D47):
should nothing have been told, finalizing adds one problem, "A failure
was not told while recording", naming the first failure and how many
failure events there were (or, without a failure event, the first file
not finalized). The net only guarantees that `problems` is not empty
when the result is `problems`; a failure not told while some other
problem was told appears only in `events`. `events` and `problems` are
written in the order of their time. An audio file's `audioSource` is the
audio input's device name or `System audio`; `audioSourceUID` the
input's Core Audio UID, absent for the system audio, which tells two
inputs with the same name apart (D55); the events name an audio input by
its device name only and carry no UID, so they cannot tell two such
inputs apart; `channels` the number of its mono tracks, or `stereo` for
the system audio; `clockDriftCorrection` the seconds of sound the clock
drift correction added during the file (negative: removed), to 0.0001 s,
null until the file ends; `clockDriftPpm` its audio source's clock drift
as shown at the file's end (see "Audio"), to 0.1 ppm, null until the
file ends and if it was not measured by then; `inputVolume` an audio
input's input volume at the file's start, 0 to 1 to the thousandth,
null when it cannot be read, absent for the system audio (D69);
`delays` the file's audio delays (D80), for a processor of the files
to line the audio inputs up: a list of `{at, delay}`, in order; empty
only when the file was never measured (it is then placed as recorded).
While recording, and after a crash, it holds the live entries, one per
change of the value; at Stop, before the timeline file is written, each
file's list is rewritten with hindsight: its stretches are bounded only
by the changes of the 60 s rule, each with the median of the
counted windows ending within it, one with fewer than 2 keeping its
live value (the better estimate then), neighbours within a frame
merged, the first at 0, so a file whose audio delay the 60 s rule never
changed has one entry; the anchor's files and a file without own counted windows
keep theirs (see "Audio delay", D80). `at` is the
seconds into the file from which the entry holds (to the millisecond,
never below 0; the first entry also holds before its `at`, as the best
known); `delay` is the seconds by which the file's sound there is later
than the recording's anchor's, the first input whose file is written (to
0.0001 s, negative when earlier). To line up the recording's audio
inputs, place each file's stretch from `at` on earlier by `delay` less
the smallest of the files' latest `delay` (taken as 0 when that is
above 0); a file with an empty list and the system audio are not moved;
the timeline file does exactly this. The anchor's files list
`{at: 0, delay: 0}` (a device that becomes the anchor later gets that
entry from then on); the system audio's list is always empty; a new
file of an input starts with its earlier file's value as its first
entry at 0. How a
value came about (the measurements, the rules, a carry-over) is in the
detail lines of `recording.log` only (see "Logging"). The list is
written for files being written, and an ended file keeps it. Earlier recordings' `measuredDelay` is not read
(D80). `files` lists the screen
files, the camera files and the audio files in the order of their start.

**Names in a file name (D49, D55).** In a file name, `/` and `:` in a
label become `-`, so a device name never stops a source from
recording.

**Metadata in every file (D46, D49, D55).** The timecode track names
the source as its reel name (the source reference name of its format
description): the source's label, its name unchanged. It is written with the track, so a file never finalized keeps it.
Each track is named in its user data full name (`©nam`), the one
track-level item `ffprobe` shows (as the stream's `title`, checked on
2026-11-16; items in the track's `mdta` metadata it does not show): a
screen file's video track by the reel name, its guide tracks
`Audio inputs` and `System audio`, an audio file's tracks
`<label>, channel <n>` (`Audio 1 - MacBook Pro Microphone, channel 1`)
or, for the system audio, `Audio 0 - System`. A screen file's QuickTime
metadata items, all text, under `org.schapiro.multiscreenrecorder.`:
`screenUUID`, `screenNumber`, `screenName`, `frameSize`
(`1920x1080`), `recordingStarted` (as the manifest's `started`) and
`app` (as the manifest's `app`); a camera file's the same with
`cameraUniqueID`, `cameraNumber` and `cameraName` in place of the
screen's three (D74); an audio file's: `audioSource`,
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

- **Start:** a small window. At the top, the app icon, the name, the
  version and a link to the homepage (`Homepage.url`, defined once),
  and on the right the tagline in two lines, "Every screen, every camera, all audio."
  and "Keeps going when things change." (`Tagline.lines`, defined
  once; on the homepage too, in the same two lines), right-aligned,
  in italics and the secondary text colour; neither line wraps (D55).
  Then a section "What will be recorded", built from the settings and
  the devices connected now and
  refreshed whenever the ready check runs (D33): one table, with a
  header, striped rows and a border, and its total row. The columns are
  Source, "Looks like", "Drawn at", "Records
  at" and "GB/h max", the last for every row and right-aligned. GB/h max
  is the encoder's ceiling (`kVTCompressionPropertyKey_DataRateLimits`),
  the most a source can write, and the disk checks rely on it; what one
  hour writes is usually less (D53). The widths of
  the columns after Source are measured at runtime from the widest
  possible content in the table's font ("8888×8888", "cannot be read",
  "888.8" and so on, and the header), never from what is
  connected, so no column moves when auto mode or a slider change.
  Source is as wide as the kind's icon and the longest name connected
  now, each measured with the number "88", so that a setting that
  numbers a source or not moves nothing; no cell wraps or is cut (the
  row's mouse-over starts with the label, with "(default)" after it
  for the default input). The window is as wide as the table, or as the tagline header
  when that is wider, and Source then takes the rest; it is never
  narrower than the controls below need, and the text below the table,
  such as the audio mode's explanation, wraps to that width instead of
  widening the window. So the window's width follows the devices'
  names, not the settings.
  - Source shows each source as an SF Symbol for its kind (`display` for
    a screen, `mic` for an audio input, `speaker.wave.2` for the system
    audio), then its number and its name, as its label numbers it (D55):
    the screens and the recorded audio inputs from 1, those in the order
    listed, the system audio 0 and named "System". A source not recorded
    gets no number. Whether an audio input is recorded follows the
    recording's own rule (`AudioTracker.records`): the audio mode
    includes it and it has a Core Audio UID, so an input without one is
    dimmed, unnumbered and left out of the total. A screen that mirrors
    another is left out by both, so they number the screens alike: the
    recording skips it, and macOS does not list it to the window at all
    (the owner's Mac, 2026-11-16: with the DELL P3421W mirroring the
    Wacom One 13T, `msr check` of `v0.20261116.40` listed only "1 Wacom
    One 13T"; D55). `msr check` prints the label as text instead
    (`Screen 1 - Built-in Retina Display`), the default input marked
    "(default)" after it (`Audio 1 - MacBook Pro Microphone (default)`).
  - Every source row's mouse-over (SwiftUI's `.help`, on the whole
    row) shows the technical details of how it is recorded, built by
    `SourceDetails` as plain "Label: value" lines under the row's full
    label, a potential problem as a "Note:" line. A screen: looks like,
    drawn at, records at, refresh rate, the colour it is recorded in
    (BT.709, SDR, HEVC 8-bit), display ID, main screen or not. A camera:
    its kind (USB, built in, iPhone or virtual) and unique ID, a USB
    camera's link speed (IOKit's `USBSpeed` of the `IOUSBHostDevice`
    whose `locationID` the unique ID starts with, such as `0x20522000`
    in `0x20522000046d085e`; a property Apple marks as subject to
    change, "cannot be read" without it), each size it offers once with
    its frame rates, the format chosen and why (the largest recorded
    size, `limited to 1080p` or `1080p limit off`, `turned as the
    camera's active format` where the orientation broke a tie, `kept:
    another app uses it`), the frame rate the recorder sets or the
    range another app left, whether another app uses it and whether it
    is suspended; notes for a frame rate below 30 fps (how many of
    every 30 frames repeat the one before), more than 1080p over a USB
    2 link (480 Mb/s) and another app's use. An audio input: channels,
    its sample rate (recorded at 48 kHz), connection, input volume and
    whether it can be set, default microphone or not, the Core Audio
    UID and how it is recorded. The system audio: what it captures and
    its format. Not shown: whether a USB 2 camera shares its USB bus
    with an audio input, as Core Audio gives no USB location for an
    audio input.
  - Screen rows first: the number and name, "Looks like" (the size in
    points), "Drawn at" (the pixel size, shown also where both are
    equal), "Records at" (the frame size) and GB/h max (the screen file,
    its guide tracks included). At the recording resolution None every
    screen is a source not recorded (below): no number, `-` in Records
    at and GB/h max, dimmed (D62).
  - A thin divider, no second header, then the audio rows: the name of
    each audio input (the default one marked "(default)") in Source,
    Looks like and Drawn at empty, its number of channels in Records
    at ("1 channel", "2 channels", "cannot be read"), and GB/h max (the
    audio file); the first row is the system audio with "stereo", then
    the inputs by number, then the audio sources not recorded in device
    order (D59): every input with the audio mode `none`; every input
    but the default one with `default-microphone`; with `wired` every
    input but the default one that is not built-in or wired; an input
    without a Core Audio ID; and the system audio row, "System audio"
    without a number, when it is off, last. A source not recorded is
    dimmed, its name starts where the other names start (the number's
    width stays blank), its GB/h max is `-`, and an audio input not
    recorded says why in parentheses after its name, as `msr list`
    does (`(virtual)`, `(Bluetooth)`, `(aggregate)`, `(AirPlay)`,
    `(Continuity Capture)`, `(unknown connection)`, `(no device ID)`; no
    reason under `none` and `default-microphone`, whose settings line
    gives it, except `(no device ID)` for the default input under
    `default-microphone`).
  - The table's digits are all one width, so the GB/h max figures, the
    Total's included, line up on the decimal point; only the word
    "Total" is bold.
  - GB/h max is numbers only (D46), with one decimal; under 0.05 it shows
    "<0.1", and "?" when the rate cannot be told (an input whose
    channels cannot be read).
  - The total row, after a divider: "Total" in Source and the sum in
    GB/h max. Below the table the line "<requiredRecordingHours> hours
    need <y> GB, <z> GB free.", without the free part while the free
    space is unknown (the ready check has not finished yet, or its
    output folder item failed).
  - Below, "Files go to" and the output folder, a link that opens it in
    Finder (an alert says so if Finder cannot), and "Recording continues
    when screens or audio sources change." If the screens cannot be read, that error
    stands as a red line above the table, which then has no screen
    rows; if the audio inputs cannot be read, "The audio inputs cannot
    be read: <reason>" stands as a red line above the table too, which
    then has the system audio row only; an audio input whose channels
    cannot be read shows "cannot be read" in the Records at column (and "?" GB/h max if it is recorded). The total row
    and the line below it appear only when the screens (not at the
    recording resolution None) and every recorded audio input can
    be read. The ready check's items stay as they are.

  Then a switch "Auto", on by default: the three sliders are always shown, so
  that the switch shifts nothing: on, they are disabled (grayed out) and
  show auto mode's choices, Native, Wired and All real, not the saved values, and
  a caption says what auto mode records ("Every screen at Native, the
  audio mode Wired, the camera mode All real."); off, they are enabled and show the saved values: the recording resolution (over None,
  which records no screen (D62), then 720p, 1080p, 1200p, 1440p, 4K,
  Native, smallest to largest) and the audio
  mode (over None, Default microphone, Wired, All), each with the chosen
  one's name beside it. Under the audio mode slider the window says:
  "Bluetooth and virtual microphones are recorded only under All, or
  when they are the default microphone: recording a Bluetooth headset's
  microphone switches it to call quality, and a virtual microphone
  often carries a copy of other sound." Then the camera mode slider
  (D74, over None, Default camera, All real, All) with the chosen one's
  name beside it, and under it: "Virtual cameras and iPhone cameras
  (Continuity Camera, Desk View) are recorded only under All: a virtual
  camera often carries a copy of a screen or of another
  camera." Under that the checkbox "Cameras at most 1080p" (the setting
  `limitCameras`), enabled whenever cameras are recorded (not under the
  camera mode None or at the recording resolution None) and, as the
  system audio, its own switch, not set by Auto. Then system audio and output
  folder, which stay as they are; the ready check, with "Check again";
  and, in the lower right corner, Cancel and Start, Start on the right
  in blue as the call to action. Cancel quits the app without
  recording, as Cmd-Q does. Esc presses Cancel and quits; Return
  presses Start. A change of a choice is saved at once; if the settings file
  cannot be written, a red line says so. The window has no "Reset to
  defaults": a settings file is never refused.
  The table and the line below it are the same data that `msr check`
  prints as text.
   All green,
  the ready check is one line, "Ready to record", that expands on click
  to its items; any red item shows every item, with the fix under each
  red one and under a denied Camera permission. Start is disabled while the ready check fails. For the
  devices of the `msr list` example, the defaults and the free space
  of the `msr check` example, the section shows:

| Source | Looks like | Drawn at | Records at | GB/h max |
|---|---|---|---|---|
| Screen 1 - Built-in Retina Display | 1728×1117 | 3456×2234 | 1728×1116 | 1.0 |
| Screen 2 - LG HDR 4K | 3840×2160 | 3840×2160 | 3840×2160 | 4.1 |
| Camera 1 - FaceTime HD Camera (default) |  |  | 1920×1080 | 1.1 |
| Audio 0 - System |  |  | stereo | 0.1 |
| Audio 1 - MacBook Pro Microphone (default) |  |  | 1 channel | 0.1 |
| Audio 2 - RØDE Wireless GO II RX |  |  | 2 channels | 0.1 |
| Total |  |  |  | 6.4 |

2 hours need 12.8 GB, 3.1 GB free.

- **Recording:** the window closes; the Dock icon has no badge while
  all is well, no timer (D47). Low disk space shows as a "!" badge and a
  bouncing Dock icon; no notification, which would need a third
  permission and is hidden by Focus modes. A recording problem (the
  recording manifest or the recording log cannot be written, the screens or the free space
  cannot be read, a screen file's or an audio file's writer fails, an
  audio source's capture fails) shows the same way,
  and the status window lists it (red when broken, orange for a hiccup, D78); `msr record` also names each
  on standard error.
- **Status window (D46):** clicking the Dock icon while recording opens
  a small window, and Quit opens it too: a table with a row per screen,
  then a row per camera the recording records or recorded (D74; its
  Records at its frame size, its Clock drift empty; with the Camera
  permission denied, each camera the camera mode would record, not
  numbered, State `no Camera permission`), then a row per audio source the recording records or recorded (the
  system audio first, then the audio inputs by number), and the columns Source
  (as in the start window: the kind's icon, the number and the name),
  "Records at" (a screen's frame size; an audio source's `1 channel`, `2
  channels` or `stereo`), Files, Written (its files on disk, below 1 GB
  in whole MB, from there in GB with one decimal), State (`recording`,
  `waiting`, `failed, retrying`, `shows another screen`, `disk full`,
  `mirroring`, `disconnected`, `asleep`, for an audio input no
  longer in the audio mode, such as the default microphone before a
  change, `not recorded`, for one with no audio `no audio`, see
  "Audio", and for a camera whose stream stalled `stalled`, see
  "Cameras") and "Clock drift" (an audio source's clock
  drift while it records, with the sound the correction added so far,
  `-116 ppm (+34.9 ms)`; `measuring (+0.3 ms)` until the clock drift is
  known, `measuring` before any correction; zero is `0`, never `+0` or
  `-0`; empty for a screen; for an audio input's file being written,
  uncoloured and short, `· synced 553 ms`, how much earlier the
  "Audio inputs" mix places the file, once its audio delay is set or
  confirmed by its own windows, `· synced 533 ms (carried)` while it
  holds its earlier file's, `· not synced yet` before it has one,
  `· no clear sound` once its file had sound in 3 measurements
  (`audioDelayUnclearMeasurements`, *data*) without a counted window
  (it is still recorded and joins once a window counts); the row's
  mouse-over adds the full reason as its last line: `Placed 553 ms
  earlier in the guide track, in line with the earliest microphone;
  measured` (or `; carried over from its previous file until
  measured`; for the anchor's own file, which an earlier input moves,
  the placement alone, as its audio delay is 0 by definition),
  `Not in the guide track until its audio
  delay is measured; its own audio track is recorded`, `Not in the
  guide track: no clear sound to measure its audio delay against; its
  own audio track is recorded`;
  nothing where the mix places it at 0 (to the millisecond), the
  reference's file or any other, and nothing for a file out of the guide
  track, which its problem line tells; see "Audio delay", D80), then, drawn for an audio source only,
  "Level" (its level meter) and "Input volume" (an audio input's
  slider, where its input volume can be set; see "Audio", D69). Each
  row's mouse-over shows the source's details as the start window's
  does (a screen's without drawn at and refresh rate, which the
  recording does not read; a camera's as read last, "in use by another
  app" meaning that its file kept the format another app set, as a
  reading during the recording counts the recording's own use), then
  what is known while it records: a video file's frames repeated for
  lateness and placed late so far (`This file so far: …`), a camera's
  `Stalled: yes` or `no`, an audio source's clock drift and an audio
  input's audio delay (above); under
  it the line "Recording 1:07:00 ·
  1.3 GB in 3 files · 120.4 GB free", the elapsed time as `h:mm:ss`
  (D47) and the sizes as in Written; then "CPU 23 %", our process's CPU
  use in percent of one core as Activity Monitor shows it, sampled every
  second, with the line "Encoding and capture also run in macOS's own
  processes (VTEncoderXPCService, replayd, WindowServer), which this
  number does not include."; the problems (below), with a line naming
  the recording's `recording.json` and `recording.log` for a report
  (see "Logging"); and, in the lower right corner, Continue and
  Stop, Stop on the right in blue as the call to action. The window is
  as wide as its table, no cell wrapping or cut, and the text below,
  such as the CPU line's explanation, wraps to that width. As in the
  start window, the columns after Source are as wide as their widest
  possible content (`8888×8888`, `888`, `888.8 GB`, the longest of every
  State's text, `RecordingStatusTable.StateText`, and `-8888.8 ms
  (-1000 ppm)`), so the width stays the same during a recording and
  changes only with the source names; the level meter and the slider
  are 120 points wide each. Esc presses Continue; Return
  presses Stop. It refreshes every second while open, the level meters
  and the sliders 10 times a second (*data*); Continue closes
  it. A screen file whose size cannot be read makes its screen's Written
  `?`, and the line's data written `? GB`. Free space that the volume
  does not report is a problem as a failing read is. A problem goes into
  the recording manifest, which is written at once (unless writing it is
  the problem); one that repeats, such as the free space that cannot be
  read on every check, is told once (one manifest entry, one line in
  the window, one line on standard error, one bounce) until it clears,
  and again if it comes back. **Problem lines (D78):** red marks something
  broken that a person must fix, or a recording not usable as it is;
  orange a hiccup in a recording that worked. Red while it lasts: the
  Camera permission missing; a screen, camera or audio source whose
  file a failure ended (its writer failed, its stream failed) and an
  audio file whose writer failed, until a new file of that source
  starts; a full disk, until there is room; the recording log or the
  recording manifest not written, the free space not read (a person
  should look at the disk), the screens or the audio inputs not read
  until the next read works (a new source might go unrecorded). Red
  always: a screen, camera or audio file lost in part (it lacks
  content), an audio input that cannot be recorded, the audio inputs'
  changes that cannot be followed. Red while it lasts, its own line: an
  audio input silent right after its gaps (D81, see "No audio"), `Audio
  <n> <name> sends only silence since its gaps at 0:25; unplug and plug
  it in again`, and once its sound returns or it disconnects `Audio <n>
  <name> sent only silence for 1:05 after its gaps at 0:25, recovered`
  (or `, then disconnected`, `, stopped` when its capture ended
  otherwise), orange. Orange: everything else once it is
  over, a failure followed by a new file of its source included, and
  always a camera stall (its file goes on), the Dock icon not shown, an
  input volume not set or not followed, a video file's guide tracks cut
  before its video (the video is intact) and the timeline file not
  written (the media are intact), and an audio input out of the
  "Audio inputs" guide track (D79), which also neither bounces the
  Dock icon nor sets the badge nor counts in the status line. A failure of a file whose source has
  started a newer file is over when told, so it is orange at once; a
  full disk, guide tracks cut or a file lost in part never is. A line
  only shown, as a video file's end the manifest lists already, never
  keeps a problem of its kind told after it from the manifest. A
  problem still lasting at the end keeps its colour by this rule. Each
  kind has its own words and names its source, such as `Screen 1 DELL not
  captured`, `Camera 2 BRIO stalled`, `Free space not read`, `Disk full`,
  `File <name> incomplete`, `Guide tracks of <name> cut`, and one line
  (an audio input out of the guide track has its own, see "Guide
  tracks"):
  `<words> since 0:12` while it lasts, `<words> for 4.0 s at 0:12,
  recovered` once over because its source works again (`, then
  disconnected` when its source went away: unplugged, or a screen gone,
  also at once for a screen's or a camera's failure told after it
  went; `, stopped` for a stall whose capture ended without recovering
  and without a disconnect), and when it came more than once
  `<words> 3 times, 12 s in total` (the ongoing one counted to now),
  with its ending once none lasts; then the
  latest error after a colon, `latest: ` before it when the errors
  differ. A stall reads `Camera <n> <name> stalled since 0:53` and `Camera
  <n> <name> stalled 7.4 s at 0:53, recovered`, without its error, always
  the same. A stall began at its end minus its length, or, while it
  lasts, 2 s (the stall limit) before it was told; another problem
  began when it was told. A stall ends when frames come again, when a
  new file of the camera starts, or at its capture's end (unplugged,
  out of the camera mode, Stop), its length then up to that end,
  `, stopped` unless unplugged. Times
  are `m:ss` since the start, `h:mm:ss` from an hour on; lengths have
  one decimal below 10 s as rounded, whole seconds from there (rounded
  once, so 10.45 s is `10 s`), `m:ss` from a minute on. The red lines
  come first, then the orange ones, each newest first; the area shows
  at most 5 lines, more scroll inside it, so the window never grows
  past that for problems; the line naming the files for a report stays
  below it. The recording manifest's `problems`, the result, the exit
  code and the lines on standard error are unchanged; the status line
  counts every time a problem was told, except an audio input out of the
  guide track.
- **Stop:** Stop in the status window finalizes, opens the recording folder itself
  in Finder (D46) and quits the app: a recording is typically one shot (D45).
  Logout, restart and shutdown finalize without asking, told apart from
  a Quit by the quit Apple event's reason (`kAEQuitReason`); one that
  comes while Stop is in progress waits for it. A failing writer and a
  full disk are a recording problem also when no screen file had
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
  shown, it looks for the newest crash report of the app
  (`~/Library/Logs/DiagnosticReports/msr-YYYY-MM-DD-HHMMSS.ips`, top
  level only) whose name is greater than `lastOfferedCrashReport` in
  the state file (nothing there: any crash report) and whose `procPath`,
  the path of the program that crashed, is inside a bundle named
  `Multi Screen Recorder.app` (D70); a report of any other `msr` (a test
  run, a stray `msr`, `msr` run from `.build/`) is skipped silently, and
  is read again at the next start; so is a crash report that cannot be
  read or names no program (no `procPath` in it), with no alert. If there is one, a dialog "Multi
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
  to drag into the issue; the dialog asks, for a crash while recording,
  for that recording's `recording.json` and `recording.log` too (D64); GitHub takes no file through a link. The app
  opens no connection itself (D15, D40). The state file is read once
  for this offer and the problem report offer below; one that cannot be
  read or decoded shows one alert "Cannot offer to report a crash or a
  recording's problems" with the error, and nothing is offered that
  start. A crash report folder that cannot be read, or a failed write,
  shows an alert "Cannot offer the crash report" with the error; a failed text copy (the dialog was
  already answered) shows "Cannot copy the crash report" with the
  error; a browser that cannot be opened shows
  an alert with the address.
- **Problem report offer (D64):** at Stop, in the app and in `msr
  record`, the state file's `lastRecording` remembers the recording
  folder's path and how the recording ended: `result` `problems` when
  `msr record` exits 3 for it (the manifest's `result` is `problems`
  or the final manifest could not be written), otherwise `ok`, with
  `noticeShown` false. A state file that cannot be read or written
  there leaves the recording unremembered: an `Error:` line in `msr
  record`, an alert "The recording is not remembered" after the
  person's Stop in the app, the unified log at logout. When the app
  starts, after the crash report offer, a last recording with
  `problems`, not shown yet, whose folder is still there, gets the
  notice "The last recording had problems" with its folder, [Report a
  problem] [Dismiss]; `noticeShown` is stored before it shows, so it
  shows once. Report a problem opens the browser on a new issue with
  the form `.github/ISSUE_TEMPLATE/problem-report.yml`: `version` (as
  `msr version` prints it) and `what-happened` filled, the summary's
  `Error at` and `Problem at` lines read from the recording's
  `recording.json`, the last first (and the line that it has no end,
  or that it cannot be read), as many as keep the link within 8000
  characters (*data*; GitHub's limit is about 8 kB [ASSUMED]), then `…
  and <n> more, in recording.log and recording.json.`; and it shows
  that recording's `recording.json` and `recording.log` in Finder for
  the person to drag into the issue (the form's `files` field). Errors as in the crash report offer:
  "Cannot offer to report the last recording", or the address when the
  browser cannot be opened. `msr record` whose summary says it exits 3
  ends it, also with `--quiet`, with `Report it: <the same link,
  built from the summary's lines>` and `Attach: <recording
  folder>/recording.log and recording.json`. Both the crash report and
  the problem report build their links in one place (`IssueFormLink`).

## How the recorder works

**Shared clock.** Everything runs on one clock that counts sleep
(`mach_continuous_time`). The recording's start t0 is one instant on
it; every timestamp in every file and in the manifest is an offset from
t0. The host clock that frames and audio buffers are stamped with does
not advance while the Mac sleeps, so a buffer's time is converted by
the difference of the two clocks, read at the start and again at every
wake; no file spans a sleep (see "Screens coming and going"), so the
conversion within a file is exact. A file starting after a wake so
keeps its place on the timeline and its timecode the time of day.

**Event loop.** The app and `msr record` run the same AppKit event
loop and show the app's Dock icon, `msr record` once the recording
starts (D45, D46): macOS reports screen changes
(`CGDisplayRegisterReconfigurationCallback`) only to a process running
`NSApplication.run()`, which the experiments of 2026-11-15 showed
([end-to-end-tests.md](end-to-end-tests.md), "What research found for
the recorder"). Both start it from `main` itself, at the same
synchronous point, with `msr record`'s arguments parsed before: an
event loop started inside a main-queue job, such as after the first
`await` of an `async` `main`, never drains the main queue again, so no
task, signal source or screen change would reach the recorder.
`msr record` stops on its signals through the same path as Stop.

**Audio only (D62).** At the recording resolution None the screen
tracker follows no screen: no stream, no screen file, no screen event
and no screen row in the status window. With the system audio the
screens are still read, as its stream follows the main screen; without
it the recorder neither reads the screens nor follows their changes, so
a microphone recording never fails for a screen. No camera is recorded
either (D74): the cameras are not read and the Camera permission is not
asked. Everything else runs
as with screens: the audio files, `recording.json` (its settings say
`"resolution": "none"`), sleep and wake.

**Constant 30 fps (D11, D21).** Per screen, a ScreenCaptureKit stream
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
6 s of ticks wait (*data*, D53); a writer further behind ends its screen
file with the event `screen file writer fell behind`, and a new
screen file starts, as after a failing stream. The v1 gate's clock
recording checks this from outside the recorder. A screen file starts
at the first tick after its stream's first frame that passes the
screen check (below), and never before the stream's own start. A
screen file and a camera file end at the tick at or before the moment
their end was asked (Stop, sleep, a change or a failure), however long
the stream then takes to stop: an audit of a 240 s recording on the
owner's Mac, 2026-11-23, found a suspended FaceTime HD Camera's
`stopRunning` blocking about 2.6 s and its file, ended when the stream
had stopped, repeating its last frame 77 times after Stop, and every
file at Stop 0.10 s to 0.27 s of frozen tail. When a file ends, the
ticks due by then are written, then those still waiting,
for at most the late-tick bound (6 s, D53) on a clock that does not count
sleep, and the file is finalized also when the writer fell behind or
the wait ran out; what failed is in the manifest.

**Timecode (D21, D31).** Every screen file and every audio file
carries a timecode track: local time of day at 30 fps, non-drop, the
clock time also on a day with a daylight saving change. A screen
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
track; in a screen file 64 kbit/s for the guide track "Audio inputs"
and 96 kbit/s for the guide track "System audio". Every screen is
recorded in SDR, also one
in HDR mode, with its colour space tagged so editors show the colours
unchanged (D24): the stream delivers 420v frames, which carry BT.709
(the experiment of 2026-11-15), and the screen file is tagged BT.709
for primaries, transfer and matrix. Apple's `SCRecordingOutput` is not used:
it writes a variable frame rate with its own track layout.

**Crash safety (D14, D21).** Files are written in fragments of 2 s
(*data*; independent of the keyframe interval), so a crash loses at
most the last 2 s; a video file up to 1 s more, as its fragment is
written only once its guide samples, mixed 1 s behind, arrive (D80),
and a camera file up to 0.5 s more again, its ticks waiting for late
frames (see "Cameras").

**Frame size (D11, D30, D44).** A screen file's frame size is the
screen's looks-like size (what macOS shows as "looks like", in points)
fitted into the recording resolution box: proportions kept, never
enlarged, each side rounded down to an even number. The size the
screen is drawn at (its pixels) is never recorded: a HiDPI mode that
looks like 1920×1080 on a 3840×2160 screen records at 1920×1080. The
box turns with a portrait screen (taller than wide): at 1080p a
2160×3840 screen records at 1080×1920 (D25). Examples: the built-in
screen, looks like 1728×1117, drawn at 3456×2234, records at Native
1728×1116 and at 1080p 1670×1080; a 4K screen without HiDPI records at
Native 3840×2160. While a screen's frame size stays the same, its file
continues, whatever else changed about the screen, a switch of its
HiDPI mode that keeps its looks-like size included. When the frame size
changes, the screen's current file ends and a new file starts at the
new frame size, like after a reconnect, with the event `screen frame
size changed` (the screen, the old and the new frame size) in the
manifest. At `native` the frame size is the looks-like size rounded
down to even numbers, so nearly every looks-like size change is such a
change; at `1080p` a change from 3840×2160 to 5120×2880 is not (both
give 1920×1080), while 3440×1440 to 1920×1080 is (1920×802 to
1920×1080).
The cost: a gap of under one second at the change in that screen's
video and guide tracks only; the audio files and the other screens'
files continue unbroken; a screen that flaps between modes makes many
short screen files, each valid.

**Audio (D12, D22, D31, D49).** One audio file per recorded audio
source, beside the screen files. Each recorded audio input gets its
own audio file, a `.mov` with one mono track per channel, named
`<label>, channel <n>`; the system audio gets its own audio file with
one stereo track, named `Audio 0 - System`. Every audio
file carries the timecode track with the source as its reel name and
the metadata items (see "Output on disk").

- **Sources.** Each recorded audio input has an `AVCaptureSession` of
  its own (D49), its PCM converted to 32-bit float at 48 kHz by the
  session's output; the system audio comes from a ScreenCaptureKit
  stream of its own on the main screen, with `capturesAudio`, our own
  process's audio excluded, its video at 2×2 pixels and one frame a
  second and dropped, so a failing screen stream never takes the
  audio with it. The stream reads the main screen each time it
  starts, never an older reading. When the system audio's screen goes,
  its stream starts again on the new main screen, with the events
  `system audio stopped` and `system audio started`; `system audio
  started` is told once its file has started, at the file's start, so a
  restart that fails tells only its failure (D65). Which audio inputs are recorded
  follows the audio mode (D44): `none` none, `default-microphone` the
  default one, `wired` the default one plus every built-in and wired one
  (transport type built-in, USB, FireWire, PCI, Thunderbolt, HDMI,
  DisplayPort; Bluetooth, Bluetooth LE, virtual, aggregate, AirPlay,
  Continuity Capture, an unknown transport and one that cannot be read
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
  one. A screen event never touches an audio file, but sleep ends
  every audio file and wake starts new ones, as for screen files.
- **Placement.** An audio file starts at the first tick after its first
  buffer, and the samples before that tick are trimmed, so its timecode
  is exact; from there every sample is placed by sample count, not by
  its timestamp; the samples are those of the clock drift correction
  (below), so the count follows the shared clock. A buffer whose
  timestamp is more than 32 ms (*data*; one buffer of 512 samples is
  about 10.7 ms) ahead of the position its sample count gives is a gap,
  the event `audio input gap` with its `length` in seconds: a gap up to
  1 s (*data*) is filled with silence of exactly its length; a longer
  one ends the audio file and a new one starts (D46 point 7). A buffer
  behind that position is written by its sample count and is no gap.
- **Appends.** The placed samples are gathered and handed to the audio
  file's writer about 100 ms at a time (`audioFileAppendSamples`, 4800
  samples, *data*), as the guide tracks are handed over; silence for a
  filled gap, and the file's end, hand over what was gathered first. One
  append per buffer of 512 samples cost more CPU than the AAC encoder
  (see "Build state", CPU). A crash loses up to about 0.1 s more than
  with one append per buffer, which the owner accepted (2026-11-16); the
  decoded audio is the same sample for sample (`AudioFileWriterTests`).
- **No audio (D69).** An audio input that delivers exact zeros (every
  channel exactly 0) for 10 s (*data*), such as the MacBook's
  microphone with its lid closed or a microphone muted at the device,
  has no audio: its audio file ends where the 10 s are reached, the
  event `no audio started` is told there, and its State is `no audio`;
  its capture keeps running. Its first sample that is not zero is the
  event `no audio stopped` and starts a new audio file, at the tick at
  or before that sample: the zeros of two ticks before it (*data*) are
  placed first, so the tick grid's trim cuts nothing of the sound. An
  audio file starts only with sound, so an input with no audio from
  the start gets no file, and one whose file ended for another reason
  (a gap, a change of the channel count) starts its next file with
  its next sound; zeros shorter than 10 s within a file stay in it.
  The 10 s count from the recording's start or from the last file
  end: zeros before a gap or a change of the channel count count for
  nothing after it, so an input that alternates shorter zeros with
  gaps is never no audio, and each gap is its `audio input gap` event.
  This is decided on the corrected audio, which keeps zeros exact.
  Each capture of an input detects no audio on its own: after a
  capture restart a continuing silence is reported as `no audio
  started` again, without a `no audio stopped` in between. The
  system audio is excluded: silence is normal there. No audio is no
  problem and no failure: nothing red, no problem entry, `result`
  unchanged. 2 s would have split the speech pauses of a noise-gated
  microphone into many files. **Silent after gaps (D81):** no audio
  whose zeros began within 10 s (`silenceAfterGapsTime`, *data*) after
  one of the input's own `audio input gap` events (any of them from
  10 s before the zeros began up to the no audio; the input's own: found
  by its device's UID, not by its name, which two devices can share) is
  the input broken by those gaps, as a BRIO's microphone was in the owner's recording of
  2026-11-24 06.30.02: a red problem, `The audio input <name> sends
  only silence since its gaps at 0:25` with the error `unplug and plug
  it in again`, told and counted as any broken source, its line in the
  window red until its sound returns (see "Status window").
- **Level meters (D69).** Each audio source with a running capture,
  the system audio included, has a level meter: the sample peak of
  each incoming buffer (the largest absolute sample of any channel,
  before the clock drift correction), in dBFS on the scale from −60 to
  0 dBFS (*data*). The status window draws the highest peak since its
  last drawing, never older than the peak hold, as a bar 10 times a
  second while it is open, and only then; the peak hold, the highest
  peak kept for 1.5 s (*data*) unless a higher one comes, as a mark.
  The bar and the mark are each red from −1 dBFS (*data*), otherwise
  green and the text colour. `msr record` has them in the same status
  window, not on its status line.
- **Input volume (D69).** Each audio input with a running capture has
  its input volume followed: the device's own volume, as macOS's Sound
  settings call it, through Core Audio's virtual main volume of its
  input scope (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`),
  0 to 1. Where Core Audio says it can be set, the status window shows
  a slider that sets it; where not, no slider (a grey one reads as
  forbidden). Setting it changes it for every app on the Mac, and Stop
  does not reset it. Every change, from the slider, a knob or another
  app, is read when Core Audio reports it to a listener and every
  0.25 s (*data*, for a change that is not reported), and once the
  volume held still for 0.5 s (*data*) it is the event `audio input
  volume changed` with `from` and `to`, at the time it reached the new
  volume, to the thousandth; a change that has not held still when
  the capture ends is told then. Each audio input's file records
  `inputVolume` at its start. A volume Core Audio refuses to set is
  the problem `The input volume of <input> cannot be set`, and a
  listener it refuses `Changes of the input volume of <input> cannot
  be followed`; each clears once it works. Which inputs can be set,
  whether a knob reaches the listener and whether lowering the volume
  prevents clipping are checked by the owner by hand: no agent sets an
  input's volume (D48).
  A stereo track's samples are interleaved straight into the sample
  buffer's memory.
- **Clock drift.** An audio device runs on its own clock, up to 117 ppm
  off the host clock (measured), and `AVCaptureSession`'s timestamps
  follow its sample count, so drift shows as no gap; the system audio's
  timestamps follow its sample count too (measured on the owner's Mac).
  Every audio source's sound, the system audio's too, goes through a
  clock drift correction that resamples it continuously so its sample
  count follows the shared clock; one code path, no bypass. The job is
  that an audio file stays within a frame (33 ms) of the shared clock
  over hours; under 1 ms is the engineering target. How far the sound
  falls behind is measured from when the buffers arrive: a buffer's
  lateness is its arrival minus its timestamp, and since a buffer can
  arrive late but never early, the smallest lateness is the device's
  clock against the host clock (a straight line to 0.04 ms for an audio
  input; [end-to-end-tests.md](end-to-end-tests.md), "What research
  found for the recorder"). The buffers are grouped by arrival in
  intervals of 1 s (*data*); each interval with a buffer gives a point,
  its smallest lateness at the arrival of that buffer, and the points of
  the last 20 s (*data*, the horizon) are kept. The device's clock is
  the lower support line of those points: the line on or below every
  point, no steeper than ±1000 ppm (*data*), with the smallest sum of
  distances to them, found exactly (its slope is one between two points
  or a limit). Late stretches, the system audio's catch-up bursts (one
  second's smallest lateness is a sawtooth of up to 5.6 ms) and sparse
  intervals lie above the line and do not move it; the measurement never
  depends on the correction. An estimate needs at least 5 points
  (*data*) spanning at least 10 s (*data*). The first estimate's line at
  the first point is the reference; the line at an interval's end minus
  the reference is the sound that must have been added by then. The rate
  is the line's slope plus what is still off divided by 10 s (*data*,
  the catch-up time), limited to ±1000 ppm. Without a fresh estimate
  (intervals without buffers, or too few points after a pause) it stays
  as the latest estimate set it for up to the catch-up time since that
  estimate, then becomes the kept slope: the median slope of the last up
  to 60 estimates (the clock drift shown), 0 before the first; the
  median ignores the tilted slopes of a stall while they are under half
  of the kept ones. What it does, simulated by the tests' simulation
  (its buffers arrive in order, so those held up by a stall queue behind
  it; the worst of 20 seeds, the correction against the true offset from
  30 s on): a steady device within 0.29 ms over 600 s, its clock drift
  shown within 1.1 ppm from 60 s and 0.65 ppm from 120 s; a source in
  bursts like the system audio within 0.24 ms, also twice as deep, and
  within 0.32 ms in each of the measured pattern's 4 phases; buffers of
  8192 samples within 0.7 ms, 16384 within 1.6 ms; a slow wander (±5 ms
  over 300 s) within 1.5 ms; a stall of 4 s within 0.34 ms; buffers
  delivered in 1 s of every 2 s, the other intervals empty, within
  0.08 ms at 0 ppm and 0.31 ms at -116 ppm; nothing for 4 s then all at
  once within 0.29 ms; pauses of 5 to 60 s, ending in a gap, within
  0.12 ms from the gap's end, an hour within 1.03 ms (0.65 ms with the
  mean as the kept slope; the median raised it). Its limits, measured
  the same way: the line tilts whenever late points outweigh the others
  in the horizon, which empty intervals make easier, until the late
  points leave the horizon: nothing for 8 s with the backlog drained
  over 6 s 6.8 ms off; a stall of 6 s or more can tilt it (6 s 0.85 ms
  at -116 ppm, 5.2 ms at +48.6 ppm), of 7 s up to 6.2 ms, of 9 s with
  the buffers queued behind it up to 8.3 ms, of 30 s up to 30 ms; a
  source at its lowest only once in 12 s with the rest 6 ms higher
  swings by up to 3.2 ms all the time. A gap after a tilt adds the kept
  slope's error times the gap's length, small while the tilted slopes
  are under half of the kept ones (a 600 s gap at once after a stall of
  9 s moves the correction by up to 0.26 ms, of 20 s 0.84 ms, of 30 s
  2.5 ms; a 3600 s gap after 9 s 1.6 ms); after a tilt that lasted
  longer than the median covers, the kept slope is the tilted one (a
  stall of 40 s, then a 600 s gap within 30 s: 530 ms). The reference
  comes from the first estimate's about 10 s of points and is never
  revised: a source at its lowest only once in 8 s can start up to
  3.4 ms off for good, depending on where its lowest second falls
  (within 0.57 ms in three of its eight phases; the measured 4 s pattern
  within 0.32 ms in all four). A lasting step of the delivery delay is
  followed as if the clock had stepped (up after about 20 s, down at
  once) at up to 1000 ppm, and a step down overshoots (1.1 ms on 2 ms,
  2.1 ms on 4 ms). One early buffer pulls the line down for the horizon
  and is amplified: 20 ms early up to 12.3 ms off, 6 ms early 8.9 ms,
  3 ms early 4.4 ms, and up to 42 s until back within 0.5 ms. The clock
  drift shown stays within 1 ppm through a step and within 3.1 ppm
  through a stall of up to 30 s; after a longer one it is the tilted
  slope until the tilted estimates are under half again (a stall of 40 s
  from 100 s: off by up to 884 ppm, more than 5 ppm off from 131 s to
  188 s, so about 90 s from the stall's start), so a file ending then
  carries a wrong `clockDriftPpm`. A fast wander (a period under about a
  minute, as the Logitech BRIO's) is not followed and comes out worse
  corrected than not: ±0.5 ms with a period of 12 to 40 s up to 1.5 ms
  off, a rate alternating by ±100 ppm every 12 s up to 1.84 ms (1.2 ms
  uncorrected). On the real arrivals of six sources (probes on the
  owner's Mac): BlackHole within 0.05 ms, MacBook Pro Microphone
  0.11 ms, CalDigit Thunderbolt 3 Audio 0.28 ms, Razer Seiren V3 Mini
  0.48 ms, Logitech BRIO 0.93 ms against its 5 s envelope; the system
  audio's correction ended at 0.09 ms, its rate within ±67 ppm. The
  resampler is a polyphase Kaiser-windowed sinc of 64 taps (*data*), its
  phases interpolated linearly; it adds no latency to the timestamps and
  holds back the 32 samples its filter needs ahead until the next buffer
  or the capture's end. Every source passes it, even at rate 0: it is a
  low-pass above 20 kHz (−0.07 dB at 20 kHz, −2.0 dB at 21 kHz), so an
  audio file is not sample-identical to what the device delivered. A gap
  (as under Placement) or a change of the channel count ends a segment
  of the correction: the held-back samples go out. A device's clock
  keeps drifting while no buffers come, so at a gap the interval before
  the gap is closed first, its estimate taken against the correction
  before the jump; then the correction grows by the kept slope times the
  gap's length, as a jump, not resampled. What was still off before the
  gap is still off after it (the status shows it unchanged); the rate is
  the kept slope until the next estimate, which catches that up. The
  next segment starts at its own timestamp plus the correction applied
  so far, so a gap reaches the audio file and the guide track as a jump
  of its length plus that drift. This assumes a source's timestamps keep
  following its sample count across a gap; with `--debug` each gap
  writes a line with the correction applied, the drift added for the gap
  and the lateness before and after it, which shows if they do not. The
  clock drift shown is the kept slope, the median slope of the last 60
  estimates (*data*), shown from the 10th (*data*) on, so from about
  20 s. In the recording manifest each audio file has
  `clockDriftCorrection`, the sound the correction added during the file
  (negative: removed; the drift added at a gap filled with silence is in
  it, as longer silence; the drift added at a gap that ends a file is in
  neither file), to 0.0001 s, and `clockDriftPpm`, the clock drift shown
  at the file's end, positive when the source's clock runs fast, to a
  tenth of a ppm, null if not measured by then.
- **Audio delay (D77).** Some audio inputs deliver their sound later
  than others by more than their clock says: on the owner's Mac on
  2026-11-23 a DJI Osmo Pocket's microphone was 450 ms to 590 ms later
  than a Razer Seiren's, while Core Audio's latency properties reported
  0 to 1.5 ms for every microphone. So the recorder measures it while
  recording: each audio input's corrected sound also goes, mono at 8
  kHz (each 6 samples averaged), into a ring of its latest 12 s
  (`AudioDelayFeed`); every 10 s, off the capture queues and the main
  thread, each audio input's newest file, while it is being written, is
  cross-correlated (`AudioDelay`, Accelerate's FFT) with the reference's
  over their latest common 10 s, searching ±1 s. Every
  audio delay is against the recording's **anchor**, the first input
  whose file is written, its own 0. The reference is the anchor while
  its capture runs and its newest file did not end on no audio, so every
  input is measured against the anchor, the anchor's own changing audio
  delay included; a
  file of it ending on a gap or a channel change, its next file
  following, neither changes the reference nor starts anything over,
  and while it has no file open nothing is measured that cycle. Once it
  is in no audio (muted, D69) or its capture ended (unplugged), the input with the lowest number whose file is being
  written and has an audio delay, a fallback whose own audio delay turns
  its lags into ones against the anchor; with none such, the input with
  the lowest number whose file is being written becomes the new anchor
  (see below). So a silent anchor never stalls measuring. The default
  microphone plays no part (D80, amending D77). The system audio is
  neither measured nor the reference. A window counts
  only when its match is clear, the peak of |correlation| at least 12
  times its median over the searched lags (the measured windows gave 13
  to 68 when clear, 5 to 9 when not), and not when either side is
  silent or the window starts before the file. **A file's audio delay
  (D80)** is set by its first counted window's lag (the seconds by
  which the file's sound is later than the reference's), set once more
  at 3 counted windows to their median if that lies more than one frame
  (1/30 s, `audioDelayTolerance`, *data*) away, and after that changes
  only when the median of the counted windows of the latest 60 s
  (`audioDelayChangeWindowSeconds`), at least 5 of them
  (`audioDelayChangeWindows`, *data*), lies more than a frame away from
  it: a single stray window never moves it, a lasting change (an Osmo's
  audio delay moved from 558 ms to about 470 ms within 90 minutes, Rec9)
  does once it holds. A
  new file of an input (the same device in the same recording: after a
  gap, no audio, a replug or a restart) whose earlier file had an audio
  delay starts with it, carried over, until its own first counted window
  confirms it (within a frame: nothing changes but its status) or
  replaces it; the owner wanted the audio delay kept after a gap or a
  replug. A device's newest file stays its file while its capture runs,
  also once it ended (as on no audio), until the next one starts, so a
  new file that starts before the earlier one's end is told still
  carries it over. The anchor's own files are 0, listed as such.
  A fallback reference keeps every audio delay: the lags against it are
  re-based onto the anchor through its own audio delay, which stays as
  it was while it is the reference (a shortcut: it is not measured then;
  the anchor is the reference again once its file is written), and the
  mix keeps every input. Only when no input being written has an audio
  delay does the lowest-numbered one become the new anchor, and every
  input starts over (no audio delay holds, nothing is carried over), its
  audio delay against the old anchor taken as 0 and the entries written
  before staying against the old anchor (a shortcut). An entry is the
  file's audio delay against the anchor, negative when earlier, and
  changes only when the file's own changes: a new earliest input changes
  no other file's entries. Measuring ends at Stop. Each change goes into
  `recording.json` as an entry of the file's `delays` (a file that ends
  keeps its list), rewritten with hindsight at Stop (see "Output on
  disk"), and the timeline file places each stretch of the
  file by its entry less the smallest of the files' latest audio delays
  (never above the anchor's 0), so the earliest input is at 0, a file
  never measured and the system audio unchanged. The
  status window's Clock drift column shows how much earlier the mix
  places the file (`· synced 553 ms`, `· synced 533 ms (carried)`),
  nothing at 0. The audio files are not changed; the "Audio inputs"
  guide track places each input by its audio delay (see "Guide tracks",
  D80); the detail lines say every decision (see "Logging").
- **Failures.** A failing audio capture or writer and a full disk are
  handled for an audio file as for a screen file (below): the file
  ends, the event (`audio input failed`, `system audio failed`, `audio
  file writer failed` with its `error`, `audio file writer fell behind`
  when the writer took none of the last 2 s of samples, or `disk full`)
  and a problem are told, the capture is started again with the same
  back-off, and after a full disk a new audio file starts once there is
  room. Such an end makes the recording's `result` `problems` (D47); an
  unplug and a gap do not. As for a screen, a source lost a second
  time while it is still listed and recorded, with no change of the
  audio devices (an audio input) or of the screens (the system audio)
  in between, is a failure: `audio input failed` or `system audio
  failed` with that as its `error`, a problem and the back-off. When an
  audio file ends, the samples still waiting for its writer are
  written for at most 2 s; its `end` counts only what the writer took,
  and samples left over are lost: `audio file writer fell behind` with
  its `error`, a failure, and a problem.
- **Guide tracks.** For playback and waveform sync, every video file
  (screen file and camera file, D74) also carries guide tracks (audio
  only writes no video file, so no guide track, D62): "Audio inputs", one mono mix of the
  recorded audio inputs, unless the audio mode is `none`; "System
  audio", stereo, unless system audio is off. The two are never mixed
  together. For "Audio inputs" each audio input is averaged to mono, the
  inputs are summed at unity gain, so a silent input never lowers a
  live one, and a soft limiter keeps the sum within ±0.501, −6 dBFS
  (`limiterCeiling`): unchanged up to 0.251, −12 dBFS (`limiterKnee`),
  above it `0.251 + 0.250 · tanh((|x| − 0.251) / 0.250)` with its sign
  (D52, D75; the ceiling was 1.0 until an audit of a recording on the
  owner's Mac, 2026-11-23, found AAC decoding a loud thump limited to
  1.0 to 1.14 to 1.19). The AAC encoder (64 kbit/s, a cutoff near
  16.5 kHz) overshoots the limiter by up to 1.6×, depending on the
  material; in a simulation on that recording the mix decoded to at
  most about 0.78, roughly 2 dB below full scale, but the decoded peak
  is not bounded. A true-peak limiter (a low-pass and lookahead) is
  deferred. "System audio" is clamped to ±1. **Where "Audio inputs"
  places each input (D80):** the mix runs 1 s (`guideTrackDelay`,
  *data*) behind real time, so every source's buffers have arrived, also
  those of an input placed up to 0.8 s earlier; the video file's frames
  are still written live, its guide samples carry their own time. The
  anchor is in the mix from the start; any other input joins only
  once its file has an audio delay (see "Audio delay"; before that it
  is received but not mixed, `· not synced yet`, or `· no clear
  sound`), and a
  file carrying its earlier file's audio delay over joins, or stays
  out, at once. Each input is placed earlier by its audio delay less
  the smallest latest audio delay of the inputs staying in the mix, the
  mix's zero, so the earliest input in the mix is not moved and none
  moves more than 0.8 s; an input whose file ended (no audio) keeps its
  audio delay and its place in or out of the mix until its capture ends,
  so a noise-gated earliest microphone falling silent moves no other. An input that moves
  crossfades from the next sample to mix: over 20 ms
  (`guideTrackCrossfade`, *data*) where it was placed fades out
  linearly while where it is placed now fades in, then only the latter
  plays; a move repeats or skips its size of sound in the guide once.
  The mix keeps each source's samples from the next position to mix on,
  so an input moved later finds them still there. **Which audio inputs
  "Audio inputs" mixes (D79, D80):** of the audio inputs whose capture
  runs that have an audio delay (by their newest files; an input whose
  capture ended is forgotten), the largest group whose audio delays lie within
  0.8 s (`guideTrackSyncLimit`, *data*, early or late; compared with a
  tolerance of a quarter of a sample at 8 kHz, below the half-sample
  step of a median) of each other stays; on a tie the group holding
  the files that stayed before, so a newcomer never evicts them, else
  the group with the earliest input; a file outside it leaves the mix
  of every video file alike, the anchor's included, so an Osmo as the
  anchor more than 0.8 s late against two microphones in sync with each
  other leaves. A file that left rejoins when its audio delay lies
  within the limit of the staying group, or, out of it, when it no
  longer has one (a new anchor), then not in the guide
  track yet; the audio delay's own rules keep it from moving back and
  forth. An input that is out stays out with its next files while its
  capture runs, no new leave told; a new capture's file carrying its
  audio delay over is out at once, told again. A leave is told only once the capture took
  the file out:
  the event `audio input left the guide track` with its `offset` (from
  the staying group's earliest input), and a problem whose line reads,
  while out, `Audio <n> <name> 953 ms late, not in the guide track; its
  own audio track is recorded` (or `900 ms early` for an early input),
  and once it rejoins or its capture ends, `Audio <n>
  <name> was not in the guide track from 0:50 to 1:40 (953 ms late);
  its own audio track is recorded` (or `(900 ms early)`); always
  orange, and by design neither a Dock bounce nor the badge nor the
  status line's count. A leaving source is cut, its samples not mixed
  yet dropped. Its own audio file is unchanged and the timeline file
  still places it by its audio delays. Each source is placed by its own
  timestamps, placed earlier as above, and a source that is missing is
  silence in its guide track. The mix is handed to every open screen
  file every 100 ms (*data*); a video file's guide tracks cover
  exactly its own time, so a frame size change gives them the same gap
  as the video. A video file listens to the mix until its last mix:
  stopping hands it every mix handed over before, and its last mix
  takes, from the samples the sources delivered and not mixed yet, the
  rest up to the end of its video, without taking them from the other
  video files. Before it takes its last mix, a video file waits
  until every source mixed in each guide track has delivered its
  samples up to the end of its video (and an input placed earlier that
  much beyond it), for at most 2 s (`audioWaitBoundSeconds`,
  *data*); if the wait runs out, it mixes what is there, and a source's
  samples that have not come are silence in it. At Stop the audio
  sources stop only after every video file's last mix. Its last mix
  is joined into one buffer per guide track,
  cut at the end of the video, and waits for the writer as long as its
  ticks do, so its guide tracks end with the video (D51). Should the
  samples not mixed yet start after what the file received, it writes
  up to there, never silence in their place; that, or a writer that
  does not take the last mix in time, is told as a problem at the
  file's end. A file ended by a failure (its writer failed or fell
  behind) gets no last mix, so its guide tracks may end early.

**A failed file's end (D66).** A file whose writer failed is not
finalized, and its entry in the recording manifest ends where the file
really ends, not where the writer was last given a frame: after the
file is closed the recorder reads its duration (`AVURLAsset`, loaded
asynchronously), and the end is the file's start plus that duration. A
problem on the file, `Screen file <name>` or `Audio file <name>`, says
`the file ends at <t> s, the writer failed at <t> s: <n> s of the
recording are lost`, with the times in seconds from the recording's
start; no such problem when nothing is lost. A file that cannot be read
at all ends at its start, and the problem says so with the read error.
The failure's event and its problem stay at the failure's time, the end
the writer was given. A file that is finalized, or ended without a
writer failure (such as samples lost at the end of an audio file), keeps
the end it had.

**Screen identity.** A screen is known by the UUID macOS gives it
(`CGDisplayCreateUUIDFromDisplayID`), never by its display ID, which
changes when a screen comes back, nor by its name, which macOS may
change ("MSR Test (1)"). A screen that comes back with the same UUID
keeps its number and its name in the file names for the whole
recording. Whether a real screen keeps its UUID after it was
unplugged is UNVERIFIED (the owner's check on the first build). In a
file name, `/` and `:` in a screen's name become `-`, so a name never
stops a screen from recording. A screen reached through another port
(a monitor with two USB-C inputs) may be another screen, with its own
UUID and number: macOS treats it so, and so does the recorder (D46).

**Screens coming and going (D14).** A screen that appears gets a
stream and a screen file (event `screen connected`); one that
vanishes has its file finalized (event `screen disconnected`). A
screen that is asleep counts as disconnected; that macOS's screen
change callback fires when a screen falls asleep is [ASSUMED]. When
a screen is unplugged, its stream ends first, with ScreenCaptureKit's
`noCaptureSource` (-3815), and macOS's screen-change notice may come
seconds later (8 s for the Wacom One, observed in the owner's run of
2026-11-15, `--debug` log). That stream end is no failure: the screen
file ends as on a disconnect, with no `screen stream failed` event and
no back-off; the event `screen disconnected` comes with the notice. A
screen still listed one settle time after such a stream end gets a new
stream, as after any change, without a failure event. Only the first
such end is free: if the stream ends with `noCaptureSource` again with
no screen-change notice for that screen in between, it is a failure
(`screen stream failed` with its error, back-off, and a problem told),
so a screen that stays listed but cannot be captured never goes
unrecorded silently. Any other stream error is a failure: a stream that fails finalizes its file and is restarted after 1 s,
backing off to 10 s (*data*), for as long as the screen exists. Each
gap is an event in the manifest. A screen's stream starts, or starts
again, only once the screen has been unchanged for the settle time,
1 s (*data*): a mode change that macOS reports as a disconnect and a
reconnect, or modes switched through quickly, so make no burst of
short screen files. When a mode change gives a new frame size, the
current screen file runs on through the settle time, with the picture
scaled to the old frame size (never observed: the code reads no
buffer's size or format, and the `capture` detail lines of "Logging"
show what the frames are), and then ends; the stream is stopped and
a new one started at the new frame size, the same path as a reconnect
(`updateConfiguration` is not used: never tried). The gap is the
restart only. Target, checked by the end-to-end tests: a screen's file
starts within 1 s (*data*) after its settle time ends, the new
stream's first frame included (D63).
- **Mirroring:** a screen that starts mirroring another
  (`CGDisplayMirrorsDisplay`) ends its screen file with the event
  `screen mirroring started` (the screen and the one it mirrors);
  when mirroring stops, a new screen file starts with `screen
  mirroring stopped`. The screen keeps its number.
- **Main screen:** a change of the main screen is the event `main
  screen changed`; the numbers stay.
- **Sleep and wake:** at sleep every file ends (event `sleep`); at wake
  (event `wake`) new files start, the screens after the settle time.
  The audio's wake runs whether or not the screens can be read: a wake
  whose screens cannot be read tells "The screens cannot be read",
  still writes the `wake` event and restarts the audio inputs, and the
  screens start after the settle time from the next reading of the
  screens that works.

**Screen check (D45).** Every frame is checked before it is kept: the
rectangle ScreenCaptureKit attaches to it (`SCStreamFrameInfo.screenRect`)
must be its screen's bounds (`CGDisplayBounds`, held in memory and
read again when the screens change). It reads no pixels. A frame that
fails is never written, and its tick repeats the last frame that
passed. Why: after a screen reconnects, ScreenCaptureKit can deliver
another screen's picture on its stream, and a restart does not clear
it (the experiments of 2026-11-13 and 2026-11-15 with virtual screens,
[end-to-end-tests.md](end-to-end-tests.md), "What research found for
the recorder"); a frame then carries the other screen's rectangle.
After 30 failing frames in a row (*data*), not counting those within
the settle time after a screen change, the screen file ends with the
event `screen shows another screen's picture`, the Dock badge shows
"!", `msr record` names the screen on standard error, and the screen
is tried again only after its next change. Its limit: a frame whose
rectangle is right can still be black (seen once, cause unknown); the
check cannot see that. That `screenRect` and `CGDisplayBounds` are
comparable as they are, in points and the same coordinates, is
[ASSUMED]; the builder checks it with real frames.

**Cameras (D74).** Each camera the camera mode records gets a camera
file made exactly as a screen file: the same writer, the same 30 fps
tick grid on the shared clock (the newest frame at each tick, repeated
when the camera delivers none), HEVC, timecode, the same guide tracks,
no audio of the camera's own.

- **Which cameras.** The cameras are AVFoundation's video devices
  (built-in, Continuity Camera, Desk View, external). The default camera
  is `AVCaptureDevice.default(for: .video)`. An iPhone camera is a
  Continuity Camera or Desk View, or a camera connected by Continuity
  Capture. A camera is virtual unless AVFoundation lists it as built in,
  as a Continuity Camera or Desk View, or connected by built-in, USB,
  FireWire, PCI, Thunderbolt or Continuity Capture (the transport types
  as Core Audio names them), such as OBS Virtual Camera; an unknown
  transport is virtual. Every other camera is real. None records no
  camera, Default camera the default camera if it is real, All real
  every real camera, All every camera, virtual and iPhone cameras too
  (the owner, 2026-11-22). A suspended camera
  (`isSuspended`, such as a laptop's with its lid closed) is not
  recorded, and its file ends when it is suspended and starts again
  after the settle time when it is resumed; the recorder and the app
  observe the suspension and read the cameras again when it changes.
- **Format.** A camera's box is the recording resolution's box limited
  to 1920×1080 (*data*, `RecorderValues.cameraLargestSize`) while the
  setting `limitCameras` is on, the default; off, the recording
  resolution's box alone (the owner, 2026-11-23: "for the webcam
  resolution clamp I'd like a toggle"). With the limit, at
  Native, 4K and 1440p a camera records at most 1920×1080, or 1080×1920
  upright, and at 720p 1280×720 (the owner, 2026-11-23: "quality and
  reliability trumps all"). The reason for the default: at Native a BRIO (USB 3) opened
  4096×2160 and a DJI Osmo Pocket (USB 2, on the same dock controller as
  a USB microphone and the keyboard) 3840×2160; the system log showed
  about 1100 USB errors, the BRIO stalled and the microphone's file was
  padded with zeros. At 1080p the same two cameras (1920×1080 and
  1080×1920) gave no USB error, no stall and no late frame. The limit is
  set before the start, never adapted while recording. Per frame size
  the variant with the lowest highest frame rate that still reaches 30
  fps (a rate rounded to whole frames), or the fastest where none does.
  As for screens (the owner, 2026-11-22): each format reaching 30 fps,
  of any aspect ratio (16:9, 9:16, 3:2, square), records its size
  fitted into the camera's box as a screen's looks-like size is (never
  enlarged, a portrait format against the box turned upright); the
  format with the largest recorded size is chosen, and of formats with
  that same recorded size the smallest, the least to decode. Of formats
  that record as much and are as large (such as 1920×1080 and
  1080×1920), the one turned as the camera's active format (portrait,
  landscape or square) is opened, as the camera's own orientation tells
  which picture it means: the Osmo in its 9:16 mode runs in 1080×1920
  and also lists a 1920×1080 with that picture pillarboxed in it, while
  the FaceTime HD Camera, offering 1920×1080, 1080×1920 and 1552×1552,
  runs in 1920×1080. Without an active format, or still tied, landscape
  goes first, then the narrower, whatever the camera lists first. So at 720p a camera with 640×480 and 1920×1080 records
  1920×1080 scaled to 1280×720, and a BRIO with 4096×2160, 3840×2160
  and 1920×1080 records 1920×1080 as it is at 1080p and at Native. A
  camera with no format reaching 30 fps records its fastest, the
  largest of those. The camera's frame duration is set to 1/30 s where
  the format's ranges allow it, otherwise to the allowed rate closest
  to 30, told in a detail line. Where the camera lists several formats
  of that size and rate, differing in the pixel format macOS delivers
  them in (such as `420v`, `yuvs`, `2vuy` or MJPEG), the first that is
  not MJPEG is opened, else the first, with a detail line naming them:
  a deterministic pick among what macOS delivers, not a choice of what
  crosses the cable, which is the driver's and not visible (the Osmo
  cannot send 1080×1920 `2vuy` at 30 fps over USB 2; its driver decodes
  MJPEG). AVFoundation scales the frames to the camera file's frame
  size. A frame without a decoded picture ends the capture as a failing
  stream.
- **Orientation (D76).** A camera that offers its format's size in both
  orientations (W×H and H×W, both at 30 fps), such as a DJI Osmo Pocket
  (1920×1080 and 1080×1920), delivers in the orientation it is not set to its
  picture between pure black bars, and opens in the orientation a host last
  set, not in its own mode (the owner's Mac, 2026-11-23: a portrait
  picture pillarboxed in 1920×1080, and after a switch to landscape
  while unplugged a landscape picture letterboxed in 1080×1920). So the
  recorder checks such a camera's picture (`CameraOrientation`): the
  luma of a frame sampled on a grid of 192 samples along its long side
  (`sampledLuma`, the middle pixel of each cell), the picture being what
  lies between whole columns or rows within 4 of black (16 in video
  range); the picture is boxed in the other orientation when it has bars on
  both sides across the long side, equal within a sample, none across
  the short side (a dark first or last row of the picture allowed), and its
  aspect ratio is within 5% of the frame turned. A dark room has no
  pure black bars and a picture of another aspect ratio does not match.
  At the capture's start its frames go to no file until the orientation is
  told: 3 frames in a row boxed with the same picture turn the camera at
  once, before any file of it (no event); 3 frames in a row not boxed,
  or 1 s from the first frame, start the file (a frame black all over
  tells nothing). While recording, a frame is checked every 5 s, and
  every 0.5 s while a boxed picture is confirmed; boxed with the same
  picture for 2 s, the camera turns as a frame size change does: after
  the settle time its file ends and a new one starts in the other
  orientation, with the event `camera orientation changed` (from and to). The
  orientation stays turned, also when the camera's active format says
  the other, until its picture shows it boxed again. A takeover by
  another app while a turn waits cancels the turn: the new file is the
  takeover's, with its event. A camera another app uses
  or took over keeps that app's format and is never turned (see "Another app").
- **Another app.** A camera another app uses when the recorder reads
  the cameras before its start is opened without changing its format or
  frame duration: it records the format the camera runs in, fitted into
  the camera's box like any format (the owner, 2026-11-23: "accept
  another app taking control"). "Another app uses it" is Core Media
  I/O's `kCMIODevicePropertyDeviceIsRunningSomewhere`, read for the
  device whose `kCMIODevicePropertyDeviceUID` is the camera's unique ID
  (`CameraInfo.isRunningElsewhere`), taken only from a reading while no
  capture of the recorder's own is the camera's, from that capture's
  start until its capture-ended report, which comes once its file is
  finalized, after its `stopRunning` returned (a reading counts the
  recorder's own session too; [ASSUMED] Core Media I/O is current by
  then); then the cameras are read again, as a reading while its
  capture still counted was not taken: for a capture the recorder
  stopped, after its file ended; for one that ended by itself, in its
  stream's end, not AVFoundation's
  `isInUseByAnotherApplication`, which stays false for a camera a
  browser uses (D74). Otherwise the recorder sets its own format, as
  above. Once the recorder's own opening of a camera has finished
  setting it up, any change of its active format the recorder did not
  make is another app taking it over (`ForeignFormatWatch`); the
  recorder's own format and frame duration settings never count. When
  such a change gives another recorded frame size, the camera file ends
  and a new one starts at the new size in the format the camera then
  runs in, with the event `camera frame size changed` (from and to),
  after the settle time as a screen's frame size change makes a new
  screen file (D30), so an app changing it several times in a row gives
  one new file; the format is never set back. The recorder reads the
  cameras again when a camera's active format or AVFoundation's
  `isInUseByAnotherApplication` changes.
- **Placement.** A camera's frames arrive late more often than a
  screen's: USB cameras deliver them in bursts, seen 0.1 s to 1.5 s
  after their capture when the USB bus was overloaded (a BRIO and a DJI
  Osmo Pocket on the owner's Mac, 2026-11-22). So a camera file's tick
  is decided once a frame captured after the tick's time has arrived, or
  0.5 s (*data*, `RecorderValues.cameraDecisionDelay`) after the tick's
  time, whichever is first, and shows the newest frame captured at or
  before the tick's time; a screen file's tick is decided at its time.
  A frame arriving after its tick was decided goes to the next tick
  decided, as a screen's would, and is placed late (counted only when a
  tick shows it, not when a newer frame supersedes it first): at the
  file's end a detail line gives the count and the longest such frame
  took from its capture to its arrival. A frame placed late is not a
  frame repeated for lateness (`framesRepeatedForLateness`, a tick the
  writer took late). At the file's end every tick due is decided.
- **No frames.** A camera delivers frames whether its picture changes
  or not. No frame for 2 s while recording is a stall (event `camera
  stalled`): the camera file goes on, repeating its last frame, the
  status window shows the camera as `stalled`, and the problem is told
  once per stall; when frames come again, the event `camera stall
  ended` gives its length. The capture goes on through a stall, as the
  stream recovers by itself, as a BRIO's 2.95 s USB stall did on the
  owner's Mac (2026-11-22), where ending and restarting the capture
  only split the file and left a 1.17 s hole; as it loses picture, a
  stall makes the result `problems` (D47). The capture ends as `camera stream
  failed`, and starts again after the restart delay, only on a runtime
  error of AVFoundation's capture session
  (`AVCaptureSession.runtimeErrorNotification`), when no first frame
  came within 5 s of the capture's start (10 s for an iPhone camera,
  whose stream takes longer to start), or after no frame for 10 s (all
  *data*, `CameraFrameWatch`); a disconnect ends it as `camera
  disconnected`.
- **Coming and going.** As screens: a camera that appears (event
  `camera connected`) starts its file after the settle time; one that
  vanishes ends it (`camera disconnected`); a failing stream or writer
  ends the file with its event and the capture starts again after the
  restart delay; disk full, sleep and wake as for screens (the camera
  list never fails to be read, so a wake always restarts the cameras). Under Default
  camera a change of the default camera is the event `default camera
  changed`. A camera keeps its number by its unique ID. There is no
  mirroring, main camera or screen check for cameras.
- **Permission.** The recorder reads the cameras only with the Camera
  permission. Never asked, it asks once, when the camera mode records a
  connected camera (at the start or when one appears), and records the
  cameras once granted; denied, no camera is recorded (macOS grants the
  permission per app, so it is all cameras or none), the problem "The
  Camera permission is missing" is told once, the status window shows
  each camera the camera mode would record as a row with the state `no
  Camera permission`, and the screens and the audio are recorded as
  usual (the owner, 2026-11-22: "if a single camera can be denied and
  others work, then yes record and show in status").

**Disk (D14).** Below the warning threshold: the warning. A writer that
fails on a full disk ends its file, readable up to the last fragment;
the recorder checks free space every 5 s and starts new screen files,
camera files and audio files once there is room. The low disk warning
threshold counts every screen's newest screen file, every camera's
newest camera file (D74) and every audio source's newest audio file. Nothing written is ever deleted.

**Keep awake (D14).** A power assertion against idle system and
screen sleep while recording.

## Logging

The app and `msr` write every event of the
recording manifest and every problem to the macOS unified log, subsystem
`org.schapiro.multiscreenrecorder`, at `.notice` (problems at `.error`),
levels macOS keeps on disk, with names (screens, folders) public, not
redacted. `msr record` also prints each event as one line on standard
error: the local time, the offset from the recording's start, the event
and its screen, and the details it has, such as `22:14:40 +9.2s screen
connected: Wacom One 13T` or `22:15:32 +61.3s screen stream failed: LG
(-3811)`. A failure is printed once (D65): a problem whose failure an
event tells (a screen's or an audio source's failure, and a screen file
or an audio file ended by a failure event or by its capture's failure)
is printed as that event's line with its error, not again as the problem; a problem that
is no event is printed as before. A repeat, the same failure event of
the same subject with the same chain of error domains and codes (the
error's text does not count, as it holds the changing file name), is
counted and not printed; the subject's next event that is no repeat (it
recovered, or failed differently), or Stop, first prints the count in
the event line's format, such as `15:36:31 +150.7s audio file writer
failed repeated 5 times since 15:35:31: Razer Seiren V3 Mini`; with no
repeat nothing more. The unified log, `recording.log` and
`recording.json` keep every event, and the status line and the summary
count as before. Detail lines are the tracker's actions, the screens as read,
files started and ended, the ready check's facts, and every 10 s (*data*), together as one block
in number order (the system audio, 0, first), the clock drift correction
of each audio source being recorded, such as `Audio 3 - Razer Seiren V3 Mini: clock
drift -116.1 ppm, corrected +34.94 ms so far, 0.04 ms off`, or `clock
drift not measured yet`; zero is `0`, never `+0.0`, and at each gap in
an audio source a line such as `Audio 3 - Razer Seiren V3 Mini: gap of
100.0 ms, clock drift corrected +3.45 ms so far, lateness 12.30 ms
before, 12.41 ms after`. `--debug` (for `msr record` and `msr check`)
also prints the detail lines on standard error, each as `detail
<category>: …`, and writes them at `.debug` in the unified log; while a
recording runs, each line on standard error carries the time since its
start as the event lines do, such as `detail recorder: +27.9s start
Screen 3 - LG`.

**Audio delay detail (D80, D81).** The detail lines of category
`recorder` let every sync decision be rebuilt from `recording.log`
alone, one line per decision, never per buffer, each with the log's own
`+<s>` time; files by name, audio delays as `AudioDelay.text` writes
them:

- Each measurement, every 10 s, per file: `<file>: lag 552 ms late
  against <reference file>, clarity 31, counted` (or `not counted`), or
  why it was not measured: `<file>: not measured, it or the reference
  <file> is silent`, `… has less than a window of sound`, `… the
  reference <file> has no file open` (the anchor between two files).
- Each audio delay rule that was evaluated, with its outcome:
  `<file>: audio delay set by its first counted window: 552 ms late`;
  `<file>: audio delay the median of its first 3 counted windows:
  552 ms late → 540 ms late`; `<file>: audio delay the median of its 6
  counted windows of the latest 60 s: 555 ms late → 600 ms late`;
  `… kept at 500 ms late, 10.0 ms off, within a frame` when a rule
  declined; on a carried-over audio delay `<file>: audio delay its first
  counted window on the carried-over: kept at 500 ms late, 10.0 ms off,
  within a frame, confirmed` (or `…, replaced`); a counted window no rule
  takes, `<file>: audio delay no rule: 2 of 3 counted windows for the
  median` or `… no rule: 4 of 5 counted windows in the latest 60 s`.
- A lag dropped: `<file>: lag 100 ms late dropped, the anchor's, always
  0` (or `the reference's own`, `not a device's newest file`), and
  `counted lags of <files> dropped: measured against <file>, the
  reference is now <file>` when the reference changed during a
  measurement.
- No clear sound: `<file>: no clear sound to sync, 3 measurements with
  sound and no counted window`, once, while the file has no audio delay.
- At Stop, each file whose list hindsight changes: `<file>: audio delays
  with hindsight [0.0 s: 533 ms late, 41.2 s: 472 ms late] → [0.0 s:
  472 ms late]`.
- A carry-over: `<file>: carries over 500 ms late from <earlier file>`
  and `<file>: in the guide track with the carried-over audio delay` (or
  `out of the guide track`).
- A reference change: `reference <old file> → <new file>: lags re-based
  onto the anchor by 500 ms late`, or `…: it has no audio delay, so it
  is the new anchor and every input starts over`.
- The mix: `<file>: joins the guide track placed earlier by 500 ms (the
  mix's zero: <file>)`, `<file>: placed earlier by 555 ms → 600 ms (the
  mix's zero: <file>)` followed by `the Audio inputs guide track
  crossfades from its sample 1440000`, `<file>: leaves the guide track,
  953 ms late from the staying group's earliest`, `<file>: rejoins the
  guide track`; a new file of a device placed before is no new join. A
  leave, rejoin or placement its capture did not take: `<file>: its
  capture did not take the placement, the file no longer its current
  one`, or `<file>: its capture did not take the leave, the file no
  longer its current one`, or `<file>: its capture did not take the
  rejoin, the file no longer its current one or not out`; none is
  retried.
- No audio (D81): `Audio 2 Razer Seiren: no audio since 0:25, right
  after its gap at 0:24: a red problem (D81)`, or `Audio 2 Razer Seiren:
  no audio since 0:25, no gap within 10 s before: no problem (D81)`.

**Capture detail (D66).** The detail lines of category `capture` say
what a screen capture and its writer saw, to root-cause a writer that
fails on some Macs only (the hosted runner, about 2 of 7 runs, with
`AVFoundationErrorDomain -11800` from `OSStatus -19092`):

- Per screen capture, for every complete frame before its screen check
  acts, the frame's facts: width × height of the pixel buffer, pixel
  format as its four-character code, colour primaries, transfer
  function and YCbCr matrix attachments, whether an ICC profile is
  attached, ScreenCaptureKit's content rect and scale factor, and the
  screen check's verdict. One line, `Screen 2 LG: first frame <facts>`,
  at the first frame; after that one line `Screen 2 LG: frame changed:
  <value was → now, …>` whenever any of them changes; never per frame.
- Per screen file, at its start: the video output settings
  (`video settings of <file>: {…}`) and the video encoders VideoToolbox
  lists for HEVC with their hardware-accelerated flag.
- Per screen file, when its video input's `isReadyForMoreMediaData`
  changes (the first time only when not ready): `video input of <file>
  ready for more media data: false`, and back.
- Once, when a screen file's writer fails: `writer of <file> failed:
  status <writer status>, error <error detail>; <per input: video, each
  guide track, timecode: samples appended and the presentation time of
  the last>; <the first input whose append returned false, or that none
  did>; last buffer <w>×<h>, IOSurface ID <id>, a repeat of the one
  before: yes or no` (the ticker appends the last passed frame again
  when the screen shows no new one).

- Per camera capture (D74): `camera <unique ID>: startRunning took <ms>
  ms` and at its end `camera <unique ID>: stopRunning took <ms> ms`, so
  a freeze can be traced (both block the session's own queue); at the
  session's start `camera <unique ID>:
  active format <w>×<h> <subtype>, frame duration <min> to <max>` (such
  as `1/30 s to 1/30 s`), with `the format allows no 30 fps, set to <n>
  fps` when it cannot run at 30 (left out when its format was kept), and
  before it `camera <unique ID>: in use by another app at the start, its
  format kept` when another app used the camera as the cameras were
  read;
  `camera <unique ID>: active format changed to <w>×<h> <subtype>, frame
  duration <min> to <max>` when the open camera's active format changes,
  with `, by another app` when the recorder did not make the change;
  `camera <unique ID>: <n> frames dropped: <reason> <count>, …` for the
  frames AVFoundation dropped (`captureOutput(_:didDrop:from:)`, its
  reason such as `FrameWasLate`, `OutOfBuffers` or `Discontinuity`), at
  most one line a second with the counts since the line before, and the
  rest at the capture's end; at the first frame `Camera 1 FaceTime
  HD Camera: first frame <w>×<h> <pixel format>`; at a camera file's
  end, when frames arrived after their tick was decided, `<file>: <n>
  frames arrived after their tick was decided and were placed late, the
  latest <ms> ms after its capture` (see "Cameras"). In category
  `recorder`, at every reading of the cameras, `cameras, read in <ms>
  ms: <name> [virtual] [Continuity Camera] [suspended] <format>, …`, how
  long listing them took (AVFoundation's list and the Core Media I/O
  read, on the main thread) and the format the camera is opened with at
  the recording resolution (none at None), and when
  AVFoundation's `isInUseByAnotherApplication` of a camera changes,
  `camera <name> (<unique ID>): now in use by another app` or `no longer
  in use by another app`.

A screen's frame is never converted: its size and format go to the
writer as they come, so a frame of a size other than the file's gets no
check before the writer; the lines above are what tells whether that
happens. A camera's frames are decoded and scaled by AVFoundation to
the camera file's frame size, in the screens' pixel format (`420v`).

**Recording log (D64).** Every recording, in the app and in `msr
record`, with or without `--debug`, writes `recording.log` in its
recording folder, next to the recording manifest: plain text, one line
each, every event, every problem with its full error text (the error
detail as one line, see "Output on disk"), and every detail line, and
`finalizing the recording manifest` at its end. It starts, before the
first event, with detail lines of the starting situation, in this
order: `started: <app and version>, recording folder <name>`; `macOS
<version and build>, Mac model <identifier>` (`hw.model`, such as
`Mac15,8`); the effective settings line by line as `msr settings`
prints them (category `settings`: the output folder, the low disk
warning minutes and the rest); "What will be recorded" line by line as
`msr record` prints it (category `what will be recorded`, its empty
lines left out); and the ready check's facts and its result, line by
line (category `ready check`), of the ready check before Start. The
block is written and synchronized to disk before the recording starts,
so a crash in its first seconds leaves it. It goes to the recording log
only, also with `--debug`: `msr record` printed the table and the ready
check already. Nothing in it names the person beyond what the files
already carry: no user name, serial number or host name. Each line starts with the local time
and the offset from the recording's start: an event's line is its line
on standard error, a problem's `22:15:32 +61.3s problem: <the problem
as the status window lists it>`, a detail line `22:14:58 +27.9s detail
recorder: start Screen 3 - LG`. The file is created new and only
appended to, never rewritten: after an event's or a problem's line it
is synchronized to disk (`fsync`), so a crash leaves everything up to
the last event or problem; detail lines wait in memory until then, until
Stop, or until the check once a second finds 10 s (*data*) since the
last write, so about 11 s at most. A capture thread adding a detail line
never waits for a write or its `fsync`. A recording log that cannot be
created or written is a problem, told once until writing it works again
(the lines meanwhile are lost); the recording goes on. At Stop the
recording log is written, synchronized and closed before the recording
manifest is finalized: if that fails, it is a problem in the final
manifest and the `result` is `problems` (exit 3 for `msr record`). A
problem reported after the manifest is finalized (the final manifest
that cannot be written, or a late report of the recording log) goes to
the unified log and, in the app and in `msr record` (also with
`--quiet`), to standard error as `Problem at the end: <the problem as
the status window lists it>`, such as `Problem at the end: Cannot write
the recording manifest: …`; it is printed when the problem is reported,
before the summary of `msr record`. Its cost: a
1-minute recording of 2 screens and 5 audio sources wrote 56 lines,
6.8 kB [KNOWN, measured 2026-11-19], most of it the clock drift block
(one line per audio source every 10 s), so about 0.4 MB per hour, and
one `fsync` per event and problem and at most one per 10 s otherwise.

The log of the last 2 hours, of the app and `msr`
only (the tests log under the same subsystem on a developer's Mac):

```sh
log show --last 2h --predicate 'subsystem == "org.schapiro.multiscreenrecorder" and process == "msr"'
```

The crash report form has an optional field for its output, and the
README names the command for a crash outside a recording. The crash
report dialog, the status window (with a problem), the problem report
offer, the end of `msr record`'s summary when it exits 3, and the
README name the recording's `recording.json` and `recording.log` for a
report.

## Code layout

```
Package.swift             Swift 6 language mode, macOS 26, arm64
Sources/RecorderLogic/    pure logic, Foundation and Accelerate only, fully unit-tested
Sources/RecorderCore/     ScreenCaptureKit, AVFoundation, Core Audio, Core Media I/O and IOKit adapters
Sources/msr/              entry point: the command line and the app
Sources/EndToEndLogic/    the end-to-end tests' logic: scenarios and assertions (never in the app)
Sources/VirtualScreen/    Objective-C: the private CGVirtualDisplay, looked up when it runs (test equipment)
Sources/msr-end-to-end/   the end-to-end tests' driver and device helper (end-to-end-tests.md)
Tests/RecorderLogicTests/ Swift Testing, as all tests
Tests/RecorderCoreTests/  the adapters that need no device or permission
Tests/AppTests/           the start window's model, with stand-in probes
Tests/CommandTests/       msr and the scripts in scripts/, run as commands
Tests/EndToEndLogicTests/ the end-to-end tests' logic
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
ticks), geometry for every recording resolution (and their slider order)
and change case, Native as the looks-like size, auto mode's effective
choices, the audio modes and which input each records (every transport
type), settings read leniently with the line for standard error, flags
(`--auto` against `--resolution` and `--audio-mode`) and their errors,
the text `msr check` prints for "What will be recorded", file naming,
manifest states, the screen tracker (numbers, the settle time, frame
size changes, mirroring, the main screen, back-off, the screen check's
fault, a full disk, sleep and wake, and no screen at the recording
resolution None, a wake without a reading that starts the screens at
the next one), the ready check at the recording resolution None
(the screen permission only with the system audio, no screens item,
nothing to record refused), the screen check, the shared clock,
the timecode (also on a daylight saving day and at a second frame rate),
`--duration`, the summary of `msr record`, the Dock badge and the
problems of a recording, the audio tracker (the audio modes, inputs
coming and going, an unplug told once, a replug, the default microphone
followed, failures with the back-off, the system audio moving to the new
main screen, a full disk, a channel count change, two inputs with the
same name, sleep and wake), the camera mode and which camera each
records (a suspended one not, an iPhone camera only under All), a
camera's chosen format (any aspect ratio, inside the recording
resolution's box, the slowest variant at 30 fps)
and frame rate, the limits for a camera without frames,
the camera tracker (numbers, the default camera first, a camera
coming and going, failures with the back-off, a full disk, sleep and
wake), camera files in the manifest, the timeline and the status
window (D74), the audio file's placement on the tick grid
(trimming, gaps filled or ending the file, jitter within 32 ms), the
clock drift correction (the tracker against simulated devices, seeds 1
to 3: steady, also for 30 minutes, sources in bursts like the system
audio, buffers delivered every other second, stalls of 4 s and 9 s, a
stall before a gap, pauses up to an hour, buffers of 8192 and
16384 samples, lasting steps up and down, an early buffer, a slow
wander, and fast wanders as a bound on how much worse they get; the
support line with hand-made points and the rate; the resampler's purity,
its sample count, chunking and a rate change; clicks, gaps with the
drift during them, and the rate and what is still off right after a gap,
through the whole correction; when the status and the detail line are
due), the level meter (the peak of any channel since the last reading,
the peak hold, dBFS and the scale, red from −1 dBFS), which samples go
into an audio file around no audio and where it starts and stops, an
input volume's change once it held still, and an audio file's `clockDriftPpm` and `clockDriftCorrection`
(never `-0`), splitting interleaved and non-interleaved PCM, the guide
track mixes, audio file names and metadata, our process's CPU use, the
status window's rows, the version, the state file's content, the choice
of the crash report to offer and of the last recording's problems to
tell, the new-issue links of both (and that the issue forms have the
fields they fill; the problem report's cut to its length), the end of
`msr record`'s summary that offers a report, Report a problem with a
stand-in for the browser and Finder, the name of a crash report's text copy,
the text of the examples in this document, which the tests hold to
the code, the status line's text and cut (it counts the problems), the badge ("!" or none), that no
source file writes on standard error but the one writer, the error
detail (nested and multiple underlying errors, four-character codes,
the depth guard, a Swift error's own text, its JSON), that no source
file but the error detail's reads `localizedDescription`, and an
error's `errorDetail` in the recording manifest. The writer
itself is tested with a stand-in sink and on a pseudo-terminal, a pipe
and a pipe without a reader, in `RecorderCoreTests`. `RecorderCoreTests` test the recording log with a stand-in file and a
stand-in clock (appended, never rewritten, synchronized after each event
and problem, detail lines written with the next event or after 10 s,
a failing write told once until it works again, a detail line not held
up by a slow synchronize, Stop's close giving its failure) and the real file it
appends to, the writers' errors keeping the system's error chain, the output folder probe against
scratch folders, and that this Mac's audio inputs can be read and a
listener for their changes registered, which needs no permission and
shows no prompt, the state file (missing, saved, broken, updated), the listing of
the crash report folder (a missing one is no crash reports, an
unreadable one an error), the text copy of a crash report, screen files
written from synthetic frames and read back (constant frame rate,
timecode, BT.709, fragments, a file never finalized, the guide tracks),
audio files written from synthetic PCM and read back (a mono track per
channel or one stereo track, the bit rates, the timecode with its reel
name, the metadata, a filled gap decoding as silence, a file never
finalized, appends of 100 ms decoding the same as appends of 512
samples, stereo interleaved), the proof that an audio-only fragmented `.mov` carries a
timecode track, a screen file's ticks with a stand-in writer (a failing
writer, one that fell behind, a slow end, guide samples placed from the
file's first tick), audio captures with a stand-in source and writer
(appends of about 100 ms from buffers of 512 samples, the clock drift
status about once a second, each file's
`clockDriftCorrection` against a correction of the test's own, the
second file's counted from its own start, the correction's held-back
samples written when a capture ends by itself, dropped when its writer
failed or fell behind, with nothing written after that, also by a Stop
racing in; each buffer's peak in the level meter, `inputVolume` at a
file's start, no audio from the start getting no file, a file after no
audio starting before the sound, zeros shorter than 10 s staying in a
file, the system audio excluded), the input volume against a stand-in
for Core Audio (its property's address, a set clamped to 0 to 1, a
refusal, the listener; no test reads or sets a real device's volume), a
recorder audio only with a stand-in audio input and input volume
and a stand-in for the screens, and with stand-in cameras (a camera
appearing and vanishing, its stream failing, a frame without a picture,
and the Camera permission never asked, granted, denied, refused at the
request, not asked without a camera or under the camera mode None; a
camera without a first frame, one whose frames stop, one that stalls
and delivers again, and frames arriving after their tick was decided;
Stop and sleep and wake with a camera file) (`RecorderDevices.screens`; a wake whose
screens cannot be read still writes its wake event and restarts the
audio inputs) (`RecorderTests`: a failure told once by its event and its repeats
counted at Stop, D65; `inputVolume`, a change told once it held still,
also one Core Audio does not report, the slider's set, a refused set as
a problem, no slider where it cannot be set; the level meters; no audio
in the window and the manifest, not a problem, unless right after a gap
(D81); an input joining the guide track at its audio delay, leaving it,
rejoining, and a new file carrying its audio delay over, D79, D80), a stream stopped while it starts, that an action waiting for
the main run loop's default mode runs only there, the classification of
Core Audio's transport types, and the ready check's probes with
stand-ins (the output folder's file access is off the main thread). The
recorder's filter of the clock drift status by capture number, which
drops a status from a capture already replaced, has no unit test yet;
`RecorderTests` record no screen and open no camera. `AppTests` run the
start window's model with stand-in probes and a stand-in for the hold:
one check per burst of device changes, nothing applied while a menu is
open, a stale queued refresh does nothing, choices saved only when
changed, no ready check while recording, Start only when ready,
which quit finalizes without asking, where each kind of text of `msr
record` goes with and without `--quiet` (standard output the folder's
path only), when the status line is drawn and ended, that `--quiet`
with `--debug` is a usage error, and that the icon's frame in dark mode
follows the tile in the icon file. `CommandTests` run the built `msr`
with a scratch `HOME` (`msr settings`, with flags, `--resolution none`
and `--auto`, `msr record --help`, and `msr
version`, which prompt for nothing; also through a symbolic link into an
app bundle), `scripts/version` in scratch git repositories and
`scripts/unpack-app` on scratch archives (some written byte by byte, as
no tar would write them from a file system), `scripts/sign-app` and
`scripts/smoke-test` on a scratch bundle, and
`scripts/publish-snapshot-release` against a stub `gh`;
`scripts/smoke-test` runs the built app's `msr` the same way in the
pipeline. Capture itself is verified by the end-to-end tests, which
drive `msr record` as built and examine the recording folder, run by
hand in a tart VM on the owner's Mac (D67), and by the v1 gate. The design of the
end-to-end tests is [end-to-end-tests.md](end-to-end-tests.md) (D37);
their logic is unit-tested in `EndToEndLogicTests`.

## Not covered, and rejected

- **Rust**, also as a core under a Swift shell: every framework call
  would be `unsafe` through generated bindings (D17).
- **One JSON file per screen file** (the reference implementation):
  with a constant frame rate on a shared clock a file needs only its
  start offset.
- **A global "one recording at a time" lock:** folder claims allow
  parallel recordings at no extra cost (D20).
- **Mixing an input down to mono or stereo in its audio file:**
  channels may carry different people (D22); only the guide track
  "Audio inputs" is a mix, for playback and sync (D31).
- **A notification for low disk space:** see "The app".
- **Recording HDR screens as HDR:** files of mixed kinds on one
  timeline, larger files, and weak support outside DaVinci Resolve, for
  content that is rarely HDR (D24).
- **Sequenced after v0** (D18, D44, `backlog.md`): AGC.
- **A settings file refused, repaired on read or kept as a copy:** a
  settings file is read, what is invalid is ignored and named on
  standard error, and nothing is written until a person saves (D44).
- **A "Reset to defaults" in the window, an `--auto on` / `--auto off`
  value, a repair of the file on read:** the settings file is not
  something people deal with by hand (the owner, D44).
- **Every audio source in every screen file** (D12): one audio file
  per source instead, with guide tracks in the screen files (D31).
  Joining the files into one without re-encoding is deferred
  (`backlog.md`).
- **The command line driving the running app**, so a terminal needs no
  permissions of its own: deferred (`backlog.md`).
- **Screenshots as a fallback** for a screen that shows another
  screen's picture (`SCScreenshotManager`, right in 3 of 3 faulty
  runs, its cost at 30 frames per second unknown): a second capture
  path; deferred (`backlog.md`, D45).
- **Choosing audio inputs one by one** with auto mode off (open in
  D34): the audio mode `all-inputs` records every input, virtual ones
  included, which the end-to-end tests use; deferred (`backlog.md`).

## Open questions

- Unproven until the owner's first real recording with audio (D31):
  that DaVinci Resolve reads the timecode of an audio-only `.mov`, and
  how Kdenlive places the screen files and audio files.

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
(D45): B1 `msr record`, Start and Stop, the screen files with their
timecode, screen changes and the screen check, the recording
manifest and the Dock badge; B2 the audio files, the
guide tracks, system audio and the default microphone followed.

Built (the recording core's screens, B1, D45): `msr record` with
`--duration`, Start and Stop in the app, the Dock icon, its badge and
the status window also for `msr record`, the app quitting after Stop
and not on its last window closing while it records, the ready check
held while recording, the recording folder claim, the recording manifest with
its screen files and events, the shared clock, the tick grid with late
ticks, screen files (HEVC, fragments of 2 s, the timecode track,
BT.709), the frame size, screen identity by UUID, the settle time,
screens coming and going, failing streams with back-off, mirroring, the
main screen, sleep and wake, the screen check, a full disk and the
free space check, and keep awake. The frame rate is one value
(*data*); the tick grid, the timecode, the keyframe interval, the
late-tick bound (6 s) and the screen check's limit (1 s of frames)
derive from it. Tested without a screen: the logic by unit tests, and
screen files written from synthetic frames and read back (a constant
frame rate, the timecode, BT.709, a file never finalized readable up to
its last fragment). A finalized screen file is a regular movie:
Apple's writer joins the fragments when it finalizes [KNOWN, the
tests]. Live capture is verified on the owner's Mac.

Built in B1 where this document leaves the detail open, provisional and
for the architect to settle: the encoder's quality target (0.5) and
ceiling (4 times the estimated rate); `msr record` prints `Recording
into <folder>` at its start and, at its end, how long it recorded, each
file with its state, each failure event and each problem; it ends with
an error (exit 3) when the manifest's `result` is `problems` (D47): a
file is not finalized, a file was ended by a failure or a camera
stalled, and when the finalized manifest could not be written (the problem is told,
the app shows an alert after the person's Stop, never at logout, restart or shutdown, and the file on disk keeps no `ended`); `at` is rounded to
the millisecond; a screen file whose name is taken (a new file within
the same second) gets " (2)"; the timecode of tick 0 is t0's time of
day rounded to the nearest frame; after a full disk, new screen files
start once the free space is above the low disk warning threshold;
low disk space bounces the Dock icon until the app is activated; a
frame's rectangle passes the screen check within 0.5 points of its
screen's bounds.

Built (the recording core's audio, B2, D49): an `AVCaptureSession` per
recorded audio input, following the audio mode and the default
microphone; an unplug ending the audio file and a replug starting a new
one; a new audio file on a channel count change; the system audio from
a ScreenCaptureKit stream on the main screen, moving with it; audio
files placed on the tick grid, gaps up to 1 s filled with silence, a
longer one ending the file; `clockDriftPpm` per audio file; the guide
tracks "Audio inputs" and "System audio" in every screen file; audio
sources in the status window and the summary; audio files counted in
the low disk warning threshold; our process's CPU use in the status
window, the summary and the manifest. Tested without a microphone or a
screen: the logic by unit tests, audio captures with a stand-in source
and writer, audio files and guide tracks written from synthetic PCM and
read back. Verified live on the owner's Mac on 2026-11-16, build
`7ad0b6b`, in two runs by the owner and five by the architect: capture
from 4 audio inputs and the system audio into finalized files; default
microphone changes; a USB microphone unplugged and replugged, ending
its audio file and starting a new one; screens connected and
disconnected, a virtual screen and main screen changes among them;
the "System audio" guide track equal to `System audio.mov` at 0
samples of lag; the timecode aligned in DaVinci Resolve; the
"Microphones" (now "Audio inputs") gain of 1/√6 of that build, the rule D52 replaced,
measured. Seen there, and not the
recorder's: while USB devices re-enumerated, macOS delivered zeros on
the USB inputs and on the system audio for 4 to 10 s. Not verified
live: everything after `7ad0b6b` (the soft limiter of D52, the guide
tracks' end, the debug times), drift over an hour, and DaVinci
Resolve's reading of the audio files' metadata.

Built in B2 where this document leaves the detail open, decided by the
architect on review (D50): the failure events are named `audio input
failed`, `system audio failed`, `audio file writer failed` and `audio
file writer fell behind`; an event about an audio source names it in
`audioSource`, never in `screen`; samples lost at an audio file's end
are `audio file writer fell behind`, a failure; an audio source the
audio mode records but that has no file yet shows the state `not
recorded`; an audio input is recorded only when Core Audio gives its
UID, which `AVCaptureDevice` opens it by; the beginning of a recording
tells no `default microphone changed` or `audio input connected` events;
the system audio's stream asks for 2×2 pixels at 1 frame per second and
drops them; a screen file's guide tracks end with its video, by a last
mix at its end (D51); the video track's name is written as QuickTime
user data `©nam`, which ffprobe shows as `title` (track-level metadata
items do not show and are not written; the file-level items are); `msr
record`'s summary ends with the line `CPU N % on average, N % at the
peak, of one core (this process only)`.

Built (the clock drift correction): every audio source resampled to
follow the shared clock (see "Audio", "Clock drift"), `clockDriftPpm`
and `clockDriftCorrection` per audio file, the status window's "Clock
drift" column and the detail lines. Tested by unit tests against
simulated devices. Run on the owner's Mac on 2026-11-16 (two runs of
90 s, wired audio mode and the system audio; their builds were not
recorded) with one interval's smallest lateness, a follow time of 5 s
and a rate fit over 10: the system audio reached a false correction of
about +2 ms and wobbled 0.5 to 1.8 ms, because it arrives in bursts (see
end-to-end-tests.md). With the rolling minimum, the start after 5
intervals, a follow time of 15 s and a rate fit over 30, run again on
2026-11-17 (120 s, the same sources; its build was not recorded): the
system audio's correction stayed between +0.23 and +0.47 ms from 40 s on
(+0.79 ms at 20 s), its clock drift shown within ±4 ppm from 70 s on,
`clockDriftPpm` -2.7; the Razer Seiren V3 Mini -115.4 to -117.8 ppm and
at most 0.1 ms off from 50 s on, `clockDriftPpm` -115.7; CalDigit
Thunderbolt 3 Audio +47.9; MacBook Pro Microphone +2; Logitech BRIO
-37.7 (it wanders). Our process's CPU use was the same as before within
the runs' spread (51 % before; 47 %, 54 % and 56 % after). Not verified:
the correction over an hour, and by ear or by clicks in a real
recording.

A proportional-integral loop that followed a rolling minimum was built
and run next, and replaced (D57): the rolling minimum moved older
intervals along the loop's own integral, so the loop fed its own
measurement and ran away on long pauses and deep bursts. Rebuilt with
the lower support line (see "Clock drift") and run on the owner's Mac on
2026-11-17 on the build `0.20261117.49-dev+a8f374d.dirty`, the support
line before it was committed (180 s, wired audio mode and the system
audio, `--debug`): the clock drift shown from about 20 s; from 30 s on
the Razer Seiren V3 Mini -114.2 to -119.5 ppm and at most 0.15 ms off,
`clockDriftPpm` -116.1 with +20.8 ms corrected; CalDigit Thunderbolt 3
Audio +48.3 to +50.6 ppm and at most 0.07 ms off, +49.4; MacBook Pro
Microphone at most 0.04 ms off, +2.4; Logitech BRIO wandering from
-116.2 to +4.8 ppm, at most 0.97 ms off, +4.4; the system audio's
correction between -0.80 and -0.14 ms, at most 0.43 ms off, its clock
drift shown -2.9 to +13.3 ppm, `clockDriftPpm` +2.9. No gap and no
event. Our process's CPU use 54 % on average (51 % before the
correction). Run again on the build of `1e5bfe7` (2026-11-17, its
version string checked; 10 minutes, the same sources and options):
result ok, no event and no gap, our process's CPU use 55 %;
`clockDriftPpm` Razer Seiren V3 Mini -115.2, CalDigit Thunderbolt 3
Audio +49.7, Logitech BRIO +5.2, MacBook Pro Microphone +2.4, the system
audio -1.2; `clockDriftCorrection` Razer +0.0692 s, CalDigit -0.0297 s,
MacBook -0.0012 s, BRIO +0.0021 s, the system audio +0.0002 s; from 30 s
on at most 0.23 ms off (Razer), 0.10 (CalDigit), 0.11 (MacBook), 0.99
(BRIO) and 0.75 (the system audio). The four inputs' files end within
1.4 ms of each other. By the room's sound, the Razer's and the BRIO's
files keep the same lag: -16.4 ms in six of nine 90 s stretches (the
others -17.9 and -20.7 ms, in a quiet room), where uncorrected it would
have moved about 55 ms. With the kept slope, then the mean of the latest
slopes, and the rate hold, run on the build `0.20261117.49-dev+151b3b7`
(2026-11-17, 120 s, the same sources and options): result ok, no event
and no gap, our process's CPU use 54 %; `clockDriftPpm` Razer -115,
CalDigit +49.6, BRIO +6.2, MacBook +1.7, the system audio +0.8;
`clockDriftCorrection` Razer +0.0138 s, CalDigit -0.0059 s, BRIO
+0.0041 s, MacBook -0.0002 s, the system audio +0.0001 s; from 30 s on
at most 0.19 ms off (Razer), 0.10 (CalDigit), 0.04 (MacBook), 0.91
(BRIO, its clock drift shown wandering from -115.3 to +0.2 ppm) and 0.22
(the system audio). The final tracker, the median as the kept slope,
checked by the architect on the build `0.20261117.49-dev+cdd75ad`
(2026-11-17 05:09 Europe/Berlin, 180 s, all five audio sources and two
screens on the owner's Mac): result ok, no event; `clockDriftPpm` Razer
-115, CalDigit +50.3, MacBook +4.5, BRIO +4.7, the system audio +0.7;
`clockDriftCorrection` Razer +0.0206 s, CalDigit -0.009 s, MacBook
-0.0008 s, BRIO +0.0037 s, the system audio -0.0001 s; from 30 s on at
most 0.11 ms off (Razer), 0.13 (CalDigit), 0.05 (MacBook), 1.03 (BRIO)
and 0.32 (the system audio). Not verified: a real gap's drift, the order at a gap (the interval before it closed
before the jump) and the median across a real gap, which no real
recording has had yet (only the tests), and by ear or by clicks in a
real recording.

The hour run, on the build `0.20261117.49-dev+1fb8dae` (2026-11-17
07:36 to 08:36 Europe/Berlin, one hour, five audio sources and two
screens on the owner's Mac): result ok, no event; `clockDriftPpm` Razer
-115.2, CalDigit +50.2, BRIO +2.5, MacBook +3.2, the system audio +6.3;
`clockDriftCorrection` Razer +0.4139 s, CalDigit -0.1804 s, BRIO
-0.0146 s, MacBook -0.0108 s, the system audio +0.0002 s; "ms off" in
the detail lines from 30 s on at most 0.21 (Razer), 0.17 (CalDigit),
0.83 (BRIO), 0.10 (MacBook) and 0.92 (the system audio). By room sound
the Razer's and the BRIO's files kept the same lag, -16.1 to -16.8 ms
in ten of twelve 60 s stretches across the hour, the other two with too
little sound. CPU 37 % of one core on average.

The status line was run for 12 s under a pseudo-terminal on the build
`0.20261117.49-dev+4768d34`: standard output carried only the path, the
line redrew every second and was cleared before the summary; not yet
seen in the owner's own terminal.

Answered (D50's open question): the system audio's timestamps follow its
sample count, not the host clock. A probe of 120 s (128 s of data) of a
ScreenCaptureKit audio stream on the owner's Mac (2026-11-17) had every
timestamp at its sample count from the first to within a microsecond,
and the clock drift correction corrects the output device's clock drift
like an input's, so it shows as no `audio input gap` events.

Built (audio only, the first step of the CPU work and the icon's frame
in dark mode, D62): the recording resolution None (see "Audio only"
and "Ready check"); the audio files' appends of about 100 ms (see
"Appends"); `pcmSample` without an array per sample; in dark mode the
start window's header draws a frame of white at 25 % opacity, 1 pt, on
the edge of the icon's tile, scaled from the tile in
`assets/icon/app-icon.svg` (inset 4.7 pt, corner radius 8.6 pt at
48 pt; `IconTileFrame`), seen in an offscreen render of the header, not
yet in the running app.

CPU, the findings behind this step (backlog item 6, 2026-11-16, build
`7ad0b6b`, two displays): a 20 s `sample` put the 11 AAC encoders at
22 % (the guide tracks about 5.8 % per display), the movie writers at
6 %, the microphone capture at 7 %, VideoToolbox at 5 % (3 % of it
rebuilding a colour space from the frame's ICC profile, twice per
frame) and our own code at 1.6 %; steady CPU was 11.5 % for video only,
25.9 % with the system audio, 35.0 % with the default microphone too
and 62.0 % with all inputs. A replica of the audio path, real-time
paced, found the 94 appends a second, not the encoder, to be the main
cost: appends of about 100 ms gave bit-identical files and saved about
1.9 % of a core per input.

Measured with this step (2026-11-18, the owner's Mac: two screens, LG
Ultra HD at 2560×1440 and the built-in display at 1512×982; the system
audio and three inputs, Jabra Evolve3 65, Logitech BRIO with two
channels and the MacBook Pro Microphone): `msr record` for 3 minutes,
our process's CPU from 30 s to 170 s by `ps`, the build of `main`
(`0e179d4`) against this branch's, alternating:

| Settings | `main` | this branch |
|---|---|---|
| Auto (two screens at Native, the system audio, three inputs) | 45.8 %, 41.0 % | 31.5 %, 32.4 % |
| Video only (`--resolution native --audio-mode none --system-audio off`) | 11.3 % | 12.7 % |
| Audio only (`--resolution none --audio-mode wired`) | – | 19.3 % |

So about 11 percentage points of one core less with these four audio
sources, a quarter of the process's CPU; video alone is unchanged
within the runs' spread. `recording.json`'s `cpu` gave the same
averages within 0.6 points.

The colour space was left unchanged: with ScreenCaptureKit set to
deliver BT.709 (`colorSpaceName` and `colorMatrix`), so VideoToolbox
would not rebuild the colour space from the ICC profile, the decoded
frames were not the same as before, and the step was to be taken only
if they were (the owner, 2026-11-16; D24): recorded at the same time as
the unchanged build, the frames' mean Y was about 6 levels (of 255)
higher on both screens (108.1 against 114.5 on the LG, 114.8 against
120.8 on the built-in display), where two unchanged builds recording
together differed by under 0.05.

Built (cameras, D74): the camera mode (`--camera-mode`, the setting
`cameraMode`, the slider), a camera file per recorded camera on the
screen files' writer path (see "Cameras"), the Camera permission in the
ready check and while recording, cameras in "What will be recorded",
`recording.json`, the timeline file, the status window, the status line
and the summary. Capture from a real camera is UNVERIFIED: no test opens
a camera, and the end-to-end VM has none.

Details the design left open, as built and confirmed by the owner
(D25, D28, D44): a key missing from the settings file takes its default;
the output folder must start with `/` or `~`; the two number settings
must be greater than 0 (an invalid one is ignored, see "Settings file").
`msr version` prints the full
version string and the commit, such as `0.20261115.2-dev+a1b2c3d (a1b2c3d)`,
from the bundle's Info.plist keys `MSRVersion` and `MSRCommit`;
outside a bundle it prints `development build (not bundled)`. The
banner's build date is the key `MSRBuildDate`, the commit's date in
UTC, the same date the version carries, so a rebuild of the same
commit gives the same banner; a bundle without it says `built (build
date missing from Info.plist)`, and outside a bundle the banner has no
build date. The
settings file is found through `HOME`. The disk estimate follows its
rule, file by file (12.8 GB in the `msr check` example above). The
recording resolution box turns with a portrait screen (1080×1920 for a
2160×3840 screen at 1080p).

Further details, as built and decided by the architect for PR #1: an
unset `HOME` exits 78; `msr` that cannot re-execute
itself at its real path exits 71. When the screens cannot be read,
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
continues …" (`msr record` and `msr list` print the same table); a settings file that cannot be read as a whole is named
"the whole file" in the line on standard error; an input's transport
that cannot be read is not wired; `msr settings` with a flag that cannot
write exits 1; the window shows a red line when a save fails.
