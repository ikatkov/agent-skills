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

`reviewDecision` carries CodeRabbit's standing answer across cycles wherever the
repository enables `reviews.request_changes_workflow`: it holds
`CHANGES_REQUESTED` while any of its comments is open and turns `APPROVED` once
they are resolved and the pre-merge checks pass.

**This skill requires no particular repository configuration.** Read which case
applies from the snapshot Section 3 already fetches, and change no setting to
suit the skill: a `reviewDecision` of `APPROVED` or `CHANGES_REQUESTED` means the
workflow is on and Section 6 gates on it. `null` with CodeRabbit reviews present
means the workflow is off, its reviews land as `COMMENTED`, and Section 6's
per-cycle rules carry the verdict alone.

**Never post `@coderabbitai approve`.** It submits an approving review on demand,
with an empty body, whatever the state of the code — so it forges the exact
signal this skill waits on. `@coderabbitai review` is the only command this skill
posts.

Human reviewers never gate the verdict, but their unresolved review threads still
block `pass`: triage every unresolved thread in Section 4 regardless of who
opened it.

## 0. Preflight: pick one transport, or stop

This skill needs `bash`, `jq`, `git`, and exactly one working **GitHub API
transport**. Probe in this order, before anything else:

```bash
for c in bash jq git; do command -v "$c" >/dev/null || echo "MISSING: $c"; done
# Transport A: gh — must work END TO END, not just auth. In a macOS command
# sandbox, `gh auth status` can pass while every API call dies on TLS
# (`x509: OSStatus …`), because Go's platform verifier needs the keychain.
gh api rate_limit >/dev/null 2>&1 && echo "TRANSPORT: gh"
# Transport B: curl + token — a complete equivalent, not a degraded fallback.
[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ] && \
  curl -fsS -H "Authorization: Bearer ${GH_TOKEN:-$GITHUB_TOKEN}" \
    https://api.github.com/rate_limit >/dev/null 2>&1 && echo "TRANSPORT: curl"
```

Pick the first transport that works and use it for **every** call in this run —
the same REST/GraphQL endpoints either way (the `gh api` commands below name the
canonical paths; in curl mode hit the same paths with the token header). Never
mix transports call-by-call within a cycle, and never downgrade to partial
substitutes.

If `bash`/`jq`/`git` is missing, or neither transport works, **stop the skill
immediately.** Report exactly what is unavailable and end the turn. A partial
review is worse than none: it produces a confident verdict from data it could
not read. Do not work around it. Specifically, never:

- install, download, or build `gh`, `jq`, or any other dependency;
- parse command output with `sed`/`awk`/`grep` because `jq` is missing;
- substitute local `git log`, the PR page's HTML, or your own reading of the diff
  for the review surfaces in Section 3;
- emit a verdict — including `needs-changes` — from an incomplete snapshot.

The stop message is the deliverable in that case. Say which tool is missing and
what the operator needs to do (install it, run `gh auth login`, export
`GH_TOKEN`, or run the skill outside the sandbox).

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

If an API call fails here — auth expired, repository not visible, network
blocked — re-run the Section 0 probe once and switch to the other transport for
the whole cycle if it passes; if neither transport works, stop as in Section 0.

## 2. Wait without model turns

Resolve `scripts/wait-for-reviews.sh` relative to this skill. Skill directories
are often symlinks into a path the command sandbox cannot read (e.g.
`~/.claude/skills/x -> ~/.agents/skills/x`); if invoking the script fails with
a permission error, copy it byte-for-byte to `$TMPDIR` with the harness file
tools (Read → Write, which are not command-sandboxed) and run the copy — same
arguments, same contract. Run it with the PR,
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

The helper selects its own transport the same way Section 0 does: `gh` when a
real API call works, otherwise curl with `GH_TOKEN`/`GITHUB_TOKEN`. In a
sandbox where only direct `gh` invocations are exempted, the helper's *nested*
`gh` calls are still confined — export the token so its curl path engages:

```bash
WATCHER=skills/review-pr/scripts/wait-for-reviews.sh
GH_TOKEN="$GH_TOKEN" "$WATCHER" \
  --owner "$OWNER" --repo "$REPO" --pr "$PR" --base "$BASE" \
  --head "$HEAD_SHA" --review-start "$REVIEW_START" \
  --commit-date "$COMMIT_DATE" \
  --interval 50 --timeout 900
```

On every cycle after the first — the wait that follows pushing fixes for
findings from an exact-HEAD review at the previous anchor — add
`--re-review-cycle`. CodeRabbit reviews incrementally and will never re-post a
review body for a fix-only push; it confirms fixes in-thread and answers a
forced re-review with "Review finished". The flag lets the waiter accept that
as the terminal state `confirmed_no_new_findings` instead of burning the whole
budget on an artifact that cannot appear.

At this decision point, enforce all of these:

- Do not call `sleep` directly; sleeping is inside the helper/Monitor.
- Do not call `true`, `date`, `echo waiting`, tail a watcher log, manually poll,
  start a second monitor, or narrate heartbeats while the helper runs.
- Keep the monitor silent. Only its terminal JSON should wake the model.
- If state is `needs_tag`, post one `@coderabbitai review` comment, then restart
  the helper once with `--tagged-coderabbit` (keep `--re-review-cycle` if it was
  set). Never retag. If you filter comments by time afterwards, derive `since=`
  from the posted tag comment's `created_at` in the API response, not from your
  own clock — CodeRabbit can reply within seconds and a self-derived window
  misses it.
- If state is `failed`, `timeout`, or `snapshot_fetch_failing`, read
  [reviewer-edge-cases.md](references/reviewer-edge-cases.md) before judging it.
- If the helper exits `2` with no JSON, a dependency is missing or both
  transports failed. Stop as in Section 0 — do not retry it and do not review
  by hand.

`ready` means waiting is complete, not that the PR passes. The final snapshot
and triage remain authoritative. `confirmed_no_new_findings` (re-review cycles
only) is likewise complete waiting: CodeRabbit engaged at the new HEAD and left
zero unresolved CodeRabbit threads. Proceed to Section 3 as with `ready`; the
acceptance rule in Section 6 says what counts as its exact-HEAD response.

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

Read bodies rather than trusting check success. CodeRabbit's own status check
reports that it ran, and `reviews.fail_commit_status` defaults to false, so that
check stays green with findings open — it carries no verdict at any point. On the
first cycle, a CodeRabbit walkthrough, a `review in progress` note, or a green
CodeRabbit check with no review body and no inline finding is engagement, not a
review. A review whose state is `APPROVED` or `CHANGES_REQUESTED` at `HEAD_SHA`
is a verdict, whatever its body length. On a re-review cycle, judge against the
acceptance rule in Section 6 instead — in-thread confirmations at the new HEAD
are the review artifact there.

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
context is pending. A ruleset lookup failure is `needs-changes` — with one
carve-out: HTTP 403 with "Upgrade to GitHub Pro or make this repository public"
means the rules feature is unavailable on this plan, so no rules can exist;
treat that as an empty ruleset (no required checks), not a failed lookup. A required
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

Push fixes, re-anchor the new HEAD, and run another deterministic wait with
`--re-review-cycle` set (Section 2). Cap at five cycles; each cycle must make a
concrete fix. Stop on repeated or non-actionable churn.

`confirmed_no_new_findings` fires on zero unresolved CodeRabbit threads, and the
approval trails the resolution that triggers it — so the wait can return while
`reviewDecision` still reads `CHANGES_REQUESTED` from the review you just
answered. With every finding fixed and the decision still standing, let it settle
through the same turn-free mechanism as Section 2, and judge afterwards. An LLM
polling loop is the wrong tool here as everywhere else in this skill.

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
- Review decision: <APPROVED/CHANGES_REQUESTED/null; null where the
  request-changes workflow is off>
- Pending required checks: <list or none; include mergeStateStatus>
- Ready-only deferred gates: <list or none>
- Verdict: <pass/needs-changes>
- Summary: <1-2 sentences>
```

Return `pass` only when CodeRabbit delivered an exact-HEAD response,
every in-scope finding is fixed, every out-of-scope one is answered and listed in
the verdict, all threads are resolved, `reviewDecision` reads `APPROVED` wherever
the request-changes workflow is enabled, and every required check is
`SUCCESS`/`SKIPPED`.

`reviewDecision` is necessary and never sufficient. Auto-approval fires once
CodeRabbit's comments are resolved, and Section 4 puts resolution in this skill's
own hands — so an agent that resolves a thread it did not fix manufactures its
own `APPROVED`, and the flag confirms only that CodeRabbit agrees with what the
skill already did. The substantive conditions above are what make the resolution
honest. Read the decision as the last check on a case built elsewhere. A PR that ships exactly what its description promised and
nothing more is the goal; declining scope creep is a `pass`, not a
`needs-changes`.

What counts as CodeRabbit's exact-HEAD response depends on the cycle:

- **Cycle 1:** a substantive response at `HEAD_SHA`, which is any one of a
  nonzero-body review, inline findings, or a review carrying the state
  `APPROVED` or `CHANGES_REQUESTED` on that exact commit. The state counts on
  its own because CodeRabbit approves with an empty body when it has nothing to
  say, which is the shape of every clean review — waiting for prose that will
  never arrive burns the whole budget on a verdict already given. "No new
  commits to review" on a never-reviewed PR stays a failure.
- **Cycle N>1** (fixes pushed for findings from an exact-HEAD review at the
  previous anchor): CodeRabbit does not re-review commits it already processed
  incrementally, so accept any one of:
  - a nonzero-body review at the new HEAD (what it posts when the push contains
    substantive new code);
  - confirmation replies in the fixed threads whose wrapper reviews carry the
    new HEAD's `commit_id`, with zero CodeRabbit threads left unresolved;
  - a forced `@coderabbitai review` returning "Review finished" with no new
    findings.

`pass` means reviewed and ready to merge — nothing about whether the change
merges, builds, deploys, or works live. Never merge from this skill; hand back to
the operator.

Return `needs-changes` for an unresolved finding/thread, a failed or pending
required check, an engaged-but-incomplete CodeRabbit review, CodeRabbit being
unavailable (quota/rate limit), or `snapshot_fetch_failing`. When the *only*
remaining blocker is a still-in-progress CodeRabbit review or a
pending-not-failed required check with nothing actionable left, route through 5a
(re-arm) instead of dead-ending on this verdict.
