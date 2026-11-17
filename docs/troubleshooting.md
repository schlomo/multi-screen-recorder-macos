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
  refusing a counted number of times, each test asserting that its own
  drain asked that often), so none depends on a task being scheduled
  within the drain timeout. `GuideTrackFeedTests.theLastMixWaitsForSamplesThatComeLate`
  still delivers its late samples from a task after 150 ms, against a
  60 s bound: the feed's wait offers no event to deliver on, so the
  starvation pattern is left, with a bound 400 times the delay.
- **Verify:** CI's `scripts/test` passes on the pushed head.
- **Observed:** 2026-11-17, PR #19; open until CI passes.
