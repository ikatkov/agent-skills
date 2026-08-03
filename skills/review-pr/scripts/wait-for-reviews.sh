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
  --tag-after SECONDS           Missing-bot fallback delay (default: 60)
  --once                        Probe once without sleeping
  --tagged-coderabbit           CodeRabbit fallback tag was already posted
  --re-review-cycle             This wait follows a fix push for findings from
                                an exact-HEAD review at the previous anchor.
                                CodeRabbit reviews incrementally and never
                                re-posts a review body for a fix-only push, so
                                accept in-thread confirmations at the new HEAD
                                plus zero unresolved CodeRabbit threads as the
                                terminal state confirmed_no_new_findings.
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
TAG_AFTER=60
ONCE=0
TAGGED_CODERABBIT=0
RE_REVIEW=0

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
    --once) ONCE=1; shift ;;
    --tagged-coderabbit) TAGGED_CODERABBIT=1; shift ;;
    --re-review-cycle) RE_REVIEW=1; shift ;;
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

if ! [[ $PR =~ ^[0-9]+$ && $INTERVAL =~ ^[1-9][0-9]*$ && $TIMEOUT =~ ^[1-9][0-9]*$ && $TAG_AFTER =~ ^[0-9]+$ ]]; then
  printf 'PR, interval, timeout, and tag-after must be non-negative integers (positive except tag-after)\n' >&2
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
      unresolved_coderabbit_threads: $unresolved_cr_threads
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

# Re-review cycles gate on unresolved CodeRabbit threads instead of a review
# body CodeRabbit will never re-emit, so the waiter needs the thread state.
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
  local unavailable_regex='out[ -]?of[ -]?(plan[ -]?)?quota|rate[ -]?limit|temporar(y|ily) unavailable|unable to review'

  CR_SEEN=$(snapshot_query '
    def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
    any(.[]; .login == "coderabbitai[bot]" and scope)')
  local cr_unavailable
  cr_unavailable=$(snapshot_query "
    def scope: (.commit == \$sha) or ((.ts // \"\") >= \$review_start) or ((.ts // \"\") >= \$commit_date) or ((.body // \"\") | contains(\$sha) or contains(\$short));
    any(.[]; .login == \"coderabbitai[bot]\" and scope and ((.body // \"\") | test(\"$unavailable_regex\"; \"i\")))")
  # A verdict counts two ways. Prose — an inline finding, or a review body that
  # is more than CodeRabbit's own chatter. And a *state* on this exact commit:
  # CodeRabbit posts APPROVED with an empty body when it has nothing to say,
  # which is the shape of every clean review. Reading only prose leaves that
  # approval invisible and grinds the whole wait budget to timeout — observed on
  # qrz-bot#62, where APPROVED landed 85 seconds into a 950-second wait and the
  # waiter still reported in-progress.
  #
  # The state branch is anchored to `.commit == $sha` rather than the looser
  # `scope`, because a review state means something only for the commit it
  # names. That keeps the exact-HEAD guarantee the whole skill rests on.
  local cr_substantive
  cr_substantive=$(snapshot_query '
    def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
    def chatter: test("summarize by coderabbit\\.ai|review in progress|processing new changes|no new commits to review"; "i");
    def verdict_state: (.state // "") | ascii_upcase | . == "APPROVED" or . == "CHANGES_REQUESTED";
    any(.[];
      .login == "coderabbitai[bot]" and
      (
        (
          scope and
          ((.body // "") | length > 0) and
          ((.surface == "inline") or (.surface == "review" and (((.body // "") | chatter) | not)))
        )
        or
        (.surface == "review" and .commit == $sha and verdict_state)
      )
    )')

  if [[ $cr_substantive == true ]]; then CR_STATUS="responded"
  elif [[ $cr_unavailable == true ]]; then CR_STATUS="unavailable"
  else CR_STATUS="in-progress"
  fi

  # On a fix-only push, CodeRabbit confirms in-thread and answers a forced
  # re-review with "Review finished"; it never re-posts a review body for a
  # commit it already processed incrementally. Treat that as terminal instead
  # of grinding the full wait budget to timeout. Cycle-1 strictness is kept:
  # this branch only runs with --re-review-cycle.
  if [[ $RE_REVIEW -eq 1 && $CR_STATUS == in-progress ]]; then
    local cr_at_head
    cr_at_head=$(snapshot_query '
      def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
      any(.[]; .login == "coderabbitai[bot]" and (
        (.surface == "review" and .commit == $sha) or
        (scope and ((.body // "") | test("no new commits to review|review finished"; "i")))
      ))')
    if [[ $cr_at_head == true && $UNRESOLVED_CR_THREADS == 0 ]]; then
      CR_STATUS="confirmed_no_new_findings"
    fi
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

  elapsed=$(( $(date +%s) - STARTED_EPOCH ))
  if ((elapsed >= TAG_AFTER)) && ((TAGGED_CODERABBIT == 0)) \
    && [[ $CR_STATUS == in-progress && $CR_SEEN == false ]]; then
    emit "needs_tag" "tag CodeRabbit once, then restart the waiter with --tagged-coderabbit" '["coderabbit"]'
    exit 0
  fi

  if [[ $CR_STATUS == confirmed_no_new_findings ]] && [[ $CHECKS_STATUS == ready ]]; then
    emit "confirmed_no_new_findings" "CodeRabbit confirmed the pushed fixes at the new HEAD with zero unresolved CodeRabbit threads; it will not re-post a review body for an already-reviewed commit" '[]'
    exit 0
  fi

  if [[ $CR_STATUS == responded || $CR_STATUS == unavailable ]] && [[ $CHECKS_STATUS == ready ]]; then
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
