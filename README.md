# Multi Screen Recorder
<img src="assets/icon/app-icon-fancy-256.jpeg" alt="Multi Screen Recorder app icon" width="96" align="right">

A reliable multi-source screen and audio recorder for macOS. It
captures every screen and audio source, never loses a recording, and
keeps going when screens, resolutions or audio sources change.

**Status:** in development. Builds record every screen and audio
source. The app shows its settings and the ready check and records with
Start, and the command line lists screens and audio inputs, runs the
ready check, records and manages the settings. An audio input with its
own clock still drifts against the screen files (measured, not yet
corrected).

## What it does

- **Every screen, as screens come and go.** Each screen gets its own
  video file. Plugging in a projector, removing it, or switching
  mirroring does not stop the recording.
- **Every audio source in its own file.** No audio, the default
  microphone, the wired audio inputs, or all audio inputs, plus the
  system audio if you want it.
  Each source gets an audio file of its own, each channel its own
  track; every screen file also carries two guide tracks, the
  audio inputs and the system audio, for playback and for syncing by
  waveform with a separate recording.
- **Edit-ready video.** A constant 30 frames per second, with a fixed
  frame size per file and a recording resolution you choose (Native,
  4K, 1440p, 1200p, 1080p or 720p), only ever scaled down. Native is the
  size macOS shows as "looks like" for the screen, not the size it is
  drawn at.
- **Auto mode.** On by default: every screen at Native and the wired
  audio inputs plus the default microphone, so you get a recording that
  is safe to sort out in the editor, at the expense of disk space.
  Switch it off to choose the resolution and the audio mode yourself.
- **Built not to lose anything.** A check before you start, warnings
  when disk space runs low, files that stay readable after a crash.
- **One button.** Start the app, approve the last settings, click
  Start. Click the Dock icon, then Stop. Everything also works from the
  command line, for scripting.
- **Nothing leaves your Mac.** The app makes no network connections.

It runs on macOS 26 and later, on Apple silicon. The homepage is
<https://multiscreenrecorder.schapiro.org>.

## Tester guide

Multi Screen Recorder is in testing. Thank you for trying it!

### Requirements

A Mac with Apple silicon (M1 or later) and macOS 26 or later.

### Installation

1. Download the zip from the
   [latest release](https://github.com/schlomo/multi-screen-recorder-macos/releases/latest)
   (or, to try a change before it is merged, the snapshot release of a
   pull request, `Snapshot PR #<n>`, from the
   [releases](https://github.com/schlomo/multi-screen-recorder-macos/releases)).
2. Unzip it and move `Multi Screen Recorder.app` to `/Applications`.
3. Start it from Finder. The app is signed with the project's own
   certificate, not by an Apple-registered developer, so macOS refuses
   to open it the first time. Open System Settings › Privacy & Security,
   scroll to "Multi Screen Recorder was blocked", click **Open Anyway**
   and confirm.
4. Grant the two permissions when macOS asks: **Screen & System Audio
   Recording** (for the screens and the system audio) and
   **Microphone** (asked only when a microphone is recorded: not on a
   Mac without an audio input, nor with the audio mode None). Both are in
   System Settings › Privacy & Security.
   A microphone permission allowed there, not in the prompt, counts
   only after you quit the app and start it again; if the screen
   recording permission still shows as missing, do the same.

Every build is signed with the same certificate, so a newer build
installed over an older one should keep both permissions; this is not
confirmed yet.

### Known limits

- **CPU:** recording takes about half of one CPU core over an hour,
  with two screens and five audio sources.
- **Audio drift:** some USB audio devices drift against the video, by
  up to about 0.4 s per hour. A correction is planned.
- **USB docks:** plugging a USB device into a dock while recording can
  cause a few seconds of silence or repeated audio in the USB audio
  inputs.

### Reporting a problem

Use the
[problem report form](https://github.com/schlomo/multi-screen-recorder-macos/issues/new?template=problem-report.yml)
(a GitHub account is needed). It asks for the output of `msr version`
(see "Command line" below; About Multi Screen Recorder in the app's
menu shows the same), what happened and what you expected, and the
recording's `recording.json`. Issues are public: the form says what
`recording.json` contains, so you can remove what you don't want to
share.

## Usage

Start the app from Finder: its window shows the app's icon, version
and homepage, then what will be recorded (one
table: the screens, with what each looks like, the size it is drawn at
and the size it records at, then the audio inputs and system audio, the
ones not recorded dimmed; each row with the most disk space it can write
per hour, "GB/h max", usually more than it writes; the total as the
last row; below it the space the required hours need and the free
space; the output folder, a link that opens it in Finder), then the switch "Auto" (on, the two sliders are grayed out and show Native and Wired; off,
they are enabled and show the recording resolution and the audio mode: None, Default
microphone, Wired or All, with a note under it on Bluetooth and virtual
microphones), system audio, the output folder and the ready check:
"Ready to record" when every item passes, otherwise each item with a
fix for each failing one. Every change is saved at once; the ready check runs again after each change,
when you come back to the app, when a screen is plugged in, removed
or changed, when an audio device is plugged in or removed, when the
default audio input changes, and on "Check again". Cancel, in the
lower right corner beside Start, quits without recording.

Click Start: the window closes; the Dock icon shows a "!" badge when
the disk runs low, a screen shows another screen's picture or
something went wrong. Click the Dock icon or quit to open the status
window: each screen and audio source with its files, the data written
and its state, the time recorded (`h:mm:ss`, every second), data and
free space, the CPU use of Multi Screen Recorder itself (encoding and
capture also run in macOS's own processes, which it does not include),
and any problems in red. Stop there finalizes the files, opens the
recording folder in Finder and quits; Continue keeps recording. The
recording folder holds a video file per screen, a new one each time a
screen comes back or changes its frame size, an audio file per audio
source (a microphone unplugged and plugged in again gets a new one),
and `recording.json`, which lists every file, what happened and every
problem, and says how the recording ended.

### Command line

The app's own executable is the command line. Link it into a folder on
your `PATH`, for example `~/bin` if that is on yours:

```sh
ln -s "/Applications/Multi Screen Recorder.app/Contents/MacOS/msr" ~/bin/msr
```

Started through the link, `msr` re-executes itself from inside the app,
so it shows the app's version and runs with its signature.

| Command | Does |
|---|---|
| `msr list` | Shows screens, audio inputs and system audio |
| `msr check [flags] [--debug]` | Prints the banner (name, version, build date, homepage) and what will be recorded, then runs the ready check; exits 0 when ready, 1 when not; creates the output folder if it is missing |
| `msr record [flags] [--duration 1h30m] [--debug]` | Prints the banner and what will be recorded and runs the ready check, then records until Ctrl-C, the duration or Stop in the status window (click the Dock icon); shows the app's Dock icon while it records and prints each event on standard error; `--duration` without a suffix is minutes; exits 0 when every file is finalized and no file was ended by a failure (a problem told alone, an unplugged microphone or a gap is listed but still exits 0), 1 when not ready, 3 when a file is not finalized, a file was ended by a failure, the recording manifest could not be written at the end, or the recording could not start |
| `msr settings [flags]` | Without flags prints the effective settings as JSON; with a settings flag saves the effective settings into the settings file and prints them, the only way a command writes it |
| `msr version` | Prints the version and commit |

Without flags a command uses the settings as they are. Each flag changes
a setting for this run only: `--auto` (no value: auto mode, whatever the
settings say), `--resolution` (`native`, `4k`, `1440p`, `1200p`, `1080p`,
`720p`), `--audio-mode` (`none`, `default-microphone`, `wired`,
`all-inputs`), `--system-audio` (`on`, `off`), `--output-folder`,
`--required-recording-hours`, `--low-disk-warning-minutes`.
`--resolution` and `--audio-mode` turn auto mode off for the run; `--auto`
together with either is a usage error. A usage error exits 64; an unset
`HOME` exits 78. The settings live in
`~/Library/Application Support/Multi Screen Recorder/settings.json`,
which nothing writes until you change a choice in the window or run
`msr settings` with a flag. Nothing refuses the file: what is unknown or
invalid in it is ignored, named on standard error, and the defaults
apply for it.

```sh
msr check --audio-mode none --required-recording-hours 4
msr record --resolution 1080p --duration 45m
msr settings                     # shows the settings
msr settings --resolution 1440p  # saves it, and turns auto mode off
msr settings --auto              # saves auto mode
```

Started from a terminal, macOS attributes the two permissions to the
terminal app (Terminal, iTerm and so on), not to Multi Screen Recorder:
grant them to the terminal app for `msr check` to pass and `msr record`
to record there.

## Developer setup

Once, on the Mac:

1. Xcode, with its licence accepted and selected:
   `sudo xcodebuild -license accept` and
   `sudo xcode-select -s /Applications/Xcode.app`. The Command Line
   Tools alone build the app but cannot run the tests.
2. Python 3.15 or later as `python3` on the `PATH`, for the scripts
   (the one macOS ships is older), such as from Homebrew:
   `brew install python@3.15`.
3. The signing certificate, in Keychain Access › Certificate Assistant ›
   Create a Certificate…: a name containing `Multi Screen Recorder
   Signing`, such as `Multi Screen Recorder Signing (<your name>)`;
   identity type Self-Signed Root, certificate type Code Signing, "Let
   me override defaults" ticked, validity 3650 days (the default is one
   year, and a new certificate means granting both permissions again),
   the rest unchanged, in the login keychain.
4. For the pipeline, by the repository owner only: export the
   certificate from My Certificates as `.p12` with an empty password,
   then

   ```sh
   base64 -i msr-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 --repo schlomo/multi-screen-recorder-macos
   rm msr-signing.p12
   ```

Then:

```sh
scripts/test        # runs the tests
scripts/build-app   # builds the app in build/, signed ad hoc
scripts/smoke-test  # runs the bundled msr: version, settings, exit codes
scripts/sign-app    # re-signs it with your certificate and zips it into build/
```

`scripts/sign-app` signs with the identity named in
`SIGNING_IDENTITY`, by default `Multi Screen Recorder Signing`, which
matches any certificate whose name contains it, such as
`Multi Screen Recorder Signing (Schlomo)`; `SIGNING_IDENTITY=-` signs
ad hoc, for a local check only. How the pipeline, versions and signing
fit together is in [docs/design/delivery.md](docs/design/delivery.md).

## Feedback

Please report problems with the
[problem report form](https://github.com/schlomo/multi-screen-recorder-macos/issues/new?template=problem-report.yml)
(see "Reporting a problem" above), and ideas as
[GitHub issues](https://github.com/schlomo/multi-screen-recorder-macos/issues).
If the app quit unexpectedly, it offers to report the crash report on
your next start: your browser opens a new issue (a GitHub account is
needed) and Finder shows a copy of the crash report as a text file to
drag into it. Issues are public, and a crash report contains your Mac's
user name: check it first.

The app and `msr` write what happens during a recording (every event and
problem) to the macOS unified log; `msr record --debug` and
`msr check --debug` add detail. To attach the log of the last 2 hours
to an issue, run in Terminal:

```sh
log show --last 2h --predicate 'subsystem == "org.schapiro.multiscreenrecorder" and process == "msr"'
```

## Origins

This project was inspired by
[psi-screencapture-macos](https://github.com/UBA-PSI/psi-screencapture-macos)
by Dominik Herrmann, developed at the Chair of Privacy and Security in
Information Systems (PSI), University of Bamberg. Thank you! Its code
served as a reference; Multi Screen Recorder is a separate
implementation.

## License

GNU General Public License version 3, see [LICENSE](LICENSE).

### Contributing

By submitting a contribution (pull request, patch or other material) you confirm that you have the right to do so. You grant Schlomo Schapiro a simple (non-exclusive), irrevocable, royalty-free right of use, unlimited in time and place, transferable and sublicensable, to use the contribution in all ways known today, in particular to reproduce, edit, distribute and make it publicly available, under the GPLv3 and under other licence terms, including paid distribution such as the Mac App Store. Everyone else receives your contribution under the GPLv3. Your moral rights (Urheberpersönlichkeitsrechte) are unaffected; German law applies.

### Licensing

Multi Screen Recorder is free software under the GPLv3. The author may also distribute builds under other terms, for example through the Mac App Store, whose terms the GPLv3 doesn't allow. The source stays GPLv3 and free to build.
