# Multi Screen Recorder — architecture (current state)

A reliable multi-source screen and audio recorder for macOS. It
captures every screen, camera and audio source, never loses a recording, and
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
  a failed stream, a screen, camera or audio source that disappears)
  leaves readable video files and audio files and, where possible, keeps
  recording (D14, D31).
- **Correct by content, not by timestamp.** A frame shows what was on
  the screen at its time; this is verified by looking at the picture,
  because a recorder whose timestamps looked right was off by up to
  76 s in content (D11).
- **Edit-ready output.** Constant 30 fps, one frame size per video
  file, each audio source in its own audio file with every channel on
  its own track, and timecode in every file, so the files drop into a
  30 fps editing timeline and line up (D11, D21, D30, D31).
- **Nothing leaves the Mac.** No network access at all (D15).

## 2. Shape

The skeleton is built (the app window with the ready check and the
table of what will be recorded, auto mode, the command line without `record`, the
pipeline), and so is recording the screens (PR #11), the audio
(PR #12) and the cameras (PR #27, D74). The designs:
[design/recorder.md](design/recorder.md) and
[design/delivery.md](design/delivery.md); how the recorder is tested
end to end on a Mac: [design/end-to-end-tests.md](design/end-to-end-tests.md)
(D35, D37).

- **Recorder core:** one capture stream and one file writer per
  screen and per camera, sharing one video file path, plus the audio
  sources; it watches screens, cameras and audio sources as they come
  and go.
- **Two front ends** over the same core, in one executable: the app
  (window, Dock icon) and the command line (D13, D19).
- **Settings:** one JSON file shared by both front ends (D13).
- **Output:** a recording folder per recording, holding the screen
  files of each screen, the camera files of each camera, the audio files of each audio source, the
  recording manifest (D20, D31) and a timeline file for DaVinci
  Resolve (D68).

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
  with a portrait screen (D11, D25); a screen whose frame size
  changes gets a new screen file (D30); HEVC in `.mov`, no tick ever
  dropped, a timecode track in every file (D21, D31); always SDR (D24).
  The recording resolution None records no screen and no camera:
  audio only (D62, D74).
- Cameras (built in PR #27, D74): the camera mode none, default
  camera, all real (the default and auto mode's) or all (virtual
  cameras and iPhone cameras, Continuity Camera and Desk View, too);
  one camera file per camera, made like a screen file, with the same
  two guide tracks; each camera at 30 fps in the format, of any aspect
  ratio, that records the largest size once fitted into the recording
  resolution's box as a screen's picture is, the smallest of equal
  ones; a camera tick waits up to 0.5 s for a late frame; a camera
  that pauses for 2 s is stalled, its file going on, and one that sends
  no frames for 10 s is a failing stream; a suspended one is not
  recorded; the Camera permission is asked only when a camera would be
  recorded, and denied it records no camera, never blocking Start. A camera's own H.264 stream is not taken as-is (deferred).
- Screens (built in PR #11, D45, D46, D47): a screen is known by its
  UUID; a stream starts only after a settle time; every frame is
  checked against its screen and a screen showing another screen's
  picture ends its file loudly; every file ends at sleep, on a clock
  that counts sleep. `msr record` shows the app's Dock icon and can be
  stopped there through the status window; the app quits after Stop.
  A recording's `result` is `ok` unless part of it was lost; no crash
  markers (D47).
- Audio (built in PR #12, D49 to D52): one audio file per audio source,
  each with a timecode track; gaps over 32 ms filled up to 1 s, a new
  file beyond; every source resampled to the shared clock, its clock drift
  measured from buffer arrivals and corrected (D57); the
  "Audio inputs" guide mixes each input as mono at unity gain through a
  soft limiter (D52); guide tracks end with the video (D51).
- Audio: none, the default microphone, wired (the default microphone
  plus every built-in and wired input) or all inputs, with system audio
  and AGC as separate switches (D12, D44); one audio file per source, every
  input channel its own mono track (D22, D31); each screen file
  carries two guide tracks, microphones and system audio, for playback
  and syncing (D31); audio only has no screen file, so no guide track,
  and its system audio still needs a readable main screen (D62). Camera
  files carry the same two guide tracks (D74).
- Built (PR #9, D44): auto mode, on by default, records every screen
  at Native (its "looks like" size; the drawn-at size is never
  recorded) with the audio mode wired; a Bluetooth or virtual input
  only under "all inputs" or as the default microphone; a Mac without
  a microphone records screens and system audio; auto mode records
  every real camera (D74). The settings file is
  only read, never refused or repaired, and written only by the window
  and by `msr settings` with flags. A recording follows a change of
  the default microphone (D34, built in PR #12). What AGC does is
  open (D34).
- A recording folder and one recording manifest per recording;
  recordings into different folders may run in parallel (D20).
- A timeline file (OpenTimelineIO, in the form Resolve 21.2 exports)
  in every recording folder, written at Stop and by `msr timeline`;
  Resolve takes no resolution from it, so its first marker says
  what to set (D68).
- Safeguards: a ready check before Start (it refuses a recording with
  nothing to record, D62), low-disk warnings,
  crash-safe fragmented files, keeping the Mac awake (D14). The window
  shows what will be recorded and what it costs in disk space (D26,
  D33), and follows screens, cameras and audio inputs as they change
  (D36, D74).
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
`v0.<YYYYMMDD>.<commits on main>`, the date of its commit in UTC (D23,
D42). Building and signing run in separate
jobs: the job that compiles, tests and smoke-tests holds no secret, and
the signing jobs never compile or run what was built (D29). Scripts
with logic are Python from the runner image, standard library only
(D32). Builds
are signed with one self-signed certificate; Developer ID signing is
deferred (D5). Agents push work branches and open draft PRs, and mark a PR ready
once fully reviewed, handling a Copilot review only if one has
arrived (an optional extra, D43); only the owner merges (D8, D39). AI-written commits and PRs say so (D9).

### Work tracking

`backlog.md`, with GitHub Issues as the intake for outside users (D6).

### Environments

The user's Mac only; the homepage at
`multiscreenrecorder.schapiro.org`, a Hugo site in `homepage/` on
`main`, built and served by Cloudflare Workers Builds (D7, D53).

## 4. Open questions

See [backlog.md](../backlog.md).
