# Glossary

Reference page, not an essay. Every term below is defined **once**,
here, and used verbatim everywhere else in this project — no synonyms,
no reusing a defined term for a second meaning (see
`principles/engineering.md`'s "One word per concept").

Where a concept is designed but not yet implemented, say so explicitly
rather than letting the definition imply it already exists. Built so
far: auto mode, the recording resolution, audio mode and system audio as
settings, the ready check, the pipeline for snapshot releases and
releases, and the recording core (recording, recording folder,
recording manifest, problem, status window, display file, display
identity, settle time, display check, tick, timecode, audio track,
audio file, guide track, clock drift; D45, D49).

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
its start on the shared clock and its state, the events and the
problems, and once finalized its end and result (D20, D46).

## Problem

Something that went wrong in a recording and that the person is told:
the Dock badge's "!", red in the status window, a line on standard
error in `msr record`, and an entry in the recording manifest's
`problems` with its time and full error (D46).

## Status window

The small window of a running recording, opened by a click on the Dock
icon or by Quit, in the app and in `msr record`: what is recorded, the
data written, the problems, and Stop and Continue (D46).

## Crash report

The `.ips` file macOS writes when `msr` quits unexpectedly, in
`~/Library/Logs/DiagnosticReports`; the app offers to report it as a
GitHub issue (D40).
Its text copy is the `.txt` copy the app makes in `Crash Reports` beside
the state file, because GitHub refuses `.ips` attachments.

## State file

`~/Library/Application Support/Multi Screen Recorder/state.json`: what
the app remembers between starts (the last offered crash report), kept
apart from the settings file because the person never edits it (D40).

## Restore file

The end-to-end driver's file of what a run changed, read by `restore`;
called "state file" in D38.

## Display file

The video file for one display, with its timecode and its guide tracks
(D31).
A display that disappears or whose stream fails ends its display file;
a new one begins when it is back. A display whose frame size changes
also ends its file, and a new one begins after the settle time (D30,
D45). Sleep, mirroring, a writer too far behind and the display check
end it too.

## Display identity

What a recording knows a display by: the UUID macOS gives it, never
its display ID or its name (D45).

## Settle time

How long a display must stay unchanged before its stream starts or
starts again, so that quick mode changes make no burst of short display
files (D45).

## Display check

The check of every frame that it shows its own display, by the screen
rectangle ScreenCaptureKit attaches to it; a frame that fails is never
written (D45).

## Frame size

The size a display file is recorded at: the display's looks-like size
fitted into the recording resolution box, each side rounded down to an
even number (D11, D25, D30, D44).

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

Which audio inputs are recorded, a slider of four steps: None (`none`),
Default microphone (`default-microphone`), Wired (`wired`) and All
(`all-inputs`). The default microphone is recorded in every audio mode
but None, whatever it is (D44).

## Wired

The audio mode Wired records the default microphone plus every audio
input that is built-in or connected by cable (built-in counts as wired):
built-in, USB, FireWire, PCI, Thunderbolt, HDMI
and DisplayPort, as Core Audio reports the transport type. Bluetooth,
Bluetooth LE, virtual, aggregate, AirPlay, Continuity capture, an
unknown transport and one that cannot be read are not wired. Auto mode's
audio mode, and the default (D44).

## Auto mode

The setting `auto`, on by default: every display is recorded at Native
and the audio mode is Wired, whatever the two sliders (`resolution`,
`audioMode`) say; system audio, the output folder and the rest stay as
set. The sliders' defaults are auto mode's choices, so turning auto mode
off changes nothing until one is moved. In the window the switch "Auto"
grays out the sliders, which then show Native and Wired; on the command line `--auto` forces it for one run
(D34, D44).

## Audio file

The file for one audio source, beside the display files: a recorded
audio input's audio tracks, one per channel, or the system audio's one
audio track, with its timecode. It starts when the source appears and
ends when it disappears or its channel count changes, which starts a new
one. Its samples sit on the tick grid by their count: a gap in the
audio up to 1 s is filled with silence, a longer one ends the file and
starts a new one (D31, D46, D49).

## Guide track

A track in a display file for playback and waveform sync only:
"Microphones", one mono mix of all recorded microphone channels, or
"System audio", stereo; the two are never mixed together. Which ones a
display file has follows from the settings alone; a missing source is
silence in its guide track (D31). It lags real time by 200 ms and is
handed over every 100 ms, so it may end up to 300 ms before its display
file (D49).

## Clock drift

How far an audio file's sample count runs from the tick grid, in parts
per million, measured over the file and given in the recording
manifest as `clockDriftPpm`: positive when the audio device's clock
runs fast (more samples than the grid's time), negative when slow. Not
corrected yet (D49).

## Recording resolution

The maximum box a display's looks-like size is shrunk to fit: 4K,
1440p, 1200p, 1080p or 720p, turned upright for a portrait display, or
Native, which has no box. It never enlarges the picture (D11, D25, D44).

## Native

The recording resolution without a box: the size macOS shows as "looks
like" for the display, never the size it is drawn at (D44).

## Looks like

macOS's word for a display's size in points, as in System Settings ›
Displays; a column of the table. What Native records (D44).

## Drawn at

The display's size in pixels, which a HiDPI mode makes larger than its
looks-like size; a column of the table. Never recorded (D44).

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
that changes only Markdown files, which publishes nothing (D4, D23, D42).

## v1

The first version the owner declares fit for their own use, once it
passes the v1 gate in `backlog.md`; versions before it are 0.x.

## User's Mac

The only environment the software runs in (D7).

## Homepage

`multiscreenrecorder.schapiro.org`, served by GitHub Pages from a
separate branch of this repository (D7).

## End-to-end test

An automated test that runs the built app through a recording on a Mac
while displays and audio inputs change, and examines the recording
folder afterwards. Designed in
[design/end-to-end-tests.md](design/end-to-end-tests.md) (D37). Not an
acceptance test, which a person carries out for the v1 gate.

## Error class

A kind of thing that goes wrong with a recording, such as a file lost
or a wrong picture; the end-to-end tests are organised by it.
