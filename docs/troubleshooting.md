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
- **Fix:** no `main.swift`; an `@main` type with
  `static func main() async` that calls
  `await CommandLineInterface.main(nil)` (`Sources/msr/EntryPoint.swift`).
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
