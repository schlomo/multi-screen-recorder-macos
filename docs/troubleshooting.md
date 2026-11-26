# Troubleshooting

Known failures, keyed by the exact error text a person or an agent
sees. Search here first when something fails ("Verify before
declaring ready" in
[principles/ai-working-process.md](principles/ai-working-process.md)):

```sh
grep -n -i -F "<a distinctive part of the error text>" docs/troubleshooting.md
```

An entry is added once its fix is verified, in the change that
verifies it. Entries are never deleted: one whose cause was fixed
upstream is marked resolved upstream, with the version, because the
same error comes back with an older version. A lesson worth knowing
before anyone hits it belongs with the project's other facts (see
`AGENTS.md`); this page starts from the error.

## Index

One row per entry, the error text exactly as in the entry.

| Error text (verbatim) | Entry |
|---|---|
| `package 'multi-screen-recorder-macos' is using Swift tools version 6.4.0 but the installed version is 6.3.3` | [Swift tools version newer than the CI runner's Xcode](#swift-tools-version-newer-than-the-ci-runners-xcode) |
| `no 'async' operations occur within 'await' expression` | [Swift Argument Parser's async main from top-level code](#swift-argument-parsers-async-main-from-top-level-code) |
| `The window has been marked as needing another Layout Window pass, but it has already had more Layout Window passes than there are views in the window.` | [Layout loop in a popup menu window after a HiDPI switch](#layout-loop-in-a-popup-menu-window-after-a-hidpi-switch) |
| The prompt for the Screen & System Audio Recording permission comes back each time the window is clicked (symptom, no error text) | [Screen recording prompt comes back with an ad hoc signed build](#screen-recording-prompt-comes-back-with-an-ad-hoc-signed-build) |
| `the writer took none of the last 4800 samples (0.100 s) of Razer Seiren V3 Mini within 2.0 seconds; they are lost` | [A timing test fails on CI while command tests run](#a-timing-test-fails-on-ci-while-command-tests-run) |
| `Expectation failed: (made.guides.map(\.2).reduce(0, +) → 0) == (videoSamples → 49600)` | [Async tests time out on CI while simulation tests run](#async-tests-time-out-on-ci-while-simulation-tests-run) |
| `the virtual screen 24 is not active at 1280x720 within 5 s, but 1600x900` | [A virtual screen comes back at its last mode](#a-virtual-screen-comes-back-at-its-last-mode) |
| `the virtual screen 122787BA-50AA-4A5A-B00C-3F98867665AF has no mode 1600x900: []` | [A long-running process sees no modes of a new screen](#a-long-running-process-sees-no-modes-of-a-new-screen) |
| `the program running this (a terminal app) lacks the Microphone permission; run msr check once from this terminal to get the prompt` | [The VM's Microphone permission reads as denied before its login](#the-vms-microphone-permission-reads-as-denied-before-its-login) |
| `timed out waiting for A out of the guide track again` | [A stand-in audio input's file ends after a pause of a slow runner](#a-stand-in-audio-inputs-file-ends-after-a-pause-of-a-slow-runner) |
| `Audio 2 Mic A sent only silence for 1.6 s after its gaps at 0:00, recovered` (an extra problem line in a test) | [A slow runner's pause gives a stand-in input a gap before its no audio](#a-slow-runners-pause-gives-a-stand-in-input-a-gap-before-its-no-audio) |
| `sending 'self' risks causing data races [#SendingRisksDataRace]` | [Swift 6.3 rejects self in a later argument after callbacks capture it](#swift-63-rejects-self-in-a-later-argument-after-callbacks-capture-it) |
| `AVFoundationErrorDomain -11800; reason: An unknown error occurred (-19092)` | [The end-to-end tests fail at a mode switch on a busy Mac](#the-end-to-end-tests-fail-at-a-mode-switch-on-a-busy-mac) |
| `The job was not acquired by Runner of type hosted even after multiple attempts` | [No macOS runner: the pipeline job is cancelled](#no-macos-runner-the-pipeline-job-is-cancelled) |
| `Multi Screen Recorder quit unexpectedly` (the app's crash dialog) after running the tests, with no crash of the app | [Crash dialog for crash reports the tests wrote](#crash-dialog-for-crash-reports-the-tests-wrote) |
| `Expectation failed: (made.guideRefusals → 2) == 4` | [Timing tests fail while the audio delay invariants run](#timing-tests-fail-while-the-audio-delay-invariants-run) |
| `Audio 0 - System: clock drift -1000.0 ppm, corrected +12.00 ms so far, 8.17 ms off`, then a lasting correction of about +20 ms at about 0 ppm | [The system audio is corrected by about 20 ms for good](#the-system-audio-is-corrected-by-about-20-ms-for-good) |
| `Expectation failed: (end → 0.1) <= (asked + 1.0 / 30 → 0.09997991733333333)`, later `Expectation failed: end <= stopped - 1` | [A camera file's end is checked against a clock reading taken before Stop](#a-camera-files-end-is-checked-against-a-clock-reading-taken-before-stop) |
| `camera stalled: FaceTime HD Camera (the camera delivered no frame for 2 s` | [A camera stalls while another camera starts](#a-camera-stalls-while-another-camera-starts) |

## Format

```markdown
## <short title>

- **Error:** `<the exact error text, verbatim>`
- **Symptom:** what is seen, and where (command, job, log).
- **Why:** the root cause, with its evidence tag.
- **Fix:** the literal command or change.
- **Verify:** the check that proves the fix worked.
- **Observed:** <date>, <tool and version>; open | resolved upstream
  in <version> (<date>).
```

## Swift Argument Parser's async main from top-level code

- **Error:** `no 'async' operations occur within 'await' expression`
- **Symptom:** `swift build` fails on `await CommandLineInterface.main()`
  (or `.main(nil)`) in `Sources/msr/main.swift`; warnings are errors
  in this package.
- **Why:** in `main.swift`'s top-level code the compiler picks the
  synchronous `ParsableCommand.main` overload over the async one of
  `AsyncParsableCommand`, so the `await` covers nothing [KNOWN:
  observed with Swift 6.4 and swift-argument-parser 1.8.2].
- **Fix:** no `main.swift`; an `@main` type. Since PR #11 its
  `static func main()` is synchronous: it parses with
  `CommandLineInterface.parseAsRoot` and runs a command other than
  `msr record` in a task under `dispatchMain()`, so the AppKit event
  loop starts outside any main-queue job (`Sources/msr/EntryPoint.swift`).
- **Verify:** `swift build` passes, and `msr settings --bogus` exits 64.
- **Observed:** 2026-11-12, Swift 6.4 (Xcode 27.2), swift-argument-parser
  1.8.2; open.

## Swift tools version newer than the CI runner's Xcode

- **Error:** `package 'multi-screen-recorder-macos' is using Swift tools version 6.4.0 but the installed version is 6.3.3`
- **Symptom:** the `test` job (now `test-and-build`) fails in
  `scripts/test` before compiling
  anything.
- **Why:** the newest generally available Apple-silicon runner image
  (`macos-26`) has Xcode 26.6 at most, with Swift 6.3.3, while a Mac
  with Xcode 27 has Swift 6.4 [KNOWN: the job log, and the image's
  readme in `actions/runner-images`].
- **Fix:** `// swift-tools-version: 6.3` in `Package.swift`; raise it
  once the runner image the workflow uses ships a newer Xcode, together
  with `DEVELOPER_DIR` in `.github/workflows/ci.yml`.
- **Verify:** the `test-and-build` job passes.
- **Observed:** 2026-11-12, runner image `macos-26` 20261102.0473.1,
  Xcode 26.6; open.

## Layout loop in a popup menu window after a HiDPI switch

- **Error:** `NSGenericException`: "The window has been marked as needing
  another Layout Window pass, but it has already had more Layout Window
  passes than there are views in the window." naming an
  `<NSPopupMenuWindow …>`, preceded by "-layoutSubtreeIfNeeded for
  <NSTableRowView …> has continued for 300 iterations".
- **Symptom:** the app quits (`EXC_CRASH (SIGABRT)`) 1 to 7 s after a
  screen's HiDPI (backing scale) mode was switched, with a popup menu
  of the start window open or opened. The `.ips` crash report does not
  carry the text; read it with
  `log show --predicate 'process == "msr"'`.
- **Why:** known: the exception names the popup menu window, the app's
  code has no table view, and the only window the log records past the
  layout limit is that popup window [KNOWN, unified log and code]; that
  the loop runs in the popup menu is [ASSUMED] from these (the log
  records only windows past the limit); its trigger the backing scale
  change [ASSUMED]; an AppKit or SwiftUI bug [CONJECTURE] (D41).
- **Fix:** no popup menus in the start window: the audio mode and the
  recording resolution are sliders (D41, D44).
- **Verify:** switch a screen's HiDPI mode with the start window open;
  the app keeps running. The owner tried on 2026-11-15 ("I couldn't
  provoke the crash"), which is evidence, not proof.
- **Observed:** 2026-11-14 and 2026-11-15, macOS 26 on the owner's
  Mac; open.

## Screen recording prompt comes back with an ad hoc signed build

- **Error:** none; the prompt for the Screen & System Audio Recording
  permission appears again each time the window is clicked after it was
  denied.
- **Symptom:** seen on 2026-11-15 with a build signed ad hoc
  (`scripts/build-app`, also an unchanged `main`), not with the release
  signed by the project certificate (the signed release 0.4.0 did not
  repeat the prompt: the owner's observation of 2026-11-15).
- **Why:** [ASSUMED] an ad hoc signature gives the app no stable
  identity, so macOS does not remember the answer.
- **Fix:** after `scripts/build-app`, run `scripts/sign-app`: its
  default identity matches the project certificate in the person's
  keychain ([delivery.md](design/delivery.md)). Another certificate
  name goes in `SIGNING_IDENTITY="<certificate name>"`.
  `security find-identity -p codesigning` lists the certificate;
  with `-v` it was not listed on 2026-11-15 (observed: self-signed,
  `CSSMERR_TP_NOT_TRUSTED`).
- **Verify:** click the window again after denying the permission; no
  second prompt. Fix verified: not yet; the signed release `0.4.0` not
  repeating the prompt is the contrast case, observed by the owner on
  2026-11-15.
- **Observed:** 2026-11-15, ad hoc build of `main`; open.

## A timing test fails on CI while command tests run

- **Error:** `the writer took none of the last 4800 samples (0.100 s) of Razer Seiren V3 Mini within 2.0 seconds; they are lost`
- **Symptom:** `AudioCaptureTests.samplesStillWaitingAtTheEndAreWrittenBeforeTheFileIsFinalized`
  fails in CI's `scripts/test` (runs 43906122035 and 43910044356 of
  PR #14) and passes locally.
- **Why:** [KNOWN] the test let a task make its stand-in writer ready
  after 50 ms, against a 2 s real-time bound. [KNOWN, measured locally]
  once the command tests' `run` waited off the cooperative pool, every
  command test started its program at once: up to 106 child processes
  together, against at most one per pool thread before. [CONJECTURE]
  on the 3-core hosted runner, that starved the task past the bound.
- **Fix:** the test's writer becomes ready on an event (after refusing
  the drain twice), with a bound far away; `run` in
  `Tests/CommandTests/Support.swift` runs at most one program per
  processor (`ProgramSlots`).
- **Verify:** CI's `scripts/test` passes; locally the command tests run
  at most 9 programs at once on 12 processors.
- **Observed:** 2026-11-16, PR #14; resolved.

## Async tests time out on CI while simulation tests run

- **Error:** `Expectation failed: (made.guides.map(\.2).reduce(0, +) → 0) == (videoSamples → 49600)`
- **Symptom:** in CI's `scripts/test` (run 44112113090 on 5494a9a of
  PR #19, the three `ScreenFileTickerTests`
  `theLastGuideSamplesWaitForTheWriterWithinTheDrainTimeout`,
  `theGuideTracksEndWithTheVideoAfterAStreamStopLongerThanFiveSeconds`
  and `aLongLastMixIsNotDroppedWhileTheWriterWaits`, each "failed after
  44.6 seconds"); the same code passed on 993842b (run 44111291663),
  and passes locally.
- **Why:** [KNOWN: the test code] the three tests made their stand-in
  writer ready from a task sleeping 20 ms, against a 30 s drain timeout.
  [KNOWN: measured locally with a probe test timing a 20 ms task]
  `ClockDriftTrackerTests` and `ClockDriftCorrectionTests` are
  synchronous and compute for about 28 s of CPU in all without
  suspending, so run in parallel each case holds a thread of the
  cooperative pool; in the same process as the ticker tests, a 20 ms
  task took 15.7, 16.5 and 2.2 s to run on 12 cores, and 0.02 to 0.5 s
  once the two suites were serialized. [KNOWN: CI's logs of runs
  44111291663 and 44112113090] nearly every test reports "passed after"
  about 29.7 s in the passing run and 44 s in the failing one, the ticker
  suite 0.2 s inside its 30 s bound in the passing run. [CONJECTURE] the
  hosted runner's pool has 3 threads and slower cores, so the same
  simulations hold it past 30 s; the three tests were not made to fail
  locally, whose pool has 12 threads.
- **Fix:** the two simulation suites run serialized
  (`@Suite(.serialized)`), so they hold at most two pool threads; the
  three ticker tests' stand-in writer becomes ready on an event (after
  refusing four times, each test asserting all four refusals, of which
  at most one comes before its drain), so none depends on a task being scheduled
  within the drain timeout. `GuideTrackFeedTests.theLastMixWaitsForSamplesThatComeLate`
  still delivers its late samples from a task after 150 ms, against a
  60 s bound: the feed's wait offers no event to deliver on, so the
  starvation pattern is left, with a bound 400 times the delay.
- **Verify:** CI's `scripts/test` passes on the pushed head.
- **Observed:** 2026-11-17, PR #19; resolved, CI passed with the fix
  (run 44125362376).
- **Observed again:** 2026-11-25, PR #32, run 45617470455 on 2f62829:
  `VideoFileTickerTests.aLongLastMixIsNotDroppedWhileTheWriterWaits`
  "failed after 31.696 seconds", `samples.count → 48000 == videoSamples
  → 337600` and `guideTracksCut` not empty, while
  `ClockDriftCorrectionTests` (56 s) and `ClockDriftTrackerTests` (92 s)
  ran in parallel on the 3-core hosted runner; it passed on 733a926 (run
  45516567075) and locally. The writer is ready on an event, but the
  30 s drain timeout was still within reach of a starved pool. Fix: the
  three ticker tests that wait for the writer
  (`theGuideTracksEndWithTheVideoAfterAStreamStopLongerThanFiveSeconds`,
  `aLongLastMixIsNotDroppedWhileTheWriterWaits`,
  `theLastGuideSamplesWaitForTheWriterWithinTheDrainTimeout`) use a
  120 s drain timeout, every assertion kept;
  `aLastMixTheWriterDoesNotTakeInTimeIsTold`, which asserts the timeout
  fires, keeps its 50 ms.

## Timing tests fail while the audio delay invariants run

- **Error:** `Expectation failed: (made.guideRefusals → 2) == 4` and
  `Expectation failed: received` (`GuideTrackFeedTests.swift:30`)
- **Symptom:** in CI's `scripts/test` (run 45784134449 on 585af40 of
  PR #34) `VideoFileTickerTests`
  `theGuideTracksEndWithTheVideoAfterAStreamStopLongerThanFiveSeconds`,
  `aLongLastMixIsNotDroppedWhileTheWriterWaits`,
  `theLastGuideSamplesWaitForTheWriterWithinTheDrainTimeout` and
  `GuideTrackFeedTests.theLastMixWaitsForSamplesThatComeLate` each
  "failed after 264 s", with their 120 s and 60 s bounds passed; the
  whole run took 519.7 s against 140.6 s on `main` (run 45659873665,
  the ticker suite 28.4 s there).
- **Why:** [KNOWN: CI's log] the four failed within 0.6 s of
  `AudioDelayInvariantTests.theReferenceRulesHold(seed:)` (200 cases)
  ended "after 263.789 s" and `ReferenceChoiceTests` "after 264.081 s".
  [KNOWN: the test code] the invariant harness's `run` was synchronous:
  each of the 200 cases computed for seconds without suspending, so the
  cases held every thread of the cooperative pool, and a task the timing
  tests wait on could not resume until they ended. [KNOWN: measured
  locally with a probe test sleeping 50 ms in a loop beside the two
  suites, 12 cores] its first resumption came 29.9 s late, the suites'
  whole run. The same cause as "Async tests time out on CI while
  simulation tests run" above, from new suites.
- **Fix:** the harness's `run` is async and yields once per measurement
  (`await Task.yield()`); the tests calling it are async. Every
  assertion, bound and seed kept. A case still holds a thread between
  two yields (measured locally: median 106 ms, at most 427 ms) and for
  its setup before the first. With it the probe's resumptions were at
  worst 2.1 to 2.4 s late over the same run. Serializing the suite, the
  earlier entry's remedy, is not used here: its 200 cases would run for
  many minutes on one thread. Yielding saves no CPU: CI's `scripts/test`
  step, build included, took 11 min 26 s (run 45786893084) against
  4 min 46 s on `main` before (run 45659873665).
- **Verify:** CI's `scripts/test` passes on the pushed head.
- **Observed:** 2026-11-26, PR #34; one passing run, 45786893084 on
  4c0ef05 (whole run 510.1 s), with a thin margin:
  `aLongLastMixIsNotDroppedWhileTheWriterWaits` took 106.7 s against
  its 120 s bound, the two other ticker tests 89.5 s each, and
  `GuideTrackFeedTests.theLastMixWaitsForSamplesThatComeLate` passed
  after 73.4 s, past its 60 s wait (not explained by the log). The pool is
  still short of threads for minutes: the serialized
  `ClockDriftCorrectionTests` (294.5 s) and `ClockDriftTrackerTests`
  (342.5 s) hold two of the runner's three threads without yielding
  while the invariant cases share the third. A slower runner can fail
  these tests again.
- **Observed again** (PR #35): the
  measurement built an FFT setup per cross-correlation, 68 % of the
  invariant suite's time in `vDSP_create_fftsetup` [KNOWN: sampled
  locally]; `AudioDelay` now keeps one setup per size for the process
  (the vectorised result stays bit-equal to the scalar one). The
  invariant harness measures main's rules once when they share the new
  rules' reference and windows, and `RecorderTests` builds each noise
  and burst table once per process, bit-identical samples. Measured locally from a clean build (12
  cores, same machine, `scripts/test` including the build): whole run
  3:25.91 wall and 717.6 s user CPU on `main` against 2:23.84 to 2:27.85
  wall and 461.7 s to 481.9 s user CPU on this PR's head (two runs); `AudioDelayInvariantTests`
  36.8 s to 15.6 s; the `RecorderCoreTests` target 107.4 s to 64.8 s;
  the `RecorderLogicTests` target 49.5 s to 30.3 s. On CI (run
  45802785455 on 67ccea2): the `scripts/test` step 5 min 16 s against
  11 min 26 s, the test run 172.0 s against 510.1 s (`main` before
  PR #34: 140.6 s), `theReferenceRulesHold` 82.0 s against 294.6 s,
  `VideoFileTickerTests` 44.4 s and `GuideTrackFeedTests` 40.1 s
  against their 120 s and 60 s bounds. What remains:
  the CPU-bound suites (the invariant cases, the two clock drift suites)
  still share the cooperative pool with the real-time-bounded tests, so
  a slow runner can still push those near their bounds; the lever left,
  the owner's to choose, is the two clock drift suites yielding too.

## A virtual screen comes back at its last mode

- **Error:** `the virtual screen 24 is not active at 1280x720 within 5 s, but 1600x900`
- **Symptom:** `scripts/end-to-end-test`, the scenario `virtual-screen`
  stops when its screen connects (the number varies), after an earlier
  run switched that screen's mode and was killed, or with a helper that
  does not put the mode back.
- **Why:** macOS brings a virtual screen back at the last mode its
  identity (vendor, product, serial number) had, whatever modes it is
  given, also after a switch for the app only [KNOWN: tried on the
  owner's Mac, 2026-11-19, macOS 27.2.1]. A switch within about a
  second of the screen appearing is undone as macOS applies that mode.
- **Fix:** the device helper puts its screen back to its first size
  when it starts (after a second) and when it ends (SIGTERM, SIGINT or
  its standard input closing), so the next screen of that identity
  starts there; a scenario switches back before it disconnects.
- **Verify:** a helper switched to 1600x900 and ended by SIGTERM; the
  next helper of that identity connects at 1280x720 within 0.4 s.
- **Observed:** 2026-11-19, macOS 27.2.1; open.

## A long-running process sees no modes of a new screen

- **Error:** `the virtual screen 122787BA-50AA-4A5A-B00C-3F98867665AF has no mode 1600x900: []`
- **Symptom:** the driver could not switch a virtual screen's mode:
  `CGDisplayCopyAllDisplayModes` and `CGDisplayCopyDisplayMode` gave
  nothing for a screen that connected after the process had read the
  modes of the Mac's own screens, while `CGDisplayBounds` was right.
- **Why:** a process keeps the screens' modes it read first and does
  not learn a new screen's; a pass of the run loop did not change that
  [KNOWN: tried on the owner's Mac, 2026-11-19, macOS 27.2.1].
- **Fix:** every mode switch is a process of its own
  (`msr-end-to-end switch-mode`), and so is every read of the state
  after a run (`state`, `restore`).
- **Verify:** `scripts/end-to-end-test --scratch-folder <folder> --scenario virtual-screen`
  passes, with its three screen files at 1280x720, 1600x900, 1280x720.
- **Observed:** 2026-11-19, macOS 27.2.1; open.

## The VM's Microphone permission reads as denied before its login

- **Error:** `the program running this (a terminal app) lacks the Microphone permission; run msr check once from this terminal to get the prompt`
- **Symptom:** `scripts/end-to-end-test` stops before any scenario,
  in a freshly booted VM clone, right after the Screen Recording
  precondition passed; the next run on the same image passes.
- **Why:** the VM answers over SSH before the automatic login of
  `admin` has finished. Until then nobody owns the console (`root`),
  the user's GUI domain (`gui/501`) and its `tccd` do not exist, and
  `AVCaptureDevice.authorizationStatus(for: .audio)` reads denied (2)
  for a program started with `launchctl asuser`, while
  `CGPreflightScreenCaptureAccess`, answered by the system's `tccd`,
  reads granted; within seconds of the login it reads authorized (3)
  [KNOWN: a probe in four throwaway clones of the end-to-end VM,
  2026-11-22; caught in the two whose SSH answered within 12 s of the
  boot].
- **Fix:** `scripts/end-to-end-test` waits, before it starts the
  driver, until `admin` owns the console and
  `launchctl print gui/<uid>/com.apple.tccd` says `state = running`
  (`vm_wait_for_login` in `scripts/end-to-end-vm/lib.sh`, at most
  120 s, then it stops with an error); it prints how many 1 s waits
  that took.
- **Verify:** `scripts/end-to-end-test --scratch-folder <folder>`
  prints `admin is logged in` before the driver's first line, and the
  run passes its preconditions. Four consecutive runs passed, each
  logged in before the wait began (the app's copy into the VM takes
  longer than the login), so the wait itself is verified by the probe
  above, not by a run.
- **Observed:** 2026-11-21 (PR #25's runs) and 2026-11-22, the
  end-to-end VM (Cirrus Labs' `macos-tahoe-vanilla`); open.

## A stand-in audio input's file ends after a pause of a slow runner

- **Error:** `timed out waiting for A out of the guide track again`
- **Symptom:** in CI's `scripts/test` (run 45242373454 on 4115a17 of
  PR #27), `RecorderTests.anAudioInputOutOnAFalseFirstWindowRejoinsOnItsMedianAndLeavesAgainOnIt`
  times out and throws `CancellationError`, and
  `anAudioInputOutOfSyncLeavesTheGuideTrackUntilItsFileEnds` fails on
  `!isInTheGuideTrack(a)`, on the problem line (`Audio 2 Mic A was not
  in the guide track from 0:03 to 0:03 (500 ms late); …` instead of the
  present one) and on `audioFiles.allSatisfy { $0.end == nil }`; both
  pass locally.
- **Why:** [KNOWN: the test code] the tests sent their stand-in
  buffers timestamped at the host clock's now, so a pause between two
  sends became a gap in the input's audio; after the audio files
  started, the next buffer to A came only after the delay measurements
  (`feedDelayedNoise`, `measureAudioDelays`). [KNOWN:
  `AudioFileTimeline`, `RecorderValues.longestFilledAudioGap`] a gap
  longer than 1 s ends the file, and the input's next sound starts a
  new file, in the guide track and not yet measured (before D80; a new
  file now carries its input's audio delay over). [KNOWN: reproduced
  locally, 2026-11-23] with 36 `yes` processes on 12 cores, the second
  test failed 5 of 5 runs, A's first file ending at 0.09 s and the next
  starting at 1.1 s; a 1.5 s sleep after the measurement gave the first
  test exactly CI's three failures, and a 3.5 s sleep gave the second
  CI's timeout: a file starting after 3 s of the recording holds none
  of the measured windows (the fed noise ends at 13 s, a window is
  10 s), so A never leaves again.
- **Fix:** the buffers sent to A after the measurements continue from
  the end of the latest buffer sent to it (`sendNext` in
  `Tests/RecorderCoreTests/RecorderTests.swift`), on the test's own
  clock instead of now, so no runner's pause makes a gap. The recorder
  is right to end the file at such a gap; nothing changed there.
- **Verify:** the two tests pass 20 of 20 runs under the same load, and
  with the 1.5 s and 3.5 s sleeps; CI's `scripts/test` passes on the
  pushed head.
- **Observed:** 2026-11-23, PR #27, runner Xcode 26.6; resolved
  (the pipeline on abc1953 passed).
- **Since D90:** an input no longer leaves or rejoins the guide track
  and has no problem line for it; the two tests became
  `anAudioInputUnmixedOnAFalseFirstWindowIsMixedOnceItsMedianFits`
  (whose wait reads `A out of the guide track again`) and
  `anAudioInputBeyondTheLimitIsNotMixedOnlyItsRowSayingSo`, both
  sending with `sendNext`.

## A slow runner's pause gives a stand-in input a gap before its no audio

- **Error:** `Expectation failed: (recorder.problemLines().map(\.text) → ["Audio 2 Mic A sent only silence for 1.6 s after its gaps at 0:00, recovered", "Audio 2 Mic A 900 ms late, not in the guide track; its own audio track is recorded"])`
- **Symptom:** in CI's `scripts/test` (run 45427807337 on a5682a7 of
  PR #30), `RecorderTests.anAudioInputThatLeftTheGuideTrackStaysOutWithItsNextFile`
  has an extra D81 line; it passes locally. Locally under load (three
  `yes` processes per core, 2026-11-24) the same test failed 4 of 11
  runs, there with another extra line, `camera stream failed: the camera
  delivered no frame within 5 s of its start`.
- **Why:** [KNOWN: the test code] `startAudioFiles` sent each try's
  buffer timestamped at the host clock's now, so a runner's pause
  between two tries became a gap in the input's audio at 0:00; the
  test's no audio then began within 10 s of it, which D81 rightly tells
  as an input broken by its gaps. [KNOWN: recording.log of a local
  failing run] the stand-in camera of `startInputs`, there only so the
  guide tracks exist, sends no frame, and a test slower than 5 s hits
  its first-frame limit. The recorder is right in both.
- **Fix:** `startAudioFiles` sends each try on from the source's latest
  buffer (`sendNext`), as the fix of "A stand-in audio input's file ends
  after a pause of a slow runner" did for the later buffers; `startInputs`
  gives its camera a first-frame limit of 600 s.
- **Verify:** the guide-track tests pass 10 of 10 runs under the same
  load; CI's `scripts/test` passes on the pushed head.
- **Since D90:** the test is
  `anAudioInputBeyondTheLimitIsNotMixedOnlyItsRowSayingSo`, which
  expects no problem line at all; the guide track's line in the error
  text is no longer told.

## Swift 6.3 rejects self in a later argument after callbacks capture it

- **Error:** `sending 'self' risks causing data races [#SendingRisksDataRace]`
- **Symptom:** CI's `scripts/test` fails to compile
  `Recorder.performCamera`, with the note "task-isolated 'self' is
  captured by a main actor-isolated closure. main actor-isolated uses in
  closure may race against later nonisolated uses"; the same code builds
  with Swift 6.4 on a Mac with Xcode 27.
- **Why:** Swift 6.3, not 6.4, rejects a use of `self` in a later
  argument of the same call after callbacks in earlier arguments
  captured it [KNOWN: the CI log of PR #27; the local build with
  Swift 6.4 passed].
- **Fix:** read the value into a local before the call and pass the
  local (`checksOrientation` in `Recorder.performCamera`, 4115a17).
- **Verify:** CI's `scripts/test` compiles the package (run
  45242373454 on 4115a17 got past the build to the tests).
- **Observed:** 2026-11-23, PR #27, runner Xcode 26.6; resolved
  (the pipeline on abc1953 passed).

## The end-to-end tests fail at a mode switch on a busy Mac

- **Error:** `AVFoundationErrorDomain -11800; reason: An unknown error occurred (-19092)`
- **Symptom:** `scripts/end-to-end-test` (and
  `scripts/update-homepage-screenshots`) fail `virtual-screen`, often
  `virtual-screen-stress` too: a `screen file writer failed` event with
  this error, or, without it, lines such as `ends at 8.33 s, expected
  6.59 s to 7.59 s, the settle time after the screen's last change at
  6.09 s` (the driver's output); sometimes the app's window captures
  fail with `no window of process 522 on screen within 20 s`.
- **Why:** [KNOWN: the runs of 2026-11-23 from about 19:45 and of
  2026-11-24, Europe/Berlin] 9 of 10 runs failed while a Lima VM, ClamXAV,
  Synology Active Backup and DaVinci Resolve ran on the Mac (a load of 10
  to 15 on 12 cores): the release v0.20261123.93 5 of 5 (the encoder
  error in 2 of the 3 with Resolve open, in neither of the 2 with it
  closed), the previous release v0.20261122.89 3 of 3, a local build of
  the release's code 1 of 2. With all of them stopped (a load of 3 to 6),
  the release passed 3 runs of 3; local builds had passed 2 of 2 earlier
  on 2026-11-23, before the Lima VM ran. [CONJECTURE] the VM's
  paravirtualized encoder and its processors wait behind the Mac's other
  work, as on GitHub's hosted runner (D67).
- **Fix:** run the end-to-end tests on an idle Mac: no other virtual
  machine, no video editing, no virus scan or backup running.
- **Verify:** 3 runs in a row pass; `uptime` shows a load well below
  the number of cores.
- **Observed:** 2026-11-23 and 2026-11-24, macOS 27.2.1, tart 2.42.0;
  open (no fix in the project; the Mac is kept idle).
## No macOS runner: the pipeline job is cancelled

- **Error:** `The job was not acquired by Runner of type hosted even after multiple attempts`,
  next to `Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.`
- **Symptom:** `test-and-build` ends as cancelled after about 15
  minutes with no runner name and no log; the jobs after it are
  skipped, so a merge to `main` makes no release.
- **Why:** [KNOWN: the run's annotations] GitHub had no hosted
  Apple-silicon macOS runner free for the job; nothing in the
  repository caused it.
- **Fix:** re-run the run (`gh run rerun <run id>`), never a new push:
  the code is unchanged, and on `main` the re-run makes the release the
  merge asked for.
- **Verify:** the re-run's `test-and-build` gets a runner and passes,
  and on `main` the release job publishes `v0.<DATE>.<N>`.
- **Observed:** 2026-11-17, twice: the release run of PR #19's merge,
  and run 44167197917 of PR #20's merge; both re-run.

## Crash dialog for crash reports the tests wrote

- **Error:** the app's dialog `Multi Screen Recorder quit unexpectedly`
  on start, after `scripts/test` ran on the same Mac, while the app
  itself had not crashed.
- **Symptom:** `~/Library/Logs/DiagnosticReports` holds `msr-*.ips`
  reports whose `procPath` is a temporary folder, with
  `SIGKILL (Code Signature Invalid)` and `Launch Constraint Violation`.
- **Why:** [KNOWN: the reports' `codeSigningID com.apple.sleep`] the
  `scripts/install-app` tests used a copy of `/bin/sleep` named `msr`
  as their stand-in app; macOS sometimes kills such a copy of a system
  program at launch and writes a crash report named after it, and the
  app offers every `msr` crash report it finds. The same kill made a
  test's `waitUntilExit()` hang one run in eight.
- **Fix:** the stand-in is a program the tests compile with `cc`, and
  the test waits for it through its termination handler (PR #20).
  Delete the reports left over:
  `rm ~/Library/Logs/DiagnosticReports/msr-<date>-<time>.ips` for each
  one with a temporary `procPath`. Since D70 the app offers only its
  own reports, so these no longer show.
- **Verify:** 20 runs of `InstallAppScriptTests` write no new
  `msr-*.ips`.
- **Observed:** 2026-11-17, PR #20; resolved.

## A camera file's end is checked against a clock reading taken before Stop

- **Error:** `Expectation failed: (end → 0.1) <= (asked + 1.0 / 30 → 0.09997991733333333)`
- **Symptom:** in CI (run 45811289731, PR #36), `RecorderTests.aCameraFileEndsWhereTheStopWasAskedThoughItsStreamStopsLate`
  fails at its first bound; it passes locally, also under 24 `yes` processes on 12 cores.
- **Why:** [KNOWN: the test code before the fix] the test read the clock
  (`asked`), then called `stop()`; the recorder takes its own reading
  when the camera file's finishing begins (`VideoFileFeed.beginFinishing`),
  and the file ends at the tick at or before that reading. The bound
  `asked + 1/30` held only while the two readings were less than a
  tick (33 ms) apart, which a loaded runner's scheduling breaks. The
  product was right: the file ended at Stop, a tick (67 ms) after the
  test's reading. [KNOWN: reproduced locally, 2026-11-26] a 100 ms
  sleep between the reading and `stop()` fails the old bound with the
  same message form, and passes the new one.
- **Fix:** the bound no longer uses a reading taken before Stop. The
  stream stops one second after the recorder asked, so the file's end
  must be `<=` the clock reading after `stop()` returns, minus 1 s;
  a file that ended with the stream or repeated its last frame for
  the wait would end after that. The test keeps the 100 ms gap.
- **Second cause:** that fix failed 3 times in 200 runs locally,
  `Expectation failed: end <= stopped - 1` with `end → 0.16666666666666666`
  and `stopped - 1 → 0.15834970800000003`. [KNOWN:
  `VideoFileTicker.finish`] the file's `end` is the time after its last
  tick (`lastWrittenTick + 1`), the end of the last frame's duration,
  and that last tick is at or before the recorder's reading, so `end`
  can be up to one tick (33 ms at 30 fps) after it. The bound failed
  whenever finalizing after the stream's 1 s took less than that. The
  recorder is right; the test's bound now adds that one tick,
  `end <= stopped - 1 + 1.0 / 30`, which a file that ended with the
  stream or repeated its last frame for the wait still breaks.
- **Verify:** `swift test --filter aCameraFileEndsWhereTheStopWasAsked
  --maximum-repetitions 200`: 3 failures in 200 before, 0 after
  (2026-11-26).
- **Observed:** 2026-11-26, Swift 6.3, Xcode 26; resolved (test).

## A camera stalls while another camera starts

- **Error:** `camera stalled: FaceTime HD Camera (the camera delivered no frame for 2 s`
- **Symptom:** in a recording's `recording.log` and `recording.json`
  (event `camera stalled`, then `camera stall ended`), a running camera
  stalls at the moment another camera starts its capture, such as after
  a screen switch or a camera plugged in; its file goes on, repeating
  its last frame. Since D91 it shows nothing to the person.
- **Why:** [KNOWN: measured on the owner's Mac, 2026-11-26, with a probe
  that opens the FaceTime HD Camera and a Logitech BRIO without file
  output and starts the BRIO's capture session again and again] in one
  process, CoreMediaIO holds a process-wide lock while a camera's
  `AVCaptureSession.startRunning` runs, so every other camera of the
  process delivers no frame for as long as that start takes: the
  FaceTime camera's longest frame gap was 821 ms to 862 ms for each
  BRIO start of 823 ms to 841 ms. With each camera in its own process,
  the same starts left gaps of 43 ms at most. A stack sample of the one
  process during a start shows CoreMediaIO's frame thread
  (`CMIOGraph::PullOutputUnits`) in `__psynch_mutexwait` for 636
  samples, beside `startRunning` itself. A start of 4 s
  [KNOWN: as observed in a recording, per the architect's brief of
  2026-11-26] passes the stall limit of 2 s and is logged as this stall.
- **Fix:** none; macOS's limit. The owner, 2026-11-26: "we can't beat
  the limitations of MacOS here." A stall has no call to action, so it
  shows no line, bounces nothing and leaves the result `ok` (D91).
  Running each camera in its own process would avoid it and was not
  chosen.
- **Verify:** the stall ends while the other camera starts: in the
  owner's recording of 2026-11-26 the FaceTime HD Camera's `camera
  stall ended` came at 24.554 s, 5.0 s after the BRIO's `camera
  connected` and 8 ms before its `camera disconnected`; the probe's
  frame gaps of 0.82 s to 0.86 s match each BRIO start's length.
- **Observed:** 2026-11-26, macOS 26, Apple silicon; open (macOS).

## The system audio is corrected by about 20 ms for good

- **Error:** in `recording.log`, `Audio 0 - System: clock drift -1000.0 ppm, corrected +12.00 ms so far, 8.17 ms off`
  about 20 to 35 s after the system audio started, then the clock drift
  near 0 ppm while the correction stays at about +20 ms; the manifest's
  `clockDriftCorrection` about 0.02 at a `clockDriftPpm` near 0.
- **Symptom:** the system audio's file is shifted by about 20 ms against
  the other sources for the whole file; seen in nearly every recording
  from 2026-11-22 to 2026-11-26, also after the system audio restarts.
- **Why:** [KNOWN: a debug run on the owner's Mac, 2026-11-26] in its
  first second the system audio's buffers arrive about 22 ms less late
  (smallest lateness about 21 ms, then about 44 ms from 1.0 s on). The
  first estimate's support line lay under that second at 1000 ppm, and
  the reference taken from it is never revised, so the 22 ms stayed in
  the correction.
- **Fix:** a source's first 2 s are not measured (D92,
  `RecorderValues.clockDriftStartSkipped`); the drift over them is the
  kept slope's.
- **Verify:** `swift test --filter aLessLateStartIsNotTakenAsDrift`
  (22 ms without the fix, under 0.5 ms with it); in a recording, the
  system audio's `clockDriftCorrection` near 0 at a drift near 0 ppm.
- **Observed:** 2026-11-26, PR #35; fixed in PR #35: the owner's
  recording of 2026-11-26 19.38.01 (build 6620fc9; undocked and docked
  again, the Logitech BRIO unplugged, the lid closed) shows the system
  audio's clock drift +38.3, then +3.7 to +8.4 ppm and its correction
  under 1 ms (-0.49 ms at +92.8 s, 0 ms after its restart at +106.3 s);
  its three system audio files' `clockDriftCorrection` are 0, -0.0007
  and 0.0002, where recordings before had about 0.02.
