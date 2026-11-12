# Delivery: pipeline, versions, signing

## What this covers

How a change becomes something a person can install: the scripts, the
pipeline that wires them, version numbers, signing, and the one-time
developer setup. What the app does is in [recorder.md](recorder.md).

## The decision

**Scripts hold the behaviour; the pipeline only wires them** (thin CI).
Each runs the same on a developer's Mac and in CI:

| Script | Does |
|---|---|
| `scripts/test` | Runs the unit tests |
| `scripts/version` | Prints the version of the current checkout |
| `scripts/build-app` | Builds, bundles, signs and zips the app into `build/` |
| `scripts/ci-import-signing-certificate` | CI only: puts the certificate from the secret into a temporary keychain |
| `scripts/publish-snapshot-release` | Creates or replaces a PR's snapshot release |
| `scripts/remove-snapshot-release` | Removes a closed PR's snapshot release |
| `scripts/publish-release` | Publishes the release for a merge to `main` |

**Pipeline** (`.github/workflows/ci.yml`, GitHub Actions on a hosted
macOS runner for Apple silicon; free for a public repository):

| When | What runs |
|---|---|
| Every push to a PR | test, build, sign, publish the PR's snapshot release |
| A PR is closed | remove its snapshot release |
| A push to `main` that changes more than Markdown files | test, build, sign, publish a release |
| A PR from a fork or from Dependabot | test only: such a run gets no signing secret |

**Snapshot release:** one GitHub pre-release per PR, tag `pr-<number>`,
replaced on every push, titled `Snapshot PR #<n>: <version>`. A
pre-release rather than a draft, which only collaborators can see and
which has no stable download link.

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

**Signing** (D5, D23). `scripts/build-app` signs with the identity
named in `SIGNING_IDENTITY` (default `Multi Screen Recorder Signing`)
and never sees a secret: `codesign` reads the key from the keychain. On
a developer's Mac that is the login keychain; in CI,
`scripts/ci-import-signing-certificate` first imports the repository
secret `SIGNING_CERTIFICATE_P12` (base64 of a `.p12` exported without a
password) into a temporary keychain. A missing secret or identity stops
the build with an error. The hardened runtime is on, with the
audio-input entitlement, so behaviour does not change when Developer ID
signing arrives.

**Toolchain** (D17): the latest released Swift and Xcode, upgraded
soon after each release. Dependabot proposes updates of the GitHub
Actions and Swift packages in use.

## Developer setup, once

1. Xcode, with its licence accepted and selected:
   `sudo xcodebuild -license accept` and
   `sudo xcode-select -s /Applications/Xcode.app`. The Command Line
   Tools alone build the app but cannot run the tests.
2. The signing certificate, in Keychain Access › Certificate Assistant ›
   Create a Certificate…: name `Multi Screen Recorder Signing`, identity
   type Self-Signed Root, certificate type Code Signing, "Let me
   override defaults" ticked, validity 3650 days (the default is one
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
- Keeping the secret out of the build script means the tested
  procedure is the shipped one, on a Mac and in CI alike.

## Accepted risk

A PR's pipeline run executes the branch's code with the signing secret
before a human has reviewed it. Accepted (D23): a self-signed
certificate matters only on Macs that granted this app its permissions.
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
