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

Options:
  --base BRANCH                 Base branch (default: main)
  --interval SECONDS            Poll interval (default: 50)
  --timeout SECONDS             Total wait budget (default: 900)
  --tag-after SECONDS           Missing-bot fallback delay (default: 60)
  --once                        Probe once without sleeping
  --tagged-coderabbit           CodeRabbit fallback tag was already posted
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

for command in gh jq mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'required command not found: %s — stop the review, do not work around it\n' "$command" >&2
    exit 2
  fi
done

# Fail fast instead of spending the whole wait budget on calls that cannot work.
if ! gh auth status >/dev/null 2>&1; then
  printf 'gh is not authenticated — stop the review and run `gh auth login`\n' >&2
  exit 2
fi

if ! gh api "repos/$OWNER/$REPO" --jq .full_name >/dev/null 2>&1; then
  printf 'cannot read %s/%s with the current gh credentials — stop the review\n' "$OWNER" "$REPO" >&2
  exit 2
fi

SHORT_SHA=${HEAD_SHA:0:9}
REPOSITORY="$OWNER/$REPO"
BASE_PATH=$(jq -rn --arg value "$BASE" '$value | @uri')
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/review-pr-watch.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

SNAPSHOT="$WORK_DIR/snapshot.json"
PR_STATE="$WORK_DIR/pr-state.json"
RULES="$WORK_DIR/rules.json"

printf '[]\n' >"$SNAPSHOT"
printf '{}\n' >"$PR_STATE"
printf '[]\n' >"$RULES"

STARTED_EPOCH=$(date +%s)

CR_STATUS="in-progress"
CHECKS_STATUS="pending"
CR_SEEN=false
PENDING_CHECKS='[]'
FAILED_CHECKS='[]'

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
      failed_checks: $failed_checks
    }'
}

fetch_snapshot() {
  local next="$WORK_DIR/snapshot.next.json"
  local issues="$WORK_DIR/issues.next.jsonl"
  local reviews="$WORK_DIR/reviews.next.jsonl"
  local comments="$WORK_DIR/comments.next.jsonl"

  if ! gh api --paginate "repos/$OWNER/$REPO/issues/$PR/comments" \
      --jq '.[] | {surface:"issue",login:.user.login,id,ts:.created_at,commit:"",path:null,line:null,url:.html_url,body}' >"$issues" 2>/dev/null; then
    rm -f "$issues"
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
  fi

  if gh api --paginate "repos/$OWNER/$REPO/pulls/$PR/reviews" \
      --jq '.[] | {surface:"review",login:.user.login,id,ts:.submitted_at,commit:.commit_id,path:null,line:null,url:.html_url,body}' >"$reviews" 2>/dev/null \
    && gh api --paginate "repos/$OWNER/$REPO/pulls/$PR/comments" \
      --jq '.[] | {surface:"inline",login:.user.login,id,ts:.created_at,commit:(.original_commit_id // .commit_id),path,line,url:.html_url,body}' >"$comments" 2>/dev/null \
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

fetch_rules() {
  local required_checks="$WORK_DIR/required-checks.next.json"
  local next="$RULES.next"

  if fetch_json "$RULES" gh api "repos/$OWNER/$REPO/rules/branches/$BASE_PATH"; then
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
  local cr_substantive
  cr_substantive=$(snapshot_query '
    def scope: (.commit == $sha) or ((.ts // "") >= $review_start) or ((.ts // "") >= $commit_date) or ((.body // "") | contains($sha) or contains($short));
    def chatter: test("summarize by coderabbit\\.ai|review in progress|processing new changes|no new commits to review"; "i");
    any(.[];
      .login == "coderabbitai[bot]" and scope and
      ((.body // "") | length > 0) and
      ((.surface == "inline") or (.surface == "review" and (((.body // "") | chatter) | not)))
    )')

  if [[ $cr_substantive == true ]]; then CR_STATUS="responded"
  elif [[ $cr_unavailable == true ]]; then CR_STATUS="unavailable"
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
  fetch_json "$PR_STATE" gh pr view "$PR" --repo "$REPOSITORY" \
    --json statusCheckRollup || failed=1
  fetch_rules || failed=1

  if ((failed)); then return 1; fi
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
