---
name: review-pr
description: "Run an exact-HEAD GitHub PR review loop: trigger CodeRabbit if it is missing, wait without LLM polling, collect every review surface and unresolved thread, fix the findings that fall inside the PR's stated scope, decline the ones that don't, verify required checks, and return a machine-readable verdict. Use for bot-review requests, review cleanup, or GitHub review handling on the current branch PR."
---

# Review PR

Review the current PR's exact HEAD, fix the findings that belong to it, and
return a machine-readable verdict. Two rules run through the whole loop: keep
polling deterministic — never spend model turns waiting for external state — and
keep the diff inside the scope the PR description already claims.

This skill takes no flags. Its only input is the PR on the current branch (or a
PR number the caller names).

## Review gate

**CodeRabbit (`coderabbitai[bot]`) is the only gating reviewer.** It runs on
push; the fallback trigger is a `@coderabbitai review` comment. The verdict waits
on CodeRabbit and on the ruleset-required status checks — nothing else.

Human reviewers never gate the verdict, but their unresolved review threads still
block `pass`: triage every unresolved thread in Section 4 regardless of who
opened it.

## 1. Anchor one cycle

Resolve the current branch PR with `gh pr view --json number,headRefOid`. With no
PR on the branch, stop and tell the user to open one; this skill never creates a
PR.

Refuse a dirty tree before reviewing. Push, then require PR `headRefOid` to equal
local HEAD. Record:

- `HEAD_SHA` and its short form.
- `REVIEW_START` in `Z` UTC.
- `COMMIT_DATE` from
  `gh api repos/$OWNER/$REPO/commits/$HEAD_SHA --jq .commit.committer.date`.
- The `git status --porcelain` baseline for later fix ownership.
- `SCOPE`: the PR title and body from `gh pr view --json title,body`, plus the
  changed-file list from `gh pr diff --name-only`. This is the scope contract for
  Section 4.

Use the API committer date; local `git log` can preserve a non-UTC zone. A
finding belongs to this cycle when its `commit_id` is `HEAD_SHA`, its timestamp
is at or after either anchor, or its body cites the full/short SHA.

If `gh` auth fails and GitHub app tools are available, use their PR, review,
comment, reply, and resolve-thread operations; retain the same exact-HEAD and
three-surface rules.

## 2. Wait without model turns

Resolve `scripts/wait-for-reviews.sh` relative to this skill. Run it with the PR,
HEAD, anchors, and base branch. It silently checks CodeRabbit's artifacts and the
ruleset-required status checks, preserves the last good snapshot, and emits one
terminal JSON object.
Use its `--once` mode only for a read-only diagnostic probe or validation, not
for the normal bounded wait.

On Claude Code, invoke the helper through **one main-session `Monitor` call**
with `timeout_ms` slightly above the helper's 900-second budget. Do not delegate
to an `Agent` subagent. After `Monitor started`, end the assistant turn; the task
notification resumes the main session.

On another harness, run the helper in one long-lived execution and use that
harness's process-wait primitive. Never implement an LLM polling loop.

```bash
WATCHER=skills/review-pr/scripts/wait-for-reviews.sh
"$WATCHER" \
  --owner "$OWNER" --repo "$REPO" --pr "$PR" --base "$BASE" \
  --head "$HEAD_SHA" --review-start "$REVIEW_START" \
  --commit-date "$COMMIT_DATE" \
  --interval 50 --timeout 900
```

At this decision point, enforce all of these:

- Do not call `sleep` directly; sleeping is inside the helper/Monitor.
- Do not call `true`, `date`, `echo waiting`, tail a watcher log, manually poll,
  start a second monitor, or narrate heartbeats while the helper runs.
- Keep the monitor silent. Only its terminal JSON should wake the model.
- If state is `needs_tag`, post one `@coderabbitai review` comment, then restart
  the helper once with `--tagged-coderabbit`. Never retag.
- If state is `failed`, `timeout`, or `snapshot_fetch_failing`, read
  [reviewer-edge-cases.md](references/reviewer-edge-cases.md) before judging it.

`ready` means waiting is complete, not that the PR passes. The final snapshot
and triage remain authoritative.

## 3. Fetch one final snapshot

After the waiter stops, fetch the full bodies once from all three REST surfaces:

```bash
{ gh api --paginate repos/$OWNER/$REPO/issues/$PR/comments --jq '.[] | {surface:"issue",login:.user.login,id,ts:.created_at,commit:"",path:null,line:null,url:.html_url,body}'
  gh api --paginate repos/$OWNER/$REPO/pulls/$PR/reviews --jq '.[] | {surface:"review",login:.user.login,id,ts:.submitted_at,commit:.commit_id,path:null,line:null,url:.html_url,body}'
  gh api --paginate repos/$OWNER/$REPO/pulls/$PR/comments --jq '.[] | {surface:"inline",login:.user.login,id,ts:.created_at,commit:(.original_commit_id // .commit_id),path,line,url:.html_url,body}'
} | jq -s 'sort_by(.ts // "")'
```

If the issue-comments REST call fails, fetch the same full top-level comment
bodies through the paginated GraphQL pull-request `comments` connection. A
successful equivalent fallback is a valid surface; an empty response caused by
a failed command is not.

REST review payloads have no `severity` field. Read CodeRabbit's severity label
from its body. Only inline findings carry `path:line`. Scope inline findings with
`original_commit_id`; GitHub may rewrite `commit_id` as the diff moves, which can
make stale feedback look current.

Fetch every unresolved thread, whoever opened it. Keep the thread node ID for
resolution and `fullDatabaseId` for replies:

```bash
gh api graphql --paginate -f query='
  query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
    repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
      reviewThreads(first:100,after:$endCursor){
        nodes{id isResolved isOutdated path line
          comments(first:50){nodes{fullDatabaseId body createdAt url author{login}}}}
        pageInfo{hasNextPage endCursor}}}}}
' -f owner=$OWNER -f repo=$REPO -F pr=$PR \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)'
```

Also fetch the base ruleset and
`gh pr view --json isDraft,mergeStateStatus,mergeable,reviewDecision,statusCheckRollup`.
A failed snapshot or ruleset lookup fails closed; never interpret an empty
payload as clean.

Read bodies rather than trusting check success. A CodeRabbit walkthrough, a
`review in progress` note, or a green CodeRabbit check with no review body and no
inline finding is engagement, not a review.

## 4. Triage against the scope contract, then fix

Dedupe by thread/URL. If an inline finding is an unresolved thread, handle it
once as the thread.

Classify every finding against `SCOPE` **before** deciding how to answer it. A
finding is in scope only when it is one of:

- a defect in the diff — the code this PR added or changed is wrong, unsafe, or
  breaks a caller;
- a gap the PR description itself promises to close;
- a required-check failure this PR causes.

Everything else is out of scope, however reasonable it sounds: adjacent
pre-existing bugs, refactors of code the PR merely touched, new abstractions,
extra features, wider test coverage than the change needs, renames, and
style rewrites beyond the changed lines. Reviewers and bots suggest these
constantly. **Do not implement them in this PR.** Reply with one sentence naming
the reason (out of scope for this PR), then resolve. Carry every declined finding
into the Section 6 verdict so the user sees what was turned down and can decide
whether it deserves its own PR.

When a finding's scope is genuinely unclear, or a reviewer argues the PR's
approach is architecturally wrong, read `docs/architecture/INTENT.md` and
`docs/architecture/adr/*` before answering. If a recorded decision already
settles it, reply citing that document by path and decline the change. If those
files do not settle it, ask the user — never widen the diff to end an argument.

Then, for the findings that survive triage:

- Fix in-scope bugs, correctness/security issues, and CodeRabbit
  `⚠️`/`🔴`/`🟠` at the root. Still triage low-severity findings even when the
  overall verdict says the patch is correct.
- Apply cheap, correct CodeRabbit `🧹`/`🔵` suggestions that land inside the
  changed lines; otherwise explain the skip. Ignore `🤖 Prompt for AI Agents` and
  `🧩 Analysis` scaffolding.
- Ask the user on a design judgment call. Reply to a false positive with
  evidence.
- For consistency findings, trace the real resolver and make both paths read the
  same runtime source; symmetric-looking code is not enough.

Never edit a file outside the PR's changed-file list to satisfy a finding. If a
correct fix genuinely requires touching a new file, say so and get the user's
agreement first — that is a scope change, not a review fix.

Always reply before resolving. Resolve only a finding you fixed or explicitly
declined as out of scope; anything still open or awaiting the user stays
unresolved. Reply inline through
`pulls/$PR/comments/{id}/replies`, top-level through `issues/$PR/comments`, and
resolve with:

```bash
gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' -f t=$THREAD_ID
```

For an outdated thread, reply and resolve only when the current diff already
covers it; otherwise leave it unresolved and tell the user.

## 5. Verify, push, and repeat

Every ruleset-required check must be `SUCCESS`/`SKIPPED`; a missing required
context is pending. A ruleset lookup failure is `needs-changes`. A required
`pull_request` approval gate only evaluates once the PR is ready for review; on a
draft PR report it as deferred instead of waiting for it.
`BLOCKED`/`DIRTY`/`UNKNOWN` blocks unless only that ready-only gate remains with
zero pending checks and unresolved threads.

Commit only files introduced relative to the cycle baseline. Stop if unrelated
edits appear. Before pushing, diff the new changed-file list against the `SCOPE`
list from Section 1: a file that review fixes added to the PR is a scope change
the user has not seen — stop and confirm it. Run the repo's own
lint/format/typecheck entry point on the changed files — read `CONTRIBUTING.md`,
`AGENTS.md`, `CLAUDE.md`, or the package/Makefile scripts to find it rather than
guessing a command.

If the accepted fixes made the PR description inaccurate, update the description
to match what the PR now does. Never let the diff drift ahead of its stated
scope.

Push fixes, re-anchor the new HEAD, and run another deterministic wait. Cap at
five cycles; each cycle must make a concrete fix. Stop on repeated or
non-actionable churn.

## 5a. Re-arm on only-waiting, don't dead-end a pending PR

Before returning `needs-changes`, check whether the *only* blocker is external
progress — CodeRabbit still in-progress, or a required check still
pending-not-failed — with zero actionable findings/threads, zero failed checks,
and zero pending local fixes. Any actionable finding or failed check returns
`needs-changes` immediately; never mask a real problem behind "still waiting".

On that only-waiting state, re-arm instead of stopping, so the operator never
re-runs the helper by hand:

- **Claude Code / dynamic-loop harness:** schedule a self-paced wake-up
  (`ScheduleWakeup`, dynamic-mode loop) with a long fallback interval (~20–30
  min) re-arming this skill for the same PR, then end the turn. Idle must cost
  nothing — no assistant turns between wakes, never a short busy poll. This
  re-arm is **outer only**: never wrap the Section 2 turn-free watcher wait in a
  recurring loop.
- **Each wake:** re-resolve the PR HEAD and re-run Section 1 exact-HEAD
  anchoring before judging — a human may have pushed between wakes — then
  re-enter from Section 2.
- **Always terminate.** Stop on a real verdict (`pass` or real `needs-changes`),
  on operator interrupt, or after a few consecutive wakes with no reviewer/check
  movement — then return the last `needs-changes` (still waiting). Never re-arm
  forever.
- **Other harness with no self-paced-loop primitive:** emit `needs-changes`
  (still waiting) and tell the operator to re-arm with
  `/loop /review-pr <PR#>` (dynamic mode, long fallback).

## 6. Return the verdict

```text
GITHUB_REVIEW_RESULT:
- PR: <url or number>
- CodeRabbit: <responded/in-progress/unavailable/failed; reason>
- Review cycles: <count>
- Issues found / fixed in scope / declined out of scope: <n> / <n> / <n>
- Declined as out of scope: <one line each: finding, thread URL, reason; or none>
- Files added to the PR by review fixes: <list or none>
- Unresolved actionable threads: <count>
- Pending required checks: <list or none; include mergeStateStatus>
- Ready-only deferred gates: <list or none>
- Verdict: <pass/needs-changes>
- Summary: <1-2 sentences>
```

Return `pass` only when CodeRabbit delivered a substantive exact-HEAD review,
every in-scope finding is fixed, every out-of-scope one is answered and listed in
the verdict, all threads are resolved, and every required check is
`SUCCESS`/`SKIPPED`. A PR that ships exactly what its description promised and
nothing more is the goal; declining scope creep is a `pass`, not a
`needs-changes`.

`pass` means reviewed and ready to merge — nothing about whether the change
merges, builds, deploys, or works live. Never merge from this skill; hand back to
the operator.

Return `needs-changes` for an unresolved finding/thread, a failed or pending
required check, an engaged-but-incomplete CodeRabbit review, CodeRabbit being
unavailable (quota/rate limit), or `snapshot_fetch_failing`. When the *only*
remaining blocker is a still-in-progress CodeRabbit review or a
pending-not-failed required check with nothing actionable left, route through 5a
(re-arm) instead of dead-ending on this verdict.
