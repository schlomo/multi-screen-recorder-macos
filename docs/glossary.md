# Glossary

Reference page, not an essay. Every term below is defined **once**,
here, and used verbatim everywhere else in this project — no synonyms,
no reusing a defined term for a second meaning (see
`principles/engineering.md`'s "One word per concept").

Where a concept is designed but not yet implemented, say so explicitly
rather than letting the definition imply it already exists. Built so
far: the recording resolution, audio mode and system audio as settings,
the ready check, and the pipeline for snapshot releases and releases.
Nothing a recording produces exists yet (recording, recording folder,
recording manifest, crash marker, display file, tick, timecode, audio
track, audio file, guide track).

## Multi Screen Recorder

This product: the app and its command line for macOS. The repository is
`multi-screen-recorder-macos`; the bundle ID is
`org.schapiro.multiscreenrecorder`.

## Former upstream

`UBA-PSI/psi-screencapture-macos`, the MIT-licensed project by Dominik
Herrmann (PSI chair, University of Bamberg) that this one started from.
Not a source of merges in either direction (D16).

## Reference implementation

The former upstream's code, used only to learn from; this project's
code is written from scratch (D1).

## Recording

Everything captured between Start and Stop: one or more display files
and audio files, in one recording folder.

## Recording folder

The folder holding one recording, named by its local start time. A
recording claims it by creating it (D20).

## Recording manifest

`recording.json` in the recording folder: the settings, every file with
its start on the shared clock and its state, and the events (D20).

## Crash marker

The file a recording process keeps while it records, naming its
recording folder; one left behind by a process that is gone marks a
recording that was not finalized (D20).

## Display file

The video file for one display, with its timecode and its guide tracks
(D31).
A display that disappears or whose stream fails ends its display file;
a new one begins when it is back. A display whose frame size changes
also ends its file, and a new one begins at once (D30).

## Frame size

The size a display file is recorded at: the display's pixel size fitted
into the recording resolution box, each side rounded down to an even
number (D11, D25, D30).

## Tick

One of the instants, 1/30 s apart from the recording's start, at which
every display file gets a frame (D11, D21).

## Timecode

The time-of-day track in every display file and every audio file, by
which an editor places files on a timeline (D21, D31).

## Audio track

One track in an audio file: one channel of an audio input, mono, or
the system audio, stereo (D22, D31).

## Audio source

A device whose sound is recorded: a microphone or other audio input, or
the system audio.

## System audio

What the Mac plays. A separate switch, independent of the audio mode.

## Audio mode

Which audio inputs are recorded: none, the default microphone, or all
audio inputs.

## Audio file

The file for one audio source, beside the display files: a recorded
audio input's audio tracks, one per channel, or the system audio's one
audio track, with its timecode. It starts when the source appears and
ends when it disappears, never padded with silence (D31).

## Guide track

A track in a display file for playback and waveform sync only:
"Microphones", one mono mix of all recorded microphone channels, or
"System audio", stereo; the two are never mixed together. Which ones a
display file has follows from the settings alone; a missing source is
silence in its guide track (D31).

## Recording resolution

The maximum box a display's picture is shrunk to fit: Native, 4K,
1440p, 1200p, 1080p or 720p, turned upright for a portrait display. It
never enlarges the picture (D11, D25).

## Ready check

The check before Start: the permissions, the displays (at least one,
each readable), the chosen audio sources, the output folder (created
if missing, and written to), and free disk space there for the
required recording hours (D14, D28).

## Required recording hours

The setting `requiredRecordingHours`: how many hours of recording the
free disk space in the output folder must hold for the ready check to
pass (D27).

## Snapshot release

The installable build a PR publishes, for trying the change before it
is merged (D4).

## Release

The GitHub release published by each merge to `main`, except a merge
that changes only Markdown files, which publishes nothing (D4, D23).

## v1

The first version the owner declares fit for their own use, once it
passes the v1 gate in `backlog.md`; versions before it are 0.x.

## User's Mac

The only environment the software runs in (D7).

## Homepage

`multiscreenrecorder.schapiro.org`, served by GitHub Pages from a
separate branch of this repository (D7).
