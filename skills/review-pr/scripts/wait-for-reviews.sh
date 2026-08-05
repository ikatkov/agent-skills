#!/usr/bin/env bash

# jq programs deliberately keep their --arg variables single-quoted.
# shellcheck disable=SC2016

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: wait-for-reviews.sh \
  --owner OWNER --repo REPO --pr NUMBER --head SHA \
  --review-start Z_UTC --commit-date Z_UTC [options]

Wait silently for an exact-HEAD CodeRabbit review and the ruleset-required
status checks. The script prints exactly one JSON object when it reaches a
terminal state.

Auth: uses `gh` when it works end to end. When it does not (not installed,
unauthenticated, or broken by a command sandbox), it falls back to direct
REST/GraphQL calls with curl, authenticated by $GH_TOKEN or $GITHUB_TOKEN —
the same endpoints, not a degraded path. Neither transport prints the token.

Options:
  --base BRANCH                 Base branch (default: main)
  --interval SECONDS            Poll interval (default: 50)
  --timeout SECONDS             Total wait budget (default: 900)
  --tag-after SECONDS           Missing-bot fallback delay (default: 480).
                                Must sit above the repository's observed
                                push-to-review latency: a tag posted inside
                                that window interrupts the automatic review it
                                was meant to provoke.
  --once                        Probe once without sleeping
  --tagged-coderabbit           CodeRabbit fallback tag was already posted
  --re-review-cycle             This wait follows a fix push for findings from
                                an exact-HEAD review at the previous anchor.
                                Automatic incremental review covers the new
                                commit, so the wait is the whole mechanism; the
                                flag only enables the needs_full_review
                                escalation once the budget runs low.
  --full-review-after SECONDS   Escalation delay on a re-review cycle, and on
                                any cycle whose CodeRabbit rate-limit window has
                                run out (default: 600). A clean incremental
                                review can emit no artifact at all, and a
                                refused request is never retried on its own;
                                neither case ends a wait.
  --forced-full-review          `@coderabbitai full review` was already posted
EOF
}

OWNER=""
REPO=""
PR=""
HEAD_SHA=""
REVIEW_START=""
COMMIT_DATE=""
BASE="main"
INTERVAL=50
TIMEOUT=900
TAG_AFTER=480
FULL_REVIEW_AFTER=600
ONCE=0
TAGGED_CODERABBIT=0
RE_REVIEW=0
FORCED_FULL_REVIEW=0

while (($#)); do
  case "$1" in
    --owner) OWNER=${2:-}; shift 2 ;;
    --repo) REPO=${2:-}; shift 2 ;;
    --pr) PR=${2:-}; shift 2 ;;
    --head) HEAD_SHA=${2:-}; shift 2 ;;
    --review-start) REVIEW_START=${2:-}; shift 2 ;;
    --commit-date) COMMIT_DATE=${2:-}; shift 2 ;;
    --base) BASE=${2:-}; shift 2 ;;
    --interval) INTERVAL=${2:-}; shift 2 ;;
    --timeout) TIMEOUT=${2:-}; shift 2 ;;
    --tag-after) TAG_AFTER=${2:-}; shift 2 ;;
    --full-review-after) FULL_REVIEW_AFTER=${2:-}; shift 2 ;;
    --once) ONCE=1; shift ;;
    --tagged-coderabbit) TAGGED_CODERABBIT=1; shift ;;
    --re-review-cycle) RE_REVIEW=1; shift ;;
    --forced-full-review) FORCED_FULL_REVIEW=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for required in OWNER REPO PR HEAD_SHA REVIEW_START COMMIT_DATE; do
  if [[ -z ${!required} ]]; then
    printf 'missing required argument: %s\n' "$required" >&2
    usage >&2
    exit 2
  fi
done

if ! [[ $PR =~ ^[0-9]+$ && $INTERVAL =~ ^[1-9][0-9]*$ && $TIMEOUT =~ ^[1-9][0-9]*$ && $TAG_AFTER =~ ^[0-9]+$ && $FULL_REVIEW_AFTER =~ ^[0-9]+$ ]]; then
  printf 'PR, interval, timeout, tag-after, and full-review-after must be non-negative integers (positive except the delays)\n' >&2
  exit 2
fi

for command in jq mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'required command not found: %s — stop the review, do not work around it\n' "$command" >&2
    exit 2
  fi
done

# ---- transport selection -----------------------------------------------------
#
# gh is preferred, but it is a Go binary: inside a macOS command sandbox its
# platform TLS verifier (Security.framework) is blocked and every call dies
# with `x509: OSStatus …` even though curl works fine — and `gh auth status`
# can still pass. Probing gh END TO END (a real API call) is what routes
# around that.

GH_MODE=""
API="https://api.github.com"
API_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if command -v gh >/dev/null 2>&1 \
  && gh auth status >/dev/null 2>&1 \
  && gh api "repos/$OWNER/$REPO" --jq .full_name >/dev/null 2>&1; then
  GH_MODE=gh
elif [[ -n $API_TOKEN ]] && command -v curl >/dev/null 2>&1 \
  && curl -fsS -H "Authorization: Bearer $API_TOKEN" -H 'Accept: application/vnd.github+json' \
       "$API/repos/$OWNER/$REPO" >/dev/null 2>&1; then
  GH_MODE=curl
else
  printf 'no working GitHub access: gh failed and no usable GH_TOKEN/GITHUB_TOKEN for curl — stop the review\n' >&2
  exit 2
fi

# GET one path (relative to the API root). Prints the body followed by one
# final line holding the HTTP status code — the caller splits them. The code
# cannot travel back through a variable: callers run this inside $(...), which
# is a subshell, and a global set there dies with it.
raw_get() {
  curl -sS -w $'\n%{http_code}' \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    "$API/$1"
}

# Emit every element of a paginated array endpoint, one JSON object per line.
api_elements() {
  local path=$1
  if [[ $GH_MODE == gh ]]; then
    gh api --paginate "$path" --jq '.[]'
    return
  fi
  local page=1 sep='?' resp code body n
  [[ $path == *\?* ]] && sep='&'
  while :; do
    resp=$(raw_get "${path}${sep}per_page=100&page=$page") || return 1
    code=${resp##*$'\n'}
    body=${resp%$'\n'*}
    [[ $code == 200 ]] || return 1
    n=$(jq 'length' <<<"$body" 2>/dev/null) || return 1
    jq -c '.[]' <<<"$body"
    ((n < 100)) && break
    ((page++))
    ((page > 30)) && break # runaway backstop; 3000 items is beyond any real PR
  done
}

# GET one non-paginated JSON document.
api_object() {
  local path=$1
  if [[ $GH_MODE == gh ]]; then
    gh api "$path"
    return
  fi
  local resp code body
  resp=$(raw_get "$path") || return 1
  code=${resp##*$'\n'}
  body=${resp%$'\n'*}
  [[ $code == 200 ]] || return 1
  printf '%s' "$body"
}

SHORT_SHA=${HEAD_SHA:0:9}
REPOSITORY="$OWNER/$REPO"
BASE_PATH=$(jq -rn --arg value "$BASE" '$value | @uri')
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/review-pr-watch.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

SNAPSHOT="$WORK_DIR/snapshot.json"
PR_STATE="$WORK_DIR/pr-state.json"
RULES="$WORK_DIR/rules.json"
THREADS="$WORK_DIR/threads.json"

printf '[]\n' >"$SNAPSHOT"
printf '{}\n' >"$PR_STATE"
printf '[]\n' >"$RULES"
printf '{}\n' >"$THREADS"

STARTED_EPOCH=$(date +%s)

CR_STATUS="in-progress"
CHECKS_STATUS="pending"
CR_SEEN=false
PENDING_CHECKS='[]'
FAILED_CHECKS='[]'
UNRESOLVED_CR_THREADS=null
CR_RETRY_AFTER=null
CR_LIMIT=none

emit() {
  local state=$1
  local reason=$2
  local needs_tag=${3:-'[]'}
  local elapsed=$(( $(date +%s) - STARTED_EPOCH ))

  jq -cn \
    --arg state "$state" \
    --arg reason "$reason" \
    --argjson elapsed_seconds "$elapsed" \
    --arg coderabbit "$CR_STATUS" \
    --arg checks "$CHECKS_STATUS" \
    --argjson needs_tag "$needs_tag" \
    --argjson pending_checks "$PENDING_CHECKS" \
    --argjson failed_checks "$FAILED_CHECKS" \
    --argjson unresolved_cr_threads "$UNRESOLVED_CR_THREADS" \
    --argjson coderabbit_retry_after "$CR_RETRY_AFTER" \
    '{
      state: $state,
      reason: $reason,
      elapsed_seconds: $elapsed_seconds,
      reviewers: {
        coderabbit: $coderabbit
      },
      checks: $checks,
      needs_tag: $needs_tag,
      pending_checks: $pending_checks,
      failed_checks: $failed_checks,
      unresolved_coderabbit_threads: $unresolved_cr_threads,
      coderabbit_retry_after: $coderabbit_retry_after
    }'
}

fetch_snapshot() {
  local next="$WORK_DIR/snapshot.next.json"
  local issues="$WORK_DIR/issues.next.jsonl"
  local reviews="$WORK_DIR/reviews.next.jsonl"
  local comments="$WORK_DIR/comments.next.jsonl"

  if ! api_elements "repos/$OWNER/$REPO/issues/$PR/comments" \
      | jq -c '{surface:"issue",login:.user.login,id,ts:.created_at,commit:"",path:null,line:null,url:.html_url,body}' >"$issues" 2>/dev/null; then
    rm -f "$issues"
    if [[ $GH_MODE == gh ]]; then
      gh api graphql --paginate -f query='
        query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
          repository(owner:$owner,name:$repo){pullRequest(number:$pr){
            comments(first:100,after:$endCursor){
              nodes{id body createdAt url author{login}}
              pageInfo{hasNextPage endCursor}
            }
          }}
        }' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR" \
        --jq '.data.repository.pullRequest.comments.nodes[] |
          (.author.login // "") as $login |
          {surface:"issue",
           login:(if $login == "coderabbitai" then "coderabbitai[bot]" else $login end),
           id,ts:.createdAt,commit:"",path:null,line:null,url,body}' >"$issues" 2>/dev/null || {
        rm -f "$issues"
        return 1
      }
    else
      return 1
    fi
  fi

  if api_elements "repos/$OWNER/$REPO/pulls/$PR/reviews" 2>/dev/null \
      | jq -c '{surface:"review",login:.user.login,id,ts:.submitted_at,commit:.commit_id,state:.state,path:null,line:null,url:.html_url,body}' >"$reviews" 2>/dev/null \
    && api_elements "repos/$OWNER/$REPO/pulls/$PR/comments" 2>/dev/null \
      | jq -c '{surface:"inline",login:.user.login,id,ts:.created_at,commit:(.original_commit_id // .commit_id),path,line,url:.html_url,body}' >"$comments" 2>/dev/null \
    && jq -s 'sort_by(.ts // "")' "$issues" "$reviews" "$comments" >"$next"; then
    mv "$next" "$SNAPSHOT"
    return 0
  fi
  rm -f "$next" "$issues" "$reviews" "$comments"
  return 1
}

fetch_json() {
  local destination=$1
  shift
  local next="$destination.next"
  if "$@" >"$next" 2>/dev/null && jq -e . "$next" >/dev/null 2>&1; then
    mv "$next" "$destination"
    return 0
  fi
  rm -f "$next"
  return 1
}

# Build a statusCheckRollup-shaped document from the commit's check runs and
# legacy commit statuses. One source of truth for both transports; `gh pr view`
# has no REST equivalent for the curl path.
fetch_rollup() {
  local runs statuses
  runs=$(api_object "repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" 2>/dev/null) || return 1
  statuses=$(api_object "repos/$OWNER/$REPO/commits/$HEAD_SHA/status" 2>/dev/null) || return 1
  jq -n --argjson runs "$runs" --argjson statuses "$statuses" '
    {statusCheckRollup:
      ([$runs.check_runs[]? | {name:(.name // ""), status:(.status // ""), conclusion:(.conclusion // "")}]
       + [$statuses.statuses[]? | {name:(.context // ""), status:"COMPLETED", conclusion:(.state // "")}])
    }' >"$PR_STATE" 2>/dev/null || return 1
  jq -e . "$PR_STATE" >/dev/null 2>&1
}

# True when the rules feature is unavailable on this plan (private repo without
# Pro). Rules cannot exist there, so the correct reading is "no required
# checks", not a fail-closed lookup failure.
rules_feature_unavailable() {
  grep -qiE 'upgrade to github pro|make this repository public' <<<"$1"
}

fetch_rules() {
  local required_checks="$WORK_DIR/required-checks.next.json"
  local next="$RULES.next"
  local body

  if [[ $GH_MODE == curl ]]; then
    local resp code
    resp=$(raw_get "repos/$OWNER/$REPO/rules/branches/$BASE_PATH") || return 1
    code=${resp##*$'\n'}
    body=${resp%$'\n'*}
    if [[ $code == 200 ]] && jq -e . <<<"$body" >/dev/null 2>&1; then
      printf '%s\n' "$body" >"$RULES"
      return 0
    fi
    if [[ $code == 403 ]] && rules_feature_unavailable "$body"; then
      printf '[]\n' >"$RULES"
      return 0
    fi
    return 1
  fi

  if fetch_json "$RULES" gh api "repos/$OWNER/$REPO/rules/branches/$BASE_PATH"; then
    return 0
  fi

  body=$(gh api "repos/$OWNER/$REPO/rules/branches/$BASE_PATH" 2>&1 || true)
  if rules_feature_unavailable "$body"; then
    printf '[]\n' >"$RULES"
    return 0
  fi

  # The branch-rules endpoint can fail independently of the checks API. Keep
  # the gate fail-closed, but accept gh's required-check view as an equivalent
  # source for the only ruleset field this waiter consumes.
  gh pr checks "$PR" --repo "$REPOSITORY" --required \
    --json name,state,bucket >"$required_checks" 2>/dev/null || :
  if jq -e 'type == "array"' "$required_checks" >/dev/null 2>&1 \
    && jq '[{
      type: "required_status_checks",
      parameters: {
        required_status_checks: [.[] | {context: .name}]
      }
    }]' "$required_checks" >"$next"; then
    mv "$next" "$RULES"
    rm -f "$required_checks"
    return 0
  fi

  rm -f "$required_checks" "$next"
  return 1
}

THREADS_QUERY='query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
  repository(owner:$owner,name:$repo){pullRequest(number:$pr){
    reviewThreads(first:100,after:$endCursor){
      nodes{isResolved comments(first:1){nodes{author{login}}}}
      pageInfo{hasNextPage endCursor}}}}}'

# One GraphQL page over curl. Prints the page body; fails on transport errors,
# GraphQL errors, or a missing pullRequest node.
graphql_page() {
  local cursor=$1 payload resp code body
  payload=$(jq -cn --arg query "$THREADS_QUERY" --arg owner "$OWNER" --arg repo "$REPO" \
    --argjson pr "$PR" --arg cursor "$cursor" \
    '{query:$query, variables:{owner:$owner, repo:$repo, pr:$pr,
      endCursor:(if $cursor == "" then null else $cursor end)}}') || return 1
  resp=$(curl -sS -w $'\n%{http_code}' \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$payload" "$API/graphql") || return 1
  code=${resp##*$'\n'}
  body=${resp%$'\n'*}
  [[ $code == 200 ]] || return 1
  jq -e '((.errors // []) | length == 0) and (.data.repository.pullRequest != null)' \
    <<<"$body" >/dev/null 2>&1 || return 1
  printf '%s' "$body"
}

# Reported, not gated on. Section 4 of the skill resolves threads itself, so a
# zero count is an account of this run's own actions rather than evidence about
# the review — but it is what tells a reader whether anything is still open.
fetch_threads() {
  if [[ $GH_MODE == gh ]]; then
    fetch_json "$THREADS" gh api graphql --paginate -f query="$THREADS_QUERY" \
      -f owner="$OWNER" -f repo="$REPO" -F pr="$PR" || return 1
  else
    local pages="$WORK_DIR/threads.next.jsonl" cursor="" page hasNext
    : >"$pages"
    while :; do
      page=$(graphql_page "$cursor") || { rm -f "$pages"; return 1; }
      printf '%s\n' "$page" >>"$pages"
      hasNext=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page" 2>/dev/null) || { rm -f "$pages"; return 1; }
      [[ $hasNext == true ]] || break
      cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")
    done
    mv "$pages" "$THREADS"
  fi

  UNRESOLVED_CR_THREADS=$(jq -s '
    [.[].data.repository.pullRequest.reviewThreads.nodes[]?
      | select(.isResolved == false)
      | select(((.comments.nodes[0].author.login // "") | ascii_downcase)
          | startswith("coderabbitai"))
    ] | length' "$THREADS") || return 1
}

snapshot_query() {
  local query=$1
  jq -r \
    --arg sha "$HEAD_SHA" \
    --arg short "$SHORT_SHA" \
    --arg review_start "$REVIEW_START" \
    --arg commit_date "$COMMIT_DATE" \
    "$query" "$SNAPSHOT"
}

classify_reviews() {
  CR_SEEN=$(snapshot_query '
    def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
    any(.[]; .login == "coderabbitai[bot]" and scope)')

  # What CodeRabbit says when *it* is refusing — which is not the same as any
  # comment of its that mentions a quota. CodeRabbit describes every diff in its
  # own words, so a pull request about rate limits earns a walkthrough containing
  # "rate limit", and reading that as a refusal reports the reviewer unavailable
  # on its own summary of the change, from the first cycle, with no quota
  # anywhere. Three narrowings, each onto a notice CodeRabbit actually publishes:
  #
  #   - the wording is its own headings and generated sentences — "Review rate
  #     limited", "Review limit reached", "your next included review will be
  #     available in 28 minutes" — not the free-form "rate limit" it may write
  #     about anything;
  #   - the looser refusals are read on every surface except the walkthrough,
  #     the one comment whose body is by definition a description of the diff;
  #   - and a body that also reports a review in progress, or one that found
  #     nothing, is reporting work rather than declining it.
  #
  # A notice must also still be live, because it never leaves the snapshot on its
  # own: scope admits anything timestamped at or after the head commit, and a
  # notice is by construction newer, so only a new commit clears one. Left
  # unbounded it ends every later wait within seconds — including the waits that
  # follow the window reopening, which are the ones the caller re-armed for.
  # Live means CodeRabbit has said nothing since it, and the window it published
  # has not run out. A notice past either is `spent`, which escalates below
  # rather than ending the wait.
  CR_LIMIT=$(snapshot_query '
    def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
    def walkthrough: test("summarize by coderabbit\\.ai"; "i");
    def working: test("review in progress|no actionable comments were generated"; "i");
    def notice:
      (
        test("review rate limited|rate limit exceeded|review limit reached"; "i")
        or test("(next|another)( included)? review( will be)? available in"; "i")
        or (
          test("out[ -]?of[ -]?(plan[ -]?)?quota|temporar(y|ily) unavailable|unable to review"; "i")
          and (walkthrough | not)
        )
      ) and (working | not);
    def window:
      (
        capture("(?:next|another)(?: included)? review(?: will be)? available in:?\\**\\s*\\**(?<v>[0-9]+)\\s*(?<u>second|minute|hour)"; "i")
        | (.v | tonumber) * (if (.u | ascii_downcase) == "hour" then 3600 elif (.u | ascii_downcase) == "minute" then 60 else 1 end)
      ) // null;
    [ .[] | select(.login == "coderabbitai[bot]") ] as $cr
    | ([ $cr[] | .ts // "" ] | max // "") as $newest
    | [ $cr[]
        | select(scope and ((.body // "") | notice) and ((.ts // "") >= $newest))
        | {ts: (.ts // ""), window: ((.body // "") | window)}
      ] as $notices
    | if ($notices | length) == 0 then "none"
      elif any($notices[]; .window == null or .ts == "" or (((.ts | fromdateiso8601) + .window) > now)) then "live"
      else "spent"
      end')
  [[ -n $CR_LIMIT ]] || CR_LIMIT=none
  # A verdict counts two ways. Prose — an inline finding, or a review body that
  # is more than CodeRabbit's own chatter. And a *state* on this exact commit:
  # CodeRabbit posts APPROVED with an empty body when it has nothing to say,
  # which is the shape of every clean review. Reading only prose leaves that
  # approval invisible and grinds the whole wait budget to timeout, which is the
  # cost paid by exactly the pull requests that needed no changes.
  #
  # The chatter filter covers every surface. CodeRabbit posts non-review prose
  # inline as well as at review level — command acknowledgements, and a refusal
  # to process comments authored by another bot. Any of those is a few dozen
  # bytes long, can carry an older commit than HEAD, and lands within seconds of
  # a push, so exempting the inline surface turns the whole wait into a no-op
  # exactly when a fix commit needs reviewing.
  #
  # The state branch is anchored to `.commit == $sha` rather than the looser
  # `scope`, because a review state means something only for the commit it
  # names. That keeps the exact-HEAD guarantee the whole skill rests on.
  #
  # The third branch reads the walkthrough comment, which the chatter filter
  # otherwise discards wholesale for carrying the `summarize by coderabbit.ai`
  # marker. A clean review can produce no review object and no inline comment at
  # all — its entire verdict is the sentence "No actionable comments were
  # generated in the recent review" edited into that one comment. Discarding it
  # spends the full budget, escalates a full review that answers with an
  # acknowledgement, and reports a reviewed commit as unreviewed, on exactly the
  # pull requests that had nothing wrong with them.
  #
  # Both halves are required and both are checked on the same comment. The
  # verdict sentence alone says nothing about which commit earned it, and the
  # comment is mutable — CodeRabbit rewrites it in place on every review — so the
  # anchor is the *end* of the range it reports. Matching the SHA anywhere in the
  # body would accept a comment whose range merely *starts* at this commit, which
  # is what an incremental review of the commit after it reads like: a range
  # reading "between A and B" while the loop is anchored at A reports a review of
  # B, not of A.
  #
  # A body carrying "Review limit reached" or "Review failed" never reaches here:
  # it does not carry the verdict sentence, and the rate-limit wording lands in
  # cr_unavailable below.
  local cr_substantive
  cr_substantive=$(snapshot_query '
    def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
    def chatter: test("summarize by coderabbit\\.ai|review in progress|processing new changes|no new commits to review|review finished|action performed|skipped: comment is from another github bot|auto-generated reply by coderabbit"; "i");
    def verdict_state: (.state // "") | ascii_upcase | . == "APPROVED" or . == "CHANGES_REQUESTED";
    def clean_at_head: test("no actionable comments were generated"; "i") and test("between [0-9a-f]{40} and " + $sha; "i");
    any(.[];
      .login == "coderabbitai[bot]" and
      (
        (
          scope and
          ((.body // "") | length > 0) and
          (((.body // "") | chatter) | not)
        )
        or
        (.surface == "review" and .commit == $sha and verdict_state)
        or
        ((.body // "") | clean_at_head)
      )
    )')

  # The walkthrough reports two non-verdicts for this exact commit as well, and
  # both are terminal: waiting past either only spends the budget. "Review
  # failed" carries its own `failure by coderabbit.ai` marker and states the
  # cause below it, most often a pull request closed under the reviewer. The
  # rate-limit block names the account whose per-developer quota ran out, which
  # is worth reading — it is the identity that pushed, so a loop running as a bot
  # exhausts a different allowance than the human who owns the repository.
  local cr_failed
  cr_failed=$(snapshot_query '
    def failed_at_head: test("failure by coderabbit\\.ai|##\\s*review failed"; "i") and test("between [0-9a-f]{40} and " + $sha; "i");
    any(.[]; .login == "coderabbitai[bot]" and ((.body // "") | failed_at_head))')

  # How long the limit has left to run, counted from the notice rather than
  # copied off it. Observed windows ranged from six seconds to forty-two
  # minutes, so a caller that re-arms on a fixed interval either wastes most of
  # one or wakes into the same limit — and a wait can return a quarter of an hour
  # after the notice was posted, which is enough of a forty-two-minute window to
  # matter. Both wordings are read: the walkthrough's `Next review available in:
  # <n> <unit>` and the command reply's `Your next included review will be
  # available in <n> minutes`, whose "included" the narrower pattern missed
  # entirely, handing back null for the one notice a caller most needs to re-arm
  # on.
  CR_RETRY_AFTER=$(snapshot_query '
    def window:
      (
        capture("(?:next|another)(?: included)? review(?: will be)? available in:?\\**\\s*\\**(?<v>[0-9]+)\\s*(?<u>second|minute|hour)"; "i")
        | (.v | tonumber) * (if (.u | ascii_downcase) == "hour" then 3600 elif (.u | ascii_downcase) == "minute" then 60 else 1 end)
      ) // null;
    [ .[]
      | select(.login == "coderabbitai[bot]")
      | {ts: (.ts // ""), window: ((.body // "") | window)}
      | select(.window != null)
      | if .ts == "" then .window else (((.ts | fromdateiso8601) + .window) - now) end
      | if . < 0 then 0 else floor end
    ] | last // null')
  [[ -n $CR_RETRY_AFTER ]] || CR_RETRY_AFTER=null

  if [[ $cr_substantive == true ]]; then CR_STATUS="responded"
  elif [[ $CR_LIMIT == live ]]; then CR_STATUS="unavailable"
  elif [[ $cr_failed == true ]]; then CR_STATUS="failed"
  else CR_STATUS="in-progress"
  fi
}

classify_checks() {
  local required rollup
  required=$(jq -c '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context] | unique' "$RULES")
  rollup=$(jq -c '[.statusCheckRollup[]? | {name:(.name // .context // ""),status:(.status // ""),conclusion:(.conclusion // .state // "")}]' "$PR_STATE")

  FAILED_CHECKS=$(jq -cn --argjson required "$required" --argjson rollup "$rollup" '
    def node($name): [$rollup[] | select(.name == $name)] | last;
    [$required[] as $name |
      (node($name)) as $node |
      select($node != null and (["FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE","STALE"] | index(($node.conclusion | ascii_upcase))) != null) |
      $name
    ]')

  PENDING_CHECKS=$(jq -cn \
    --argjson required "$required" \
    --argjson rollup "$rollup" '
      def node($name): [$rollup[] | select(.name == $name)] | last;
      [$required[] as $name |
        (node($name)) as $node |
        select(
          $node == null or
          ((["SUCCESS","SKIPPED"] | index(($node.conclusion | ascii_upcase))) == null and
           (["FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE","STALE"] | index(($node.conclusion | ascii_upcase))) == null)
        ) |
        $name
      ]')

  if (( $(jq 'length' <<<"$FAILED_CHECKS") > 0 )); then CHECKS_STATUS="failed"
  elif (( $(jq 'length' <<<"$PENDING_CHECKS") > 0 )); then CHECKS_STATUS="pending"
  else CHECKS_STATUS="ready"
  fi
}

probe() {
  local failed=0

  fetch_snapshot || failed=1
  fetch_rules || failed=1
  if ((RE_REVIEW)); then fetch_threads || failed=1; fi

  if ((failed)); then return 1; fi

  # The rollup is only needed — and often only readable — when the ruleset
  # actually requires checks. A limited token can read PRs yet 403 on
  # check-runs ("Resource not accessible by personal access token"); with zero
  # required contexts that blindness is harmless, so don't fail the probe over
  # a surface nothing consumes. With required contexts present it stays
  # fail-closed.
  if (( $(jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context] | length' "$RULES") > 0 )); then
    fetch_rollup || return 1
  else
    printf '{"statusCheckRollup":[]}\n' >"$PR_STATE"
  fi

  classify_reviews
  classify_checks
  return 0
}

while :; do
  if ! probe; then
    elapsed=$(( $(date +%s) - STARTED_EPOCH ))
    if ((ONCE || elapsed >= TIMEOUT)); then
      emit "snapshot_fetch_failing" "GitHub snapshots are still failing" '[]'
      exit 0
    fi
    sleep "$INTERVAL"
    continue
  fi

  if [[ $CHECKS_STATUS == failed ]]; then
    emit "failed" "a required status check failed" '[]'
    exit 0
  fi

  # Cycle 1 only. A re-review cycle escalates through needs_full_review instead,
  # because `@coderabbitai review` is incremental and returns an acknowledgement
  # for a commit automatic review has already accounted for.
  elapsed=$(( $(date +%s) - STARTED_EPOCH ))
  if ((RE_REVIEW == 0)) && ((elapsed >= TAG_AFTER)) && ((TAGGED_CODERABBIT == 0)) \
    && [[ $CR_STATUS == in-progress && $CR_SEEN == false ]]; then
    emit "needs_tag" "tag CodeRabbit once, then restart the waiter with --tagged-coderabbit" '["coderabbit"]'
    exit 0
  fi

  # Automatic incremental review covers every push, so waiting is the whole
  # mechanism on a re-review cycle. The one case it cannot end is a clean
  # incremental review, which can emit no artifact at all — there is nothing to
  # wait for and nothing to conclude from. `full review` is the only command
  # that produces an artifact on demand; `review` is itself incremental and
  # no-ops while automatic review is un-paused.
  #
  # A spent quota window reaches the same escalation from the other side, on any
  # cycle. The request that hit the limit was refused, not queued, so nothing
  # arrives once the window reopens until something asks again — and the caller
  # re-armed on the published delay precisely to ask. Without this the wait that
  # follows a quota simply runs its budget out. The delay still applies: a review
  # that did start silently takes minutes, and a command posted inside that
  # window interrupts it.
  if { ((RE_REVIEW)) || [[ $CR_LIMIT == spent ]]; } \
    && ((elapsed >= FULL_REVIEW_AFTER)) && ((FORCED_FULL_REVIEW == 0)) \
    && [[ $CR_STATUS == in-progress ]]; then
    emit "needs_full_review" "post one @coderabbitai full review, then restart the waiter with --forced-full-review" '["coderabbit"]'
    exit 0
  fi

  # `failed` joins these because a failed review is as terminal as a delivered
  # one: CodeRabbit has stopped, and no further waiting changes that. It is not
  # a pass — Section 6 reports the commit as unreviewed — but spending the rest
  # of the budget first buys nothing.
  if [[ $CR_STATUS == responded || $CR_STATUS == unavailable || $CR_STATUS == failed ]] \
    && [[ $CHECKS_STATUS == ready ]]; then
    emit "ready" "the CodeRabbit wait and required status checks are terminal" '[]'
    exit 0
  fi

  if ((ONCE)); then
    emit "pending" "the CodeRabbit review or required status checks are still pending" '[]'
    exit 0
  fi

  if ((elapsed >= TIMEOUT)); then
    emit "timeout" "bounded review wait expired" '[]'
    exit 0
  fi

  sleep "$INTERVAL"
done
