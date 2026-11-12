# Backlog

## Next session starts here

Setup is done (2026-11-12): purpose, decisions D1–D16 and the starter's
working model are in place; the repository holds no code yet.

Next: an architect session designs v0 (the recorder core, the app, the
command line, and the build and release pipeline) and agrees the design
with the owner as text. A builder then implements it in one
longer-lived PR whose snapshot release the owner installs and tries on
their Mac. The former upstream, `UBA-PSI/psi-screencapture-macos`, is
the reference implementation (D1).

## In flight

Nothing yet.

## Queued

1. **v0 design** (architect, agreed by the owner before building).
   Includes whether Apple's `SCRecordingOutput` can serve any part, given
   it likely cannot write a constant frame rate; the fragment length
   (D14); the encoder settings for small files on a still screen (D11);
   whether to keep the reference implementation's JSON file of
   timestamps beside each display file.
2. **Build and release pipeline** (D4, D5): snapshot release per PR,
   release per merge to `main`, version from the git history, signing
   with the self-signed certificate kept as a GitHub secret. Open, for
   the architect to propose: the version format; snapshot as pre-release
   or draft release; whether GitHub's macOS runners offer macOS 26 with
   Xcode 26. For the owner: create the certificate and store it as a
   secret.
3. **v0 implementation** in one PR, tried by the owner from its
   snapshot release.
4. **Test strategy** (architect): what the core's tests cover without
   real capture, and whether CI can capture at all (it needs the screen
   recording permission).
5. **v1 gate:** acceptance tests on the owner's Mac (M3 Pro, macOS 26):
   - Timing by content: record a full-screen clock showing
     milliseconds; across a still period of at least 60 s followed by a
     change, each sampled frame shows the time of its timestamp within
     one frame.
   - `ffprobe`: r_frame_rate = avg_frame_rate = 30/1 and nb_frames close
     to duration × 30 for every display file; each audio source on its
     own track.
   - One hour, two displays plus microphone: CPU load and file size per
     hour.
   - Mid-recording: plug in and remove a display, change its
     resolution, toggle mirroring, plug and unplug a USB microphone; the
     recording continues and every file stays readable.
   - AGC on: HDMI playback keeps its level.
   - DaVinci Resolve 21.1 on a 30 fps timeline: plays at 30 fps, and
     Auto Align Clips by waveform matches the microphone track to a
     separate recording.
   - A snapshot release installed over an earlier one keeps both
     permissions (D5).
6. **README:** installation (including "Open Anyway"), permissions and
   usage, once there is something to install.
7. **Homepage** (D7): the branch name and how changes reach it
   (architect); the DNS entry for `multiscreenrecorder.schapiro.org`
   (owner).

## Deliberately deferred

- **Developer ID signing and notarization** (D5). Deferred because the
  Apple Developer Program costs €99 a year and the owner can work with
  a self-signed build. Revisit when users beyond the owner need to
  install it without "Open Anyway".
- **Interface languages other than English** (D13). Revisit when users
  ask for one.

## Done (recent)

- 2026-11-12: project setup with the starter (D1–D16).
