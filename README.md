# Multi Screen Recorder

A reliable multi-source screen and audio recorder for macOS. It
captures every display and audio source, never loses a recording, and
keeps going when screens, resolutions or audio sources change.

**Status:** in development. Builds can be installed, but they cannot
record yet: the app shows its settings and the ready check, and the
command line lists displays and audio inputs, runs the ready check and
manages the settings.

## What it does

- **Every display, as displays come and go.** Each display gets its own
  video file. Plugging in a projector, removing it, or switching
  mirroring does not stop the recording.
- **Every audio source on its own track.** No audio, the default
  microphone, or all audio inputs, plus the system audio if you want it.
  Each display file carries them as separate tracks, so it can be synced
  by waveform with a separate recording.
- **Edit-ready video.** A constant 30 frames per second, with a fixed
  frame size per file and a recording resolution you choose (Native,
  4K, 1440p, 1200p, 1080p or 720p), only ever scaled down.
- **Built not to lose anything.** A check before you start, warnings
  when disk space runs low, files that stay readable after a crash.
- **One button.** Start the app, approve the last settings, click
  Start. Click the Dock icon to stop. Everything also works from the
  command line, for scripting.
- **Nothing leaves your Mac.** The app makes no network connections.

It runs on macOS 26 and later, on Apple silicon.

## Installation

1. Download the zip from the
   [releases](https://github.com/schlomo/multi-screen-recorder-macos/releases):
   the latest release, or the snapshot release of a pull request
   (`Snapshot PR #<n>`) to try a change before it is merged.
2. Unzip it and move `Multi Screen Recorder.app` to `/Applications`.
3. Start it from Finder. The app is signed with the project's own
   certificate, not by an Apple-registered developer, so macOS refuses
   to open it the first time. Open System Settings › Privacy & Security,
   scroll to "Multi Screen Recorder was blocked", click **Open Anyway**
   and confirm.
4. Grant the two permissions when macOS asks: **Screen & System Audio
   Recording** (for the displays and the system audio) and
   **Microphone**. Both are in System Settings › Privacy & Security;
   macOS may ask you to restart the app after granting screen
   recording.

Every build is signed with the same certificate, so a newer build
installed over an older one should keep both permissions; this is not
confirmed yet.

## Usage

Start the app from Finder: its window shows what will be recorded (a
table of the displays, with what each looks like, the size it is
drawn at and the size it records at; a table of the audio inputs and
system audio, the ones not recorded dimmed; each with the disk space
it needs per hour, the total and the free space below; the output
folder), then the recording resolution, the audio mode, system audio,
the output folder and the ready check: "Ready to record" when every item
passes, otherwise each item with a fix for each failing one. Every
change is saved at once; the ready check runs again after each change,
when you come back to the app, and on "Check again".

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
| `msr list` | Shows displays, audio inputs and system audio |
| `msr check [flags]` | Runs the ready check; exits 0 when ready, 1 when not; creates the output folder if it is missing |
| `msr settings [flags] [--save]` | Prints the effective settings as JSON; `--save` writes the flags into the settings file |
| `msr version` | Prints the version and commit |

Each flag overrides a setting for this run only: `--resolution`
(`native`, `4k`, `1440p`, `1200p`, `1080p`, `720p`), `--audio-mode`
(`none`, `default-microphone`), `--system-audio` (`on`, `off`),
`--output-folder`, `--required-recording-hours`, `--low-disk-warning-minutes`.
A usage error exits 64. The settings live in
`~/Library/Application Support/Multi Screen Recorder/settings.json`; an
unknown key or invalid value there stops every command that reads the
settings (all but `msr version`) with an error naming the key, exit
78, and the app offers "Reset to defaults".

```sh
msr check --audio-mode none --required-recording-hours 4
msr settings --resolution 1440p --save
```

Started from a terminal, macOS attributes the two permissions to the
terminal app (Terminal, iTerm and so on), not to Multi Screen Recorder:
grant them to the terminal app for `msr check` to pass there.

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

Please report problems and ideas as
[GitHub issues](https://github.com/schlomo/multi-screen-recorder-macos/issues).

## Origins

This project was inspired by
[psi-screencapture-macos](https://github.com/UBA-PSI/psi-screencapture-macos)
by Dominik Herrmann, developed at the Chair of Privacy and Security in
Information Systems (PSI), University of Bamberg. Thank you! Its code
served as a reference; Multi Screen Recorder is a separate
implementation.

## License

GNU General Public License version 3, see [LICENSE](LICENSE).
