# Reviewer edge cases

Read this reference only when the waiter returns `failed`, `timeout`, or
`snapshot_fetch_failing`, or when a green CodeRabbit check has no substantive
review artifact.

## CodeRabbit

- `review in progress` or `No new commits to review` is engagement, not a
  substantive review. This holds on every cycle, first or later.
- **The walkthrough comment is where a clean review lives.** It carries the
  `summarize by coderabbit.ai` marker, so the chatter filter used to discard it
  wholesale — but when a review finds nothing, CodeRabbit posts no review object
  and no inline comment, and edits `No actionable comments were generated in the
  recent review` into that comment instead. Measured across 30 pull requests on
  one repository: 10 carried that sentence, and in all 10 it sat in the same
  comment as the reviewed range, whose end matched the pull request head in
  every spot check. Accepted only with both halves present on one comment.
  This placement is CodeRabbit's documented behaviour, not an accident to be
  tidied away later — see "Why did CodeRabbit not leave any review comments on
  my pull request" in their knowledge base, which states the confirmation
  appears below the Walkthrough section. There is no documented API, webhook or
  check-run equivalent; reading the comment is the supported route.
- The walkthrough is **mutable** — rewritten in place on each review — so anchor
  on the *end* of `between <base> and <head>`, never on the SHA appearing
  anywhere in the body. A range reading `between A and B` while the loop is
  anchored at `A` reports a review of `B`, not of `A`.
- The same comment carries the two non-verdicts as well, and **both are
  terminal** — waiting past either only spends the budget:
  - `Review failed`, with its own `failure by coderabbit.ai` marker and the
    cause below it (most often "The pull request is closed"). Classified
    `failed`, which ends the wait but never passes: the commit is unreviewed.
  - `Review limit reached`, carrying `Next review available in: <n> <unit>`.
    Classified `unavailable`, and the delay is parsed into
    `coderabbit_retry_after` (seconds). Observed 6 seconds, 15, 18, 33 and 42
    minutes across five pull requests — re-arm on the published number, never a
    fixed interval.
- The rate-limit notice names the account whose quota ran out, and the quota is
  **per developer**: observed charged to both the repository owner and to
  `github-actions[bot]`, depending on which identity pushed. A loop running as a
  bot therefore exhausts a different allowance than the human. Pro is 5 PR
  reviews an hour and Pro+ is 10, on a rolling window, with additional spacing
  above the 95th percentile of recent activity — so a five-cycle loop can consume
  half a Pro+ hour by itself, and its later cycles are the ones that get spaced
  out. `@coderabbitai rate limit` reports the remaining allowance without
  consuming a review, which is the cheap way for a human to check.
- **A review takes minutes.** `auto_incremental_review` defaults to on, so
  automatic review picks up each push without being asked; measured latency on
  one repository ran 100–440 seconds from push to the review artifact, on fix
  commits as well as first ones. Every delay in the waiter must sit above that
  band. A command posted inside the window interrupts the review it was meant to
  provoke, and what comes back is an acknowledgement mistakable for a verdict.
- **`@coderabbitai review` is itself incremental** and no-ops while automatic
  review is un-paused — it answers `Review finished` within seconds, over a note
  saying it "does not re-review already reviewed commits" and applies "only when
  automatic reviews are paused". `@coderabbitai full review` is the command that
  reassesses from scratch and is the only one that produces an artifact on
  demand. Reach for it only once the wait has genuinely run dry.
- **Silence can be the whole answer.** A clean incremental review emits no
  review, no inline comment and no state — check the walkthrough comment above
  before calling it silent, because that is where the verdict usually is. Where
  even that is missing there is nothing to wait for, which is what the
  `needs_full_review` escalation exists for. If that still yields nothing, the
  commit went unreviewed and the verdict says so.
- **The full-review escalation cannot conjure a second verdict.** Where the
  review has already run and already been reported in the walkthrough, it
  returns `Action performed / Full review finished` within seconds. Escalating
  past a walkthrough that already answers for `HEAD_SHA` costs a full budget and
  yields an acknowledgement.
- An **empty-body `COMMENTED` review** is the wrapper CodeRabbit puts around a
  thread reply. It marks a conversation, not a verdict, and it can appear within
  seconds of a push. An empty-body **`APPROVED`** at the exact HEAD is the
  opposite — a terminal verdict, and the shape of every clean review — so count
  the state, not the body length.
- A green CodeRabbit check without a review body or inline finding is not a
  substantive review artifact.
- Scope inline comments by their stable `original_commit_id`, not the movable
  `commit_id`; otherwise old resolved feedback can impersonate an exact-HEAD
  review after later pushes reposition the diff.
- Quota or rate-limit text in a CodeRabbit comment is `unavailable`, not a
  review. The waiter stops on it, but the verdict is still `needs-changes`:
  CodeRabbit is the only gating reviewer, so an unavailable CodeRabbit means the
  PR was never reviewed.
- CodeRabbit answers `@coderabbitai review` only once per push in some
  configurations. Tag at most once per cycle; if the tag produces nothing within
  the budget, report `timeout` rather than tagging again.
- After posting a tag, take the tag comment's `created_at` from the API
  response as the anchor for any `since=` comment filtering. CodeRabbit can
  reply within seconds; a window derived from your own clock or a later
  timestamp silently drops that reply and makes a finished review look like
  silence.
- On a fork PR, CodeRabbit may be configured off entirely. Check whether it has
  ever commented on this repository before waiting out a second full budget.

### CodeRabbit and bot identities

- **CodeRabbit does not process conversational comments from GitHub `Bot`
  actors.** It answers `Skipped: comment is from another GitHub bot` within
  seconds and reads nothing. **No setting changes this** — not in
  `.coderabbit.yaml`, the repository or organization UI, or the published API.
  `ignore_usernames` is exclusion-only and applies to the pull request author;
  `chat.allow_non_org_members` and `chat.auto_reply` do not govern actor type;
  `review_status: false` only hides status messages. Do not go looking again.
- **Commands are exempt.** `@coderabbitai review` and `@coderabbitai full review`
  are honoured from a bot account; only conversation is dropped. That asymmetry
  is the escape hatch, and it is the escalation rather than the main path.
- What a bot identity costs: CodeRabbit never reads the fix rationale, never
  answers a declined finding, and never resolves the thread itself — so the
  approval that follows its own resolution may never arrive. Report it under
  Repository expectations rather than working around it silently.
- The remedy is a machine-user PAT for the commenting calls, which makes the
  actor a `User`. An `actions/create-github-app-token` installation token does
  **not**: it still authenticates as the App's bot. Weigh the cost first — PAT
  events re-trigger workflows where `GITHUB_TOKEN` events do not, so the switch
  needs actor filters and an iteration ceiling.
- A separate **pull-request-author** gate exists and reads
  `Review skipped. Bot user detected. To trigger a single review, invoke the
  @coderabbitai review command.` That is a different problem with a different
  remedy, and whether automatic review resumes for later pushes after that one
  forced review is undocumented.
- A reviewer that answered the early cycles and then goes silent on a later one
  may have hit `reviews.auto_review.auto_pause_after_reviewed_commits`, which
  pauses automatic review after that many reviewed commits and defaults to 5 —
  within reach of this skill's five-cycle cap when each cycle pushes a fix. The
  tag path recovers it: post one `@coderabbitai review` and restart the waiter
  with `--tagged-coderabbit`, because manual review survives the pause. Report
  the silence in the verdict so the repository owner can set the key to 0.

## Snapshots and required checks

- Keep the last good snapshot when a refresh fails. Transient failures consume
  the existing bounded wait; only failures that persist through the full wait
  budget produce `snapshot_fetch_failing`. Never infer a clean pass from stale
  or empty data.
- If the issue-comments REST endpoint fails, the waiter may retrieve the same
  top-level comment bodies through GitHub's paginated GraphQL comments
  connection. It still requires the review and inline-comment surfaces.
- If the branch-rules endpoint fails, the waiter may derive the required-check
  names from `gh pr checks --required`. It still fails closed when neither
  source returns valid JSON.
- One branch-rules failure is not a failure: HTTP 403 with "Upgrade to GitHub
  Pro or make this repository public" (private repo on the free plan) means the
  rules feature is unavailable, so rules cannot exist — read it as an empty
  ruleset, not a failed lookup. The waiter does this itself; apply the same
  reading in Section 5.
- A limited token can read PRs yet 403 on `commits/*/check-runs` ("Resource not
  accessible by personal access token"). Harmless when the ruleset requires no
  checks — the waiter skips the rollup then — but with required checks present
  it stays fail-closed.
- A required context with no node in `statusCheckRollup` is pending, not
  passing — a workflow that never started looks identical to a clean rollup
  otherwise.
- A required `pull_request` approval gate only evaluates once the PR is ready for
  review. On a draft PR, report it as deferred instead of waiting for it.
- Merge-blocking threads can come from humans, who never gate the wait. Always
  enumerate every unresolved thread in the final snapshot.
