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
recording manifest, problem, status window, screen file, screen
identity, settle time, screen check, tick, timecode, audio track,
audio file, guide track, clock drift; D45, D49), labels (D55), the
banner, the recording log and the error detail (D64).

## Multi Screen Recorder

This product: the app and its command line for macOS. The repository is
`multi-screen-recorder-macos`; the bundle ID is
`org.schapiro.multiscreenrecorder`.

## Tagline

The product's promise, always shown as two lines: "Every screen, all
audio." and "Keeps going when things change." Shown in the app's
header and on the homepage; where one line is needed, the two joined by
a space (D55).

## Banner

What `msr check` and `msr record` print first, then an empty line: the
product's name with the version as `msr version` shows it and the build
date, the commit's date in UTC (`Multi Screen Recorder 0.20261116.42
(9dc9443), built 2026-11-16`), and the homepage's address
(`AppVersion.banner`).

## Former upstream

`UBA-PSI/psi-screencapture-macos`, the MIT-licensed project by Dominik
Herrmann (PSI chair, University of Bamberg) that this one started from.
Not a source of merges in either direction (D16).

## Reference implementation

The former upstream's code, used only to learn from; this project's
code is written from scratch (D1).

## Recording

Everything captured between Start and Stop: one or more screen files
and audio files, in one recording folder.

## Recording folder

The folder holding one recording, named by its local start time. A
recording claims it by creating it (D20).

## Recording manifest

`recording.json` in the recording folder: the settings, every file with
its start on the shared clock and its state, the events and the
problems, and once finalized its end and result (D20, D46).

## Recording log

`recording.log` in the recording folder, beside the recording manifest:
every event, every problem with its full error, and the detail lines,
one line each, appended and never rewritten, synchronized to disk after
each event and problem; written by every recording, in the app and in
`msr record` (D64). Not the unified log, which is macOS's.

## Detail line

A line about what the recorder did or read during a recording or the
ready check, beyond the events and problems: the tracker's actions, the
screens as read, files started and ended, the ready check's facts, the
clock drift block and the gaps. Always in the recording log; with
`--debug` also on standard error, as `detail <category>: …` (D64).

## Problem

Something that went wrong in a recording and that the person is told:
the Dock badge's "!", red in the status window, a line on standard
error in `msr record`, a line in the recording log, and an entry in the
recording manifest's `problems` with its time and full error (D46, D64).

## Error detail

An error with its full chain: its domain, code, description, failure
reason and recovery suggestion, and the error detail of every
underlying error. One line of it is the `error` of an event or problem;
the whole is its `errorDetail` in the recording manifest (D64).

## Status window

The small window of a running recording, opened by a click on the Dock
icon or by Quit, in the app and in `msr record`: what is recorded, the
data written, the problems, and Stop and Continue (D46).

## Status line

The one line `msr record` redraws once a second on standard error when
that is a terminal: the count of problems when there are any, then the
recording time, the size written, the files and the free space, the CPU
use and the sources being recorded, in that order. Not the window's own
line below its table.

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

## Screen

A monitor the Mac shows a picture on, built in or connected, by any
port. Apple's APIs and System Settings call it a display; this project
says screen everywhere else (D55).

## Label

What a recorded source is called in its file names, its reel name, its
track names and the terminal's tables (the window shows an icon for
the kind instead of the word):
`Screen <n> - <name>`, `Audio <n> - <name>`, or `Audio 0 - System` for
the system audio. The numbers count per kind from 1 in order of
appearance in the recording, and a source keeps its number when it
comes back (D55).

## Screen file

The video file for one screen, with its timecode and its guide tracks
(D31).
A screen that disappears or whose stream fails ends its screen file;
a new one begins when it is back. A screen whose frame size changes
also ends its file, and a new one begins after the settle time (D30,
D45). Sleep, mirroring, a writer too far behind and the screen check
end it too.

## Screen identity

What a recording knows a screen by: the UUID macOS gives it, never
its display ID or its name (D45).

## Settle time

How long a screen must stay unchanged before its stream starts or
starts again, so that quick mode changes make no burst of short screen
files (D45).

## Screen check

The check of every frame that it shows its own screen, by the screen
rectangle ScreenCaptureKit attaches to it; a frame that fails is never
written (D45).

## Frame size

The size a screen file is recorded at: the screen's looks-like size
fitted into the recording resolution box, each side rounded down to an
even number (D11, D25, D30, D44).

## Tick

One of the instants, 1/30 s apart from the recording's start, at which
every screen file gets a frame (D11, D21).

## Timecode

The time-of-day track in every screen file and every audio file, by
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
Bluetooth LE, virtual, aggregate, AirPlay, Continuity Capture, an
unknown transport and one that cannot be read are not wired. Auto mode's
audio mode, and the default (D44).

## Auto mode

The setting `auto`, on by default: every screen is recorded at Native
and the audio mode is Wired, whatever the two sliders (`resolution`,
`audioMode`) say; system audio, the output folder and the rest stay as
set. The sliders' defaults are auto mode's choices, so turning auto mode
off changes nothing until one is moved. In the window the switch "Auto"
grays out the sliders, which then show Native and Wired; on the command line `--auto` forces it for one run
(D34, D44).

## Audio file

The file for one audio source, beside the screen files: a recorded
audio input's audio tracks, one per channel, or the system audio's one
audio track, with its timecode. It starts when the source appears and
ends when it disappears or its channel count changes, which starts a new
one. Its samples sit on the tick grid by their count: a gap in the
audio up to 1 s is filled with silence, a longer one ends the file and
starts a new one (D31, D46, D49).

## Guide track

A track in a screen file for playback and waveform sync only:
"Audio inputs", one mono mix of the recorded audio inputs (each averaged
to mono, summed at unity gain, through a soft limiter; D52), or
"System audio", stereo; the two are never mixed together. Which ones a
screen file has follows from the settings alone; a missing source is
silence in its guide track (D31). It ends with its screen file's video
(D51), unless the file ended by a failure, or the samples for its last
mix were no longer there or the writer did not take them in time,
which is told as a problem.

## Clock drift

How far an audio device's clock runs from the shared clock, in parts
per million: positive when it runs fast (more samples than the shared
clock's time), negative when slow (D49). It is measured from when the
device's buffers arrive and corrected: every audio source's sound is
resampled continuously so its sample count follows the shared clock.
The recording manifest gives each audio file's clock drift at the
file's end as `clockDriftPpm` (D57; under D49 it was measured over the
whole file) and the sound the correction added as
`clockDriftCorrection`.

## Recording resolution

The maximum box a screen's looks-like size is shrunk to fit: 4K,
1440p, 1200p, 1080p or 720p, turned upright for a portrait screen, or
Native, which has no box. It never enlarges the picture (D11, D25, D44).
Or None (`none`), first on the slider, which records no screen: audio
only (D62). Said in full, "the recording resolution None", as the audio
mode has a None of its own.

## Audio only

A recording at the recording resolution None: its audio files and
`recording.json`, no screen file and so no guide track. The screens are
not recorded; a recording that would record neither a screen nor any
audio source does not pass the ready check (D62).

## Native

The recording resolution without a box: the size macOS shows as "looks
like" for the screen, never the size it is drawn at (D44).

## Looks like

macOS's word for a screen's size in points, as in System Settings ›
Displays; a column of the table. What Native records (D44).

## Drawn at

The screen's size in pixels, which a HiDPI mode makes larger than its
looks-like size; a column of the table. Never recorded (D44).

## Not recorded

A source the settings or its own state leave out of a recording: shown
dimmed in the window, without a number, with `-` for GB/h max (and for
Records at, for a screen at the recording resolution None), and, for an
audio input whose own rule leaves it out, the reason in parentheses
after its name (`(virtual)`, `(no device ID)`; D59, D62).

## Ready check

The check before Start: the permissions the recording needs, the
screens (at least one, each readable; at the recording resolution None
only with the system audio, which needs a main screen), the chosen audio sources, that something is recorded at all,
the output folder (created if missing, and written to), and free disk
space there for the required recording hours (D14, D28, D62).

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

`multiscreenrecorder.schapiro.org`: a Hugo site in `homepage/` on
`main`, built and served by Cloudflare Workers Builds (D53, which
replaces D7's GitHub Pages branch).

## End-to-end test

An automated test that runs the built app through a recording on a Mac
while screens and audio inputs change, and examines the recording
folder afterwards. Designed in
[design/end-to-end-tests.md](design/end-to-end-tests.md) (D37). Not an
acceptance test, which a person carries out for the v1 gate.

## Error class

A kind of thing that goes wrong with a recording, such as a file lost
or a wrong picture; the end-to-end tests are organised by it.
