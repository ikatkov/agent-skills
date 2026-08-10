# Reviewer edge cases

Read this reference only when the waiter returns `failed`, `timeout`, or
`snapshot_fetch_failing`, or when a green CodeRabbit check has no substantive
review artifact.

## CodeRabbit

- `review in progress` and `No new commits to review` are engagement. This holds
  on every cycle, first or later.
- **The walkthrough comment is where a clean review lives.** When a review finds
  nothing, CodeRabbit posts no review object and no inline comment, and edits
  `No actionable comments were generated in the recent review` into that comment.
  The comment also carries the `summarize by coderabbit.ai` marker, so the
  chatter filter exempts it for this one sentence. Accept it with both halves
  present on the same comment: the sentence, and a reviewed range ending at the
  head. CodeRabbit documents the placement in "Why did CodeRabbit not leave any
  review comments on my pull request", which puts the confirmation below the
  Walkthrough section.
- **The walkthrough summary is the only signal a clean review produces.**
  CodeRabbit exposes no review object, check-run field, webhook or endpoint
  reporting "commit X reviewed, N actionable comments". Parsing that sentence is
  the supported route.
- **The review-progress check answers completion.** Where the repository enables
  it, it binds to the head commit and carries a status readable without parsing
  prose, reporting that the run finished. Use it to tell a review still in flight
  from a review that finished silently. The verdict comes from the surfaces
  above.
- The walkthrough is **mutable**, rewritten in place on each review, so anchor on
  the *end* of `between <base> and <head>`. A range reading `between A and B`
  while the loop is anchored at `A` reports a review of `B`.
- The same comment carries two terminal non-verdicts, and waiting past either
  only spends the budget:
  - `Review failed`, with its own `failure by coderabbit.ai` marker and the
    cause below it (most often "The pull request is closed"). Classified
    `failed`, which ends the wait and leaves the commit unreviewed.
  - `Review limit reached`, carrying `Next review available in: <n> <unit>`.
    Classified `unavailable` while the window still has time on it, with the
    remaining seconds reported as `coderabbit_retry_after`. Published windows run
    from seconds to tens of minutes, so re-arm on that number.
- **A rate-limit notice is CodeRabbit reporting its own state, and only its own
  wording says so.** Match the headings and generated sentences — `Review rate
  limited`, `Review limit reached`, `Your next included review will be available
  in <n> minutes` — plus the looser refusals (`out of quota`, `temporarily
  unavailable`, `unable to review`) on every surface *except* the walkthrough,
  whose body describes the change by construction. CodeRabbit summarises every
  diff in its own words, so a pull request about quota handling puts "rate limit"
  through its walkthrough while the review runs normally.
- **A notice stays in the snapshot until a new commit clears it, so bound it in
  time.** Scope admits any comment timestamped at or after the head commit, and a
  notice is by construction newer, so moving `--review-start` forward leaves it
  in place. Read a notice as live while CodeRabbit has said nothing since it and
  its published window has time left. Once it is spent, escalate with one
  `@coderabbitai full review`: the refused request was dropped.
- The two retry wordings differ and a pattern must cover both: `Your next
  included review will be available in 28 minutes` under `⚠️ Action not
  completed`, and the walkthrough's `Next review available in: <n> <unit>`. The
  command reply is the one a caller most often needs a delay from.
- The rate-limit notice names the account whose quota ran out, and the quota is
  **per developer**: charged to the repository owner or to `github-actions[bot]`
  according to which identity pushed. A loop running as a bot therefore exhausts
  a different allowance than the human. Pro is 5 PR reviews an hour and Pro+ is
  10, on a rolling window, with additional spacing above the 95th percentile of
  recent activity.
- **Every review counts as one, incremental reviews included.** Five fix commits
  pushed to one pull request spend five reviews, and a manually triggered
  `review` or `full review` run counts the same as an automatic one. A five-cycle
  loop therefore spends half a Pro+ hour before either escalation, and its later
  cycles are the ones the spacing slows down, so `Review limit reached` on cycle
  four is usually the loop's own doing. Batch a cycle's fixes into one push.
  `@coderabbitai rate limit` reports the remaining allowance without consuming a
  review, which is the cheap way for a human to check.
- Raising `auto_pause_after_reviewed_commits` above `0` is the other way to spend
  less quota, and CodeRabbit recommends it. This skill keeps `0` and pays in
  quota: a paused reviewer goes silent mid-loop, which reads as an approving one
  until the tag path recovers it, while a spent quota announces itself. A
  repository that sets it higher should expect the Section 2 tag path to carry
  more of its cycles.
- **A review takes minutes.** `auto_incremental_review` defaults to on, so
  automatic review picks up each push without being asked. Push-to-artifact
  latency runs 100–440 seconds, on fix commits as well as first ones, and every
  delay in the waiter sits above that band. A command posted inside the window
  interrupts the review it was meant to provoke and answers with an
  acknowledgement.
- **`@coderabbitai review` is itself incremental** and no-ops while automatic
  review is un-paused. It answers `Review finished` within seconds, over a note
  saying it "does not re-review already reviewed commits" and applies "only when
  automatic reviews are paused". `@coderabbitai full review` reassesses from
  scratch, and it is the one command that produces an artifact on demand. Reach
  for it once the wait has genuinely run dry.
- **Silence can be the whole answer.** A clean incremental review emits no
  review, no inline comment and no state. Check the walkthrough comment above
  before calling it silent, because that is where the verdict usually is. Where
  even that is missing there is nothing to wait for, which is what the
  `needs_full_review` escalation exists for. If that still yields nothing, the
  commit went unreviewed and the verdict says so.
- **The full-review escalation cannot conjure a second verdict.** Where the
  review has already run and already been reported in the walkthrough, it
  returns `Action performed / Full review finished` within seconds. Escalating
  past a walkthrough that already answers for `HEAD_SHA` costs a full budget and
  yields an acknowledgement. Treat the acknowledgement as engagement on every
  cycle.
- A run that was rate-limited or skipped outright used to report
  `Full review finished` anyway. CodeRabbit has fixed that, and a run which does
  not complete now reports that outcome. Where a `full review` still answers
  `finished` with no artifact and no already-reviewed commit behind it, send the
  pull request URL and the time to CodeRabbit support: they key their own run
  logs off that URL.
- An **empty-body `COMMENTED` review** is the wrapper CodeRabbit puts around a
  thread reply. It marks a conversation, and it can appear within seconds of a
  push. An empty-body **`APPROVED`** at the exact HEAD is a terminal verdict and
  the shape of every clean review, so count the state at any body length.
- **The approval is posted once per pull request.** Under
  `reviews.request_changes_workflow`, a clean review with no unresolved
  CodeRabbit threads and no blocking pre-merge checks posts a real GitHub
  approval. CodeRabbit then leaves the pull request approved, so the next push
  earns no second approval, and `reviewDecision` reads `APPROVED` over a commit
  nothing reviewed. It becomes a per-commit signal where branch protection
  dismisses stale approvals on push. The waiter therefore anchors its state
  branch on `.commit == $sha`, which reads correctly under either configuration.
- A green CodeRabbit check without a review body or inline finding counts as
  engagement.
- Scope inline comments by their stable `original_commit_id`. The movable
  `commit_id` lets old resolved feedback impersonate an exact-HEAD review after
  later pushes reposition the diff.
- A live rate-limit notice is `unavailable`. The waiter stops on it, and the
  verdict is still `needs-changes`: CodeRabbit is the only gating reviewer, so an
  unavailable CodeRabbit means the PR went unreviewed. Quota wording in prose it
  wrote *about the diff* leaves the wait running.
- CodeRabbit answers `@coderabbitai review` only once per push in some
  configurations. Tag at most once per cycle; if the tag produces nothing within
  the budget, report `timeout`.
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
  `review_status: false` only hides status messages. The skip is by design, no
  customer-configurable allowlist for GitHub bot accounts exists, and a dedicated
  machine-user account is the supported path for automation that needs to reply
  inside review threads. Do not go looking again.
- **Commands are exempt.** `@coderabbitai review` and `@coderabbitai full review`
  are honoured from a bot account; only conversation is dropped. That asymmetry
  is the escape hatch, and it belongs on the escalation path.
- What a bot identity costs: CodeRabbit never reads the fix rationale, never
  answers a declined finding, and never resolves the thread itself, so the
  approval that follows its own resolution may never arrive. Report it under
  Repository expectations.
- The remedy is a machine-user PAT for the commenting calls, which makes the
  actor a `User`. An `actions/create-github-app-token` installation token
  authenticates as the App's bot and leaves the skip in place. Weigh the cost
  first: PAT events re-trigger workflows that `GITHUB_TOKEN` events leave alone,
  so the switch needs actor filters and an iteration ceiling.
- A separate **pull-request-author** gate exists and reads
  `Review skipped. Bot user detected. To trigger a single review, invoke the
  @coderabbitai review command.` It has its own remedy, and whether automatic
  review resumes for later pushes after that one forced review is undocumented.
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
- One branch-rules failure reads as an empty ruleset: HTTP 403 with "Upgrade to
  GitHub Pro or make this repository public" (private repo on the free plan)
  means the rules feature is unavailable, so rules cannot exist. The waiter does
  this itself; apply the same reading in Section 5.
- A limited token can read PRs yet 403 on `commits/*/check-runs` ("Resource not
  accessible by personal access token"). The waiter skips the rollup where the
  ruleset requires no checks. With required checks present it stays fail-closed.
- A required context with no node in `statusCheckRollup` is pending. A workflow
  that never started otherwise looks identical to a clean rollup.
- A required `pull_request` approval gate only evaluates once the PR is ready for
  review. On a draft PR, report it as deferred.
- Merge-blocking threads can come from humans, who never gate the wait. Always
  enumerate every unresolved thread in the final snapshot.
