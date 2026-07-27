# Reviewer edge cases

Read this reference only when the waiter returns `failed`, `timeout`, or
`snapshot_fetch_failing`, or when a green CodeRabbit check has no substantive
review artifact.

## CodeRabbit

- A walkthrough (`summarize by coderabbit.ai`), `review in progress`, or
  `No new commits to review` is engagement, not a substantive review.
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
- On a fork PR, CodeRabbit may be configured off entirely. Check whether it has
  ever commented on this repository before waiting out a second full budget.

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
- A required context with no node in `statusCheckRollup` is pending, not
  passing — a workflow that never started looks identical to a clean rollup
  otherwise.
- A required `pull_request` approval gate only evaluates once the PR is ready for
  review. On a draft PR, report it as deferred instead of waiting for it.
- Merge-blocking threads can come from humans, who never gate the wait. Always
  enumerate every unresolved thread in the final snapshot.
