# Multi Screen Recorder — architecture (current state)

A reliable multi-source screen and audio recorder for macOS. It
captures every display and audio source, never loses a recording, and
keeps going when screens, resolutions or audio sources change. It is
built for recording talks: one click to start, edit-ready files
afterwards.

Everything here is current and settled. Nothing here restates what
another file owns:

| For | Read |
|---|---|
| What this project is, concepts, worked examples | [../README.md](../README.md) |
| Vocabulary, defined once, used verbatim | [glossary.md](glossary.md) |
| Principles: engineering, AI working process, context economy | [principles/](principles/) |
| Decisions and rulings, dated, superseded ones kept | [decisions.md](decisions.md) |
| Detailed designs | [design/](design/) |
| Known failures, keyed by their exact error text | [troubleshooting.md](troubleshooting.md) |
| Work in flight, queued, deliberately deferred | [../backlog.md](../backlog.md) |

**Stakeholders:** the repository owner uses, operates, secures
and pays for it, and decides. Whoever runs a recording is responsible,
under data protection law (DSGVO), for the people and screen contents
it captures. Dominik Herrmann, author of the former upstream, is
credited for the reference implementation.

## 1. Guiding principles

- **Never lose a recording.** Every failure mode (a crash, a full disk,
  a failed stream, a display or audio source that disappears) leaves
  readable files and, where possible, keeps recording (D14).
- **Correct by content, not by timestamp.** A frame shows what was on
  the screen at its time; this is verified by looking at the picture,
  because a recorder whose timestamps looked right was off by up to
  76 s in content (D11).
- **Edit-ready output.** Constant 30 fps, fixed frame size per file,
  each audio source on its own track, so a file drops into a 30 fps
  editing timeline and syncs by waveform (D11, D12).
- **Nothing leaves the Mac.** No network access at all (D15).

## 2. Shape

Designed, not built yet: the repository holds no code. The designs:
[design/recorder.md](design/recorder.md) and
[design/delivery.md](design/delivery.md).

- **Recorder core:** one capture stream and one file writer per
  display, plus the audio sources; it watches displays and audio
  sources as they come and go.
- **Two front ends** over the same core, in one executable: the app
  (window, Dock icon) and the command line (D13, D19).
- **Settings:** one JSON file shared by both front ends (D13).
- **Output:** a recording folder per recording, holding a display file
  per display, an audio file per late audio source, and the recording
  manifest (D12, D20).

## 3. Decisions in force

### Product and licence

An independent product, written from scratch, with the former upstream
as a reference only and credited in the README (D1). GPLv3 (D2). No
contributions back to the former upstream (D16).

### Platform

macOS 26 and later on Apple silicon only (D10). Swift, always on the
latest released toolchain (D17).

### Recording

- Video: constant 30 fps on the host clock, hardware encoding, and a
  recording resolution that only ever shrinks the picture (D11); HEVC
  in `.mov`, no tick ever dropped, a timecode track in every display
  file (D21).
- Audio: none, the default microphone or all inputs, with system audio
  and AGC as separate switches; a file keeps the tracks it started with
  (D12); every input channel is its own mono track (D22).
- A recording folder and one recording manifest per recording;
  recordings into different folders may run in parallel (D20).
- Safeguards: a ready check before Start, low-disk warnings,
  crash-safe fragmented files, keeping the Mac awake (D14).
- No network connections; feedback goes to GitHub Issues (D15).

### Front ends

One recorder core; an app controlled through its Dock icon, and a
command line with every feature; one JSON settings file (D13). The
command line is the app's executable, and its flags mirror the settings
keys (D19).

### Delivery

v0 arrives as two PRs, the skeleton and pipeline before the recorder
(D18). GitHub, trunk `main`, squash merges (D3). Every PR builds an
installable snapshot release, every merge to `main` publishes a GitHub
release, versions count from the git history and stay 0.x until v1
(D4); a snapshot release is a pre-release per PR, a release is
`v0.<commits on main>.0`, and the build script never handles the
signing secret (D23). Builds
are signed with one self-signed certificate; Developer ID signing is
deferred (D5). Agents push work branches and open draft PRs; only the
owner merges (D8). AI-written commits and PRs say so (D9).

### Work tracking

`backlog.md`, with GitHub Issues as the intake for outside users (D6).

### Environments

The user's Mac only; the homepage on GitHub Pages at
`multiscreenrecorder.schapiro.org`, built from a separate branch (D7).

## 4. Open questions

See [backlog.md](../backlog.md).
