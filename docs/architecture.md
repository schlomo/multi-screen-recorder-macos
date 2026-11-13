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
  readable display files and audio files and, where possible, keeps
  recording (D14, D31).
- **Correct by content, not by timestamp.** A frame shows what was on
  the screen at its time; this is verified by looking at the picture,
  because a recorder whose timestamps looked right was off by up to
  76 s in content (D11).
- **Edit-ready output.** Constant 30 fps, one frame size per display
  file, each audio source in its own audio file with every channel on
  its own track, and timecode in every file, so the files drop into a
  30 fps editing timeline and line up (D11, D21, D30, D31).
- **Nothing leaves the Mac.** No network access at all (D15).

## 2. Shape

The skeleton is built (the app window with the ready check and the
tables of what will be recorded, the command line without `record`, the
pipeline); recording is designed, not built yet. The designs:
[design/recorder.md](design/recorder.md) and
[design/delivery.md](design/delivery.md).

- **Recorder core:** one capture stream and one file writer per
  display, plus the audio sources; it watches displays and audio
  sources as they come and go.
- **Two front ends** over the same core, in one executable: the app
  (window, Dock icon) and the command line (D13, D19).
- **Settings:** one JSON file shared by both front ends (D13).
- **Output:** a recording folder per recording, holding the display
  files of each display, the audio files of each audio source, and the
  recording manifest (D20, D31).

## 3. Decisions in force

### Product and licence

An independent product, written from scratch, with the former upstream
as a reference only and credited in the README (D1). GPLv3 (D2). No
contributions back to the former upstream (D16).

### Platform

macOS 26 and later on Apple silicon only (D10). Swift, on the latest
toolchain that GitHub's generally available runner image offers (D17,
D28).

### Recording

- Video: constant 30 fps on the host clock, hardware encoding, and a
  recording resolution that only ever shrinks the picture and turns
  with a portrait display (D11, D25); a display whose frame size
  changes gets a new display file (D30); HEVC in `.mov`, no tick ever
  dropped, a timecode track in every file (D21, D31); always SDR (D24).
- Audio: none, the default microphone or all inputs, with system audio
  and AGC as separate switches (D12); one audio file per source, every
  input channel its own mono track (D22, D31); each display file
  carries two guide tracks, microphones and system audio, for playback
  and syncing (D31).
- Agreed and not built yet (D34): auto mode, on by default, records
  every display at its "looks like" size and all built-in and wired
  audio inputs plus the default microphone; a recording follows a
  change of the default microphone; a settings file is read, never
  refused. What AGC does is open (D34).
- A recording folder and one recording manifest per recording;
  recordings into different folders may run in parallel (D20).
- Safeguards: a ready check before Start, low-disk warnings,
  crash-safe fragmented files, keeping the Mac awake (D14). The window
  shows what will be recorded and what it costs in disk space (D26,
  D33).
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
`v0.<commits on main>.0` (D23). Building and signing run in separate
jobs: the job that compiles, tests and smoke-tests holds no secret, and
the signing jobs never compile or run what was built (D29). Scripts
with logic are Python from the runner image, standard library only
(D32). Builds
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
