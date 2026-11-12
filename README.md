# Multi Screen Recorder

A reliable multi-source screen and audio recorder for macOS. It
captures every display and audio source, never loses a recording, and
keeps going when screens, resolutions or audio sources change.

**Status:** in development. There is nothing to install yet.

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
