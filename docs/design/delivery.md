# Delivery: pipeline, versions, signing

## What this covers

How a change becomes something a person can install: the scripts, the
pipeline that wires them, version numbers, signing, and the one-time
developer setup. What the app does is in [recorder.md](recorder.md).

## The decision

**Scripts hold the behaviour; the pipeline only wires them** (thin CI).
Each script but the CI-only one runs the same on a developer's Mac and
in CI:

| Script | Does |
|---|---|
| `scripts/test` | Runs the unit tests, and the tests that run `msr` and `scripts/version` as commands |
| `scripts/version` | Prints the version of the current checkout; stops on a shallow clone |
| `scripts/build-app` | Compiles `msr` and assembles the unsigned app bundle in `build/` |
| `scripts/sign-app` | Signs the app bundle and zips it into `build/` |
| `scripts/ci-import-signing-certificate` | CI only: puts the certificate from the secret into a temporary keychain |
| `scripts/publish-snapshot-release` | Creates or replaces a PR's snapshot release |
| `scripts/remove-snapshot-release` | Removes a closed PR's snapshot release |
| `scripts/publish-release` | Publishes the release for a merge to `main` |

**Pipeline** (`.github/workflows/ci.yml`, GitHub Actions on a hosted
macOS runner for Apple silicon; free for a public repository):

| When | What runs |
|---|---|
| Every push to a PR | test, build, import the certificate, sign, publish the PR's snapshot release |
| A PR is closed | remove its snapshot release |
| A push to `main` that changes more than Markdown files | test, build, import the certificate, sign, publish a release |
| A PR from a fork or from Dependabot | test only: such a run gets no signing secret |

**Snapshot release:** one GitHub pre-release per PR, tag `pr-<number>`,
replaced on every push, titled `Snapshot PR #<n>: <version>`. A
pre-release rather than a draft, which only collaborators can see and
which has no stable download link. It is published only while the PR
is open and its head is the commit built; a run for a superseded push
or a closed PR publishes nothing and succeeds.

**Versions** (D23) count the commits on `main`, N:

| Build | Version |
|---|---|
| Release from `main` | `0.<N>.0`, tag `v0.<N>.0` |
| Snapshot of PR n | `0.<N+1>.0-pr<n>+<commit>` |
| Local build | `0.<N+1>.0-dev+<commit>` |

N grows with every commit on `main`, including Markdown-only ones that
publish nothing, so release numbers can skip but never repeat. The
bundle's short version is the numeric part; `msr version` and the About
window show the full string. 1.0 comes when the owner declares v1.

**Signing** (D5, D23, D28). `scripts/sign-app` signs with the identity
named in `SIGNING_IDENTITY` (default `Multi Screen Recorder Signing`)
and never sees a secret: `codesign` reads the key from the keychain and
matches the name as a substring of the certificate's name, so the
certificate in use, `Multi Screen Recorder Signing (Schlomo)`, is found
by the default. `SIGNING_IDENTITY=-` signs ad hoc, for a local check
only. On a developer's Mac the key is in the login keychain; in CI,
`scripts/ci-import-signing-certificate` imports the repository secret
`SIGNING_CERTIFICATE_P12` (base64 of a `.p12` exported without a
password) into a temporary keychain, the key non-extractable. It runs
after `scripts/build-app` and before `scripts/sign-app`, so no
compilation (and no code of the branch) runs while the key is in the
keychain. It is the one place that reads the secret, because macOS has
no tool that reads a certificate from the environment itself (D28). A
missing secret or identity stops with an error. The hardened runtime
is on, with the audio-input entitlement, so behaviour does not change
when Developer ID signing arrives.

**Toolchain** (D17, D28): the pipeline uses the latest Xcode and Swift
that GitHub's generally available macOS runner image offers (today
Xcode 26.6 with Swift 6.3, so the package's tools version is 6.3), not
a preview image; revisited when a newer runner image is generally
available. A developer's Mac may run a newer Xcode; the package must
still build with the runner's. Dependabot proposes updates of the
GitHub Actions and Swift packages in use.

## Developer setup, once

1. Xcode, with its licence accepted and selected:
   `sudo xcodebuild -license accept` and
   `sudo xcode-select -s /Applications/Xcode.app`. The Command Line
   Tools alone build the app but cannot run the tests.
2. The signing certificate, in Keychain Access › Certificate Assistant ›
   Create a Certificate…: a name containing `Multi Screen Recorder
   Signing`, such as `Multi Screen Recorder Signing (<your name>)`;
   identity type Self-Signed Root, certificate type Code Signing, "Let
   me override defaults" ticked, validity 3650 days (the default is one
   year, and a new certificate means granting both permissions again),
   the rest unchanged, in the login keychain.
3. For the pipeline, by the repository owner only: export the
   certificate from My Certificates as `.p12` with an empty password,
   then

   ```
   base64 -i msr-signing.p12 | gh secret set SIGNING_CERTIFICATE_P12 --repo schlomo/multi-screen-recorder-macos
   rm msr-signing.p12
   ```

## Why

- A self-signed certificate that stays the same gives every build the
  same signature, which is what lets macOS keep the two permissions
  across updates (D5); unverified until one snapshot release is
  installed over another.
- Counting commits needs no tag bookkeeping and cannot go backwards.
- Keeping the secret out of the build and sign scripts means the tested
  procedure is the shipped one, on a Mac and in CI alike.

## Accepted risk

A PR's pipeline run executes the branch's code with the signing secret
before a human has reviewed it. Accepted (D23): a self-signed
certificate matters only on Macs that granted this app its permissions.
Narrowed (D28): the key enters the keychain only after compilation, and
non-extractable; the branch's scripts still run with it.
Developer ID signing, when it comes, needs an approval step before the
signing job.

## Rejected

- **An Xcode project, XcodeGen or Tuist:** see recorder.md.
- **A draft release as the snapshot:** invisible to non-collaborators.
- **Workflow artifacts as the snapshot:** they need a GitHub login and
  expire.
- **A password on the `.p12`:** `security import` takes it only on the
  command line. If importing a password-less `.p12` fails on the
  runner, the fallback is the key and certificate as PEM.

## Open questions

None; the homepage's delivery is a separate backlog item.
