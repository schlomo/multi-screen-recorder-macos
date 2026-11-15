# Operating rules

Read before any branch, review or bookkeeping action, before recording
a ruling, before asking a human to decide something, and before
watching long-running work. Branching, merging, live systems and
verifying agent output are in the principles (linked from
`AGENTS.md`); these rules add what the architect role does.

## Bookkeeping and rulings

- **Bookkeeping is milestone-batched**: the backlog and the
  architecture doc. Never during a human's review or merge windows.
- **Other sessions may have moved these files or items.** Re-read them
  from the remote (or the tracker) immediately before every write and
  before relying on them for a decision. Never write from a stale read.
- **Edit architect-maintained files with small, anchored changes**, and
  check the file's length and section boundaries before pushing. A bad
  bulk rewrite of a long file is easy to miss and expensive to undo.
- **Generated text (a description, a decision entry) is changed with
  anchored replacements**, then the changed section is re-read as
  rendered: comparing bytes proves the upload, not the content.
- **Every ruling gets a dated entry appended to the decisions log**
  (`docs/decisions.md` unless `AGENTS.md` maps it elsewhere), after
  the human's yes. Keep it lean: see the decisions log's header.
  A request that would change a principle is not a ruling; it goes
  through "Changing a principle".
- **A ruling's entry quotes the human's words** in its Context and
  marks every elaboration as the architect's reading; a brief or doc
  that restates a ruling uses its words or says it is a reading.
- **A ruling an open MR/PR applies is recorded before that change's
  review**, or quoted with its date in the description.
- **A ruling that changes how agents work is delivered only when its
  text is in a file those agents read**; its backlog entry stays open
  until then.

## Deciding and asking

- **Decide the small things; take designs to the human.** Wording,
  examples and simplifications are the architect's call: decide, and
  say what you decided. Only a design or an interface goes back for
  sign-off ("Agree the design before anyone builds it" in the
  principles); a rule is applied for what it protects, not to every
  artifact.

## Supervising long-running work

- When asked to watch long-running work (a pipeline, a test run, an
  agent), use timed checks: not busy-polling, not fire-and-forget.
- A poll ends only on a terminal state from the whole set: for a
  pipeline, every end state its host defines (such as success, failed,
  canceled and skipped); queued, preparing and waiting are not
  terminal. Send the verdict with the resume line below; an agent that
  wakes without progress is told to stand down until messaged.
- An agent that parks itself waiting on its own children is resumed
  with: **collect the results and finish; do not wait again.**
- An agent that stops with an empty or partial report: check the remote
  yourself before concluding anything. The work is often done; the
  report is what failed.
- A pipeline failure is diagnosed from the job's own log, not a
  summary. Before a new hypothesis, search the project's docs for the
  symptom and compare with the nearest working instance.

## Copilot's review

Where `AGENTS.md` records that agents mark the PRs they open ready
once fully reviewed, and the host has Copilot review drafts (D39 in
this project), the session that opened the PR does this; a delegated
agent reports instead, and never waits on Copilot itself (its brief's
completion discipline). `gh api` fills in `{owner}` and `{repo}` from
the checkout.

- Within a few minutes of `gh pr create --draft`, check that the review
  was requested:
  `gh api 'repos/{owner}/{repo}/issues/<n>/timeline' --jq '.[] | select(.event=="review_requested") | .requested_reviewer.login'`
  shows `Copilot`. If it does not, tell the human at once, and say in
  the description that Copilot did not review the PR; it is then
  marked ready on the agent's own reviews.
- Wait with a timed check ("Supervising long-running work"), up to 30
  minutes; on PR #1 and #2 of this project it took 5 to 7 minutes:
  `gh api 'repos/{owner}/{repo}/pulls/<n>/reviews' --jq '.[] | select(.user.login | test("copilot"; "i")) | .submitted_at'`.
  Past the limit, tell the human and go on as if none was requested.
- Read all of it: the summary in the `body` of that review, and the
  inline comments, which only
  `gh api 'repos/{owner}/{repo}/pulls/<n>/comments'` shows
  (`gh pr view` does not).
- Handle each comment like an adversarial review's finding, checked
  against the code: fixed, fixed differently, or deferred to the
  backlog, each with its reason in the description. The fixes get the
  delta review like any.
- Then, with no BLOCKER or SHOULD-FIX open and the pipeline green:
  `gh pr ready <n>`, and one message tells the human the PR is ready to
  merge.
- Whether marking ready starts a second review is not known yet. If
  one arrives, read it the same way; what holds then goes into a
  follow-up PR, as the human may have merged already.
