# Backlog

## Next session starts here

The v0 design is agreed (2026-11-12, D17–D23) and written down in
`docs/design/recorder.md` and `docs/design/delivery.md`. v0 arrives as
two PRs (D18).

In flight: the skeleton and pipeline PR, on the branch
`v0-skeleton-and-pipeline`. Next for an architect session: get it
adversarially reviewed, hand its snapshot release to the owner for the
check under "In flight", then brief the recorder PR. Before that brief,
the owner decides the open HDR question (queued item 1).

## In flight

- **Skeleton and pipeline PR** (D18), branch `v0-skeleton-and-pipeline`:
  the Swift package, the app window with the ready check, `msr list`,
  `check`, `settings` and `version`, the scripts and the pipeline, the
  README's installation and developer setup.
  - Waiting on the owner: the developer setup in
    `docs/design/delivery.md` (Xcode licence and selection, the signing
    certificate, the repository secret). Until the secret exists the
    pipeline cannot publish.
  - The owner's check on the Mac: install the snapshot release, "Open
    Anyway", start the app from Finder, grant both permissions; after a
    further push, install that snapshot release over the first: both
    permissions are still granted (D5). Also note whether macOS 26
    re-asks for the screen recording permission after some weeks.

## Queued

1. **Open decision, the owner's: HDR displays.** Record what the
   display shows (10-bit HDR, conversion left to the editor) or always
   SDR. The architect's recommendation, not yet agreed: SDR in v0,
   correctly tagged, with a `dynamicRange` setting to follow. Needed
   before the recorder PR is briefed.
2. **Recorder PR** (D18): the recording core, `msr record`, Start and
   Stop in the app, timecode (D21), mono tracks per channel (D22),
   `scripts/acceptance/`. The system audio stream needs a display to
   attach to and must move when that display disappears.
3. **Audio after v0** (D12, D18), each its own PR: the audio mode all
   inputs; the audio file for a late audio source; AGC, with its own
   design and the HDMI test.
4. **v1 gate:** acceptance tests on the owner's Mac (M3 Pro, macOS 26):
   - Timing by content: record a full-screen clock showing
     milliseconds; across a still period of at least 60 s followed by a
     change, each sampled frame shows the time of its timestamp within
     one frame.
   - `ffprobe`: r_frame_rate = avg_frame_rate = 30/1 and nb_frames close
     to duration × 30 for every display file; each audio input channel
     on its own track; the timecode of every display file matches its
     start.
   - One hour, two displays plus microphone: CPU load and file size per
     hour; calibrate the encoder quality, the disk estimate and the
     keyframe interval.
   - Audio drift: a click recorded at the start and after one hour, by
     a USB microphone and by a separate recorder, stays within one
     frame. If it does not, drift correction gets its own design.
   - Mid-recording: plug in and remove a display, change its
     resolution, toggle mirroring, plug and unplug a USB microphone,
     close and open the lid; the recording continues and every file
     stays readable.
   - AGC on: HDMI playback keeps its level.
   - DaVinci Resolve 21.1 on a 30 fps timeline: plays at 30 fps, places
     display files by timecode, and Auto Align Clips by waveform matches
     the microphone track to a separate recording.
   - Other players: the files open in QuickTime Player and, checked
     once by the owner, in Kdenlive.
   - A snapshot release installed over an earlier one keeps both
     permissions, with the app started from Finder (D5).
5. **App icon.** Until then the app has the default icon.
6. **Homepage** (D7): the branch name and how changes reach it
   (architect); the DNS entry for `multiscreenrecorder.schapiro.org`
   (owner).

## Deliberately deferred

- **Developer ID signing and notarization** (D5). Deferred because the
  Apple Developer Program costs €99 a year and the owner can work with
  a self-signed build. Revisit when users beyond the owner need to
  install it without "Open Anyway". It then needs an approval step
  before the signing job (D23).
- **Interface languages other than English** (D13). Revisit when users
  ask for one.
- **Rust**, also as a core under a Swift shell (D17). Revisit for a
  Linux or Windows version, or for encoder or container code of our
  own.
- **The command line driving the running app**, so that a terminal
  needs no permissions of its own (D19). Revisit when the owner scripts
  recordings from a terminal they don't want to grant screen recording
  to.

## Done (recent)

- 2026-11-12: v0 design agreed (D17–D23); it settled the former queued
  items "v0 design", "build and release pipeline" and "test strategy".
- 2026-11-12: project setup with the starter (D1–D16).
