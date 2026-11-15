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

## Format

```markdown
## <short title>

- **Error:** `<the exact error text, verbatim>`
- **Symptom:** what is seen, and where (command, job, log).
- **Why:** the root cause, with its evidence label.
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
  display's HiDPI (backing scale) mode was switched, with a popup menu
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
- **Verify:** switch a display's HiDPI mode with the start window open;
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
