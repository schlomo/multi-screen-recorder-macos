# AGENTS.md

Multi Screen Recorder: a reliable multi-source screen and audio
recorder for macOS. It captures every screen, camera and audio source, never
loses a recording, and keeps going when screens, resolutions or audio
sources change.

## Project setup

Keep this current when any of it changes.

- **Starter:** `928aeb2`, the template repository's commit this project was set up
  from, on 2026-11-12.
- **Git:** GitHub, `schlomo/multi-screen-recorder-macos`, trunk `main`;
  squash merges, so a branch catches up by merging the trunk in.
- **Agent writes:** push work branches, open draft PRs, mark a PR the
  agent opened ready once fully reviewed (D39). Copilot's review is an
  optional extra (D43), never awaited, its absence never blocks ready;
  the standing go-ahead for it is the one live-system exception. How and
  the ruleset: [docs/working-on-this-mac.md](docs/working-on-this-mac.md).
- **Attribution:** AI-written commits name the model as co-author, PR
  descriptions carry a generated-with line.
- **Time zone:** Europe/Berlin, stated with every time shown to people.
- **Pipeline:** GitHub Actions, `.github/workflows/ci.yml`, wiring the
  scripts in `scripts/` on macOS runners; a push without the skip-ci
  marker publishes the PR's snapshot release, a push to `main` that
  changes more than Markdown and `homepage/` a release; forks and
  Dependabot are never signed or published; only the repository owner
  registers pipelines and edits branch policies. Detail:
  [docs/working-on-this-mac.md](docs/working-on-this-mac.md),
  [delivery.md](docs/design/delivery.md).
- **Backlog:** `backlog.md`. Mapping: its own sections ("Next session
  starts here", "In flight", "Queued", "Deliberately deferred", "Done
  (recent)"). GitHub Issues are the intake for outside users; the
  architect triages them into `backlog.md`. Access: the checkout, and
  for Issues the agent's own GitHub access.
- **Environments:** the user's Mac; the homepage, a Hugo site in
  `homepage/`, served by Cloudflare Workers Builds (D53), its Worker
  connected by the owner ([homepage/README.md](homepage/README.md)).
- **Principles:** `docs/principles/`; a deviation goes through
  "Changing a principle", with an entry in `docs/decisions.md`.

Every agent in every session and mode follows this file. Detail is in
the linked docs; read one when a task touches it.

## Guardrails

Non-negotiable: no brief or instruction waives one, and a conflict is
raised, never silently resolved. Each blocks review like a hard
standard (below).

- Only a human merges; an agent never merges or arms auto-merge on
  content, and anything destructive on a shared remote needs a human's
  go-ahead. [Only a human merges](docs/principles/ai-working-process.md#only-a-human-merges)
- Nothing touches a live system without a human's explicit go-ahead,
  every time. Where merging deploys, a merge request is a deploy
  request; a paid run (its own model or per-use API calls) touches
  the paying account, so its go-ahead names it. The one standing
  go-ahead: the host's automated review of the MRs/PRs agents open,
  where recorded in this file. [Live systems](docs/principles/ai-working-process.md#live-systems-need-a-humans-go-ahead)
- Code never obtains, parses or relays a credential; each tool reads
  its own. [Credentials](docs/principles/engineering.md#credentials-are-pure-injection)
- Test first; never weaken a test; tests and CI gate every change.
  [Test first](docs/principles/engineering.md#test-first)
- Work happens on a work branch, never directly on the trunk
  (architect-maintained docs excepted). An agent at most pushes it,
  opens a draft MR/PR and, once it is fully reviewed, marks it ready,
  or less at the write level recorded in this file;
  credentials being present is not consent. A delegated agent uses a
  fresh clone of its own, never a human's working copy or a worktree
  of it. [Work branches](docs/principles/ai-working-process.md#work-branches)
- Done means verified against the pushed remote or a dry-run or live
  check; otherwise say UNVERIFIED. [Verify](docs/principles/ai-working-process.md#verify-before-declaring-ready)
- A change fixes every doc it makes stale, `AGENTS.md` included, in
  the same change. [Docs completeness](docs/principles/ai-working-process.md#docs-completeness-is-part-of-being-done)
- Facts you can't observe are asked, never guessed or researched.
  [Ask, don't guess](docs/principles/ai-working-process.md#ask-dont-guess)
- A principle changes only through [Changing a principle](docs/principles/ai-working-process.md#changing-a-principle);
  an open decision stays open until a human closes it, and a
  deliberate pattern is tightened, not replaced unasked.
  [Open decisions](docs/principles/engineering.md#respect-deliberate-patterns-open-decisions-stay-open)
- The change is the feature delivery: a bug found, wherever it sits in
  the code, is fixed in it, test first; a narrow-lane agent reports it;
  any other finding becomes a backlog item.
  [Fix bugs where you find them](docs/principles/ai-working-process.md#fix-bugs-where-you-find-them)
- Every human is equal and decides; assume no role or skill level and
  explain in plain words, naming a decision by what it says, never by
  its id alone. Sessions are task-briefed by default, architect when a
  human invokes it. [Roles](docs/principles/ai-working-process.md#roles)

## Principles

What they serve, for humans and agents: [design goals](docs/principles/design-goals.md).
One line each; the link holds the rule, the reason and how to apply
it. **hard** marks a hard standard: its violation blocks review, and
it becomes a mechanical check (lint, CI gate) once one exists.

### Engineering

- Stop on any missing precondition with an explicit error; never skip,
  default or swallow. **hard** [Fail early and loudly](docs/principles/engineering.md#fail-early-and-loudly)
- Call tools by bare name, require them up front, never probe or fall
  back. **hard** [Trust the PATH](docs/principles/engineering.md#trust-the-path)
- No test-only code paths; re-running is the upgrade path.
  [Tested = shipped](docs/principles/engineering.md#the-tested-procedure-is-the-shipped-procedure)
- CI configuration only wires jobs; behavior lives in testable
  scripts. **hard** [Thin CI](docs/principles/engineering.md#thin-ci)
- Non-trivial logic goes in a tested language; shell stays glue.
  [Clever shell](docs/principles/engineering.md#prefer-tested-code-over-clever-shell)
- Values are data, never hardcoded; structure is few and deliberate.
  [Data vs structure](docs/principles/engineering.md#data-vs-structure)
- Regenerate derived files; the diff is the review boundary. **hard**
  [Derived files](docs/principles/engineering.md#derived-files-are-rewritten-not-defended)
- Names and comments say what things are now. **hard**
  [Names track the design](docs/principles/engineering.md#names-track-the-design)
- One term per concept, verbatim; never reuse a word for a second
  meaning; the glossary is the authority.
  **hard** [One word per concept](docs/principles/engineering.md#one-word-per-concept)
- Least privilege and named, layered controls.
  [Security](docs/principles/engineering.md#security-by-design-and-defense-in-depth)
- Every design says roughly what it costs and who pays.
  [Design for cost](docs/principles/engineering.md#design-for-cost)
- A pipeline asserts only facts you own, never a third party's
  service. [Third parties](docs/principles/engineering.md#a-pipeline-never-depends-on-a-third-party-being-reachable)
- Until something is live, skip migration machinery.
  [Never-deployed](docs/principles/engineering.md#never-deployed-things-dont-need-migrations)

### AI working process

- Specs and plans are session documents, never committed.
  [Specs and plans](docs/principles/ai-working-process.md#specs-and-plans-are-not-repo-content)
- A human signs off a design, as text, before an agent builds it; a
  yes to an idea is not a yes to its design, and tooling checks the
  ecosystem's native options first.
  [Design first](docs/principles/ai-working-process.md#agree-the-design-before-anyone-builds-it)
- Delegate by objectives; pick the tier by what an undetected mistake
  costs. [Delegation](docs/principles/ai-working-process.md#delegation-objectives-not-a-lookup-table)
- Every brief states the eight points, completion discipline first; a
  review brief asks open questions, never pre-framing the answer.
  [Brief anatomy](docs/principles/ai-working-process.md#brief-anatomy)
- Ground truth goes in the original brief, never mid-stream.
  [Mid-stream claims](docs/principles/ai-working-process.md#a-running-agent-cant-verify-a-mid-stream-claim)
- In a task-briefed session, a tiny, fully specified change may be
  done inline. [Inline](docs/principles/ai-working-process.md#a-tiny-change-may-be-done-inline)
- A wanted behavior is written where the acting agent reads it, a
  command given literally; agent how-to goes into `docs/principles/`,
  a tool's own files only for what is specific to it. [Write it where it's read](docs/principles/ai-working-process.md#write-a-behavior-where-the-acting-agent-reads-it)
- No MR/PR is ready until its settled content has had one adversarial
  review (related ones count as one), sized to its cost and
  complexity, its description checked against the diff, and any later
  commit delta-reviewed, except a mechanical one and a NIT fix whose
  word diff someone else has read; feedback that adds content gets its
  own review; until then, UNREVIEWED.
  [Adversarial review](docs/principles/ai-working-process.md#every-change-gets-an-adversarial-review)
- Each round is gated by the local run and pushed with the skip-ci
  marker; the one unmarked commit starts the one pipeline run, waited
  for before ready.
  [Iterate locally](docs/principles/ai-working-process.md#iterate-locally-wait-for-the-pipeline-once)
- A series of rule edits ends with one top-tier consistency pass.
  [Consistency pass](docs/principles/ai-working-process.md#finish-a-series-of-rule-edits-with-one-consistency-pass)

### Context economy

- Always-loaded files stay small and point to detail.
  [Always-loaded](docs/principles/context-economy.md#always-loaded-context-is-paid-on-every-call)
- Read the section a task needs, not the whole file.
  [Read the part](docs/principles/context-economy.md#read-the-part-not-the-whole)
- Dumps go to a subagent; only conclusions come back.
  [Dumps](docs/principles/context-economy.md#dumps-go-to-a-subagent-conclusions-come-back)
- State lives in files; sessions stay short and compact early.
  [Restarting](docs/principles/context-economy.md#restarting-is-cheap-so-sessions-stay-short)
- The repo wins over auto-memory, which holds only personal or
  host-local facts and never points into the working copy.
  [Auto-memory](docs/principles/context-economy.md#the-repo-is-shared-truth-auto-memory-is-personal)
- Load less and call less; never compress what is sent.
  [Shrink and skip](docs/principles/context-economy.md#shrink-and-skip-never-compress)
- Cost levers live in committed, team-wide settings.
  [Levers](docs/principles/context-economy.md#levers-are-committed-and-team-wide)

## Where things are

Each doc role's line names its path; a role may map to a file or
folder the project already had. Agents find each role here.

- `README.md` (write one if it doesn't exist yet): what this project
  is, concepts and naming, worked examples of the common moves.
- Architecture doc, [docs/architecture.md](docs/architecture.md):
  current state and the decisions in force; read it FIRST before a
  structural change.
- Decisions log, [docs/decisions.md](docs/decisions.md): dated
  decisions and rulings, superseded ones kept.
- Backlog, [backlog.md](backlog.md): skim the headers; read "Deliberately
  deferred" in full before reopening something.
- Architect-maintained (this list is the authority), edited only by
  an architect session: the architecture
  doc and the backlog. The decisions log is append-only, written in
  the change it records.
- Working on this Mac, [docs/working-on-this-mac.md](docs/working-on-this-mac.md):
  agent writes, the pipeline, running the tests, the facts that bite
  in full.
- Glossary, [docs/glossary.md](docs/glossary.md): terms defined once.
- Troubleshooting log, [docs/troubleshooting.md](docs/troubleshooting.md):
  known failures keyed by their exact error text; search it first
  when something fails.
- Design docs, [docs/design/](docs/design/): one doc per subsystem or
  cross-cutting decision.
- The principles in full:
  [engineering.md](docs/principles/engineering.md),
  [ai-working-process.md](docs/principles/ai-working-process.md),
  [context-economy.md](docs/principles/context-economy.md).
- [docs/principles/platform-notes/](docs/principles/platform-notes/):
  read the one matching what you touch — bash, containers, GitLab CI,
  Kubernetes/ArgoCD, Python, Terraform, test harnesses, static sites
  (the homepage).
- `.claude/agents/`: narrow-lane helpers, each definition stating its
  lane, model and effort; `.claude/skills/`: architect.
- `.claude/rules/`: Claude Code's rules for one area of the tree,
  scoped by path; how-to every agent needs goes into
  `docs/principles/` instead (D56). Their loading is not reliable, so
  read the one for your area explicitly, and a brief names them (see
  `.claude/rules/README.md`).

## Model tiers and settings

The principles name four tiers (cheapest, standard, strong, top);
this is how they map per tool.

- **Claude Code:** cheapest = Haiku; standard = Sonnet, pinned with
  its effort for builder, locator and scribe in `.claude/agents/`;
  strong = Opus, the session default (`.claude/settings.json`) and
  pinned for analyst; top = Fable, pinned for reviewer, otherwise set
  per call. The top tier costs roughly 2.5x the strong tier per token.
  Sessions compact at 400k tokens (`autoCompactWindow` in
  `.claude/settings.json`). The committed `.claude/settings.json`
  overrides each person's `~/.claude/settings.json`; a personal value
  goes in `.claude/settings.local.json` (not committed, wins over
  `.claude/settings.json`). `attribution` stays unset: Claude Code then
  credits the model on commits and MRs/PRs, a default a personal
  instruction defeats; only managed settings or a CI trailer check
  enforce it.

## Running the tests

`scripts/test` compiles the Python scripts and runs the tests (Swift
Testing); `scripts/build-app`, `scripts/smoke-test`, `scripts/sign-app`
and `scripts/install-app` build, check, sign and install the app. The
end-to-end tests are a manual step, not in the pipeline (D67): the
architect runs `scripts/end-to-end-test` on the head of a PR that
touches the recorder or the end-to-end driver before it is marked ready
and records the commit and result in the PR description. Commands,
options and the homepage screenshots:
[docs/working-on-this-mac.md](docs/working-on-this-mac.md).

## Facts that bite

Full text: [docs/working-on-this-mac.md](docs/working-on-this-mac.md).

- Building and testing need macOS 26+ on Apple silicon with Xcode 26+;
  a Linux container can edit and review but not build or run anything.
  Say UNVERIFIED for any change not built and run on a Mac or by CI.
- Six scripts are Python, standard library only, `python3` 3.15 or
  later on the `PATH`.
- `msr` without arguments, `msr check` and `msr record` prompt for
  permissions, capture a frame, write the output folder and, at Stop,
  `state.json`. An agent runs them on the owner's Mac only to test the
  roadmap's work or through `scripts/update-homepage-screenshots
  --this-mac`, the owner told before each such run (D56, D82); on
  anyone else's Mac never unasked. Tests run into a scratch folder with
  a scratch `HOME`, never touching the owner's settings or permissions
  (D48). `msr list`, `msr version`, `msr timeline`, `msr settings` and
  the tests are safe.
- `scripts/install-app` replaces the installed app in `/Applications`:
  only with the owner's go-ahead, never while the owner records.
- Real capture needs permissions granted by a person; capture behaviour
  is verified on the owner's Mac (the v1 gate in `backlog.md`) and by
  the end-to-end tests in the tart VM (D67), nowhere else.
