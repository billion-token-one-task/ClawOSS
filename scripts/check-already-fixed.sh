#!/usr/bin/env bash
# check-already-fixed.sh — Check if an issue has already been resolved
# Usage: check-already-fixed.sh <owner/repo> <issue_number>
# Exit 0 = not fixed (safe to work on), Exit 1 = already fixed

REPO="${1:?Usage: check-already-fixed.sh <owner/repo> <issue_number>}"
ISSUE="${2:?Usage: check-already-fixed.sh <owner/repo> <issue_number>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECORD_DECISIONS="${CLAWOSS_RECORD_DECISIONS:-0}"
. "$SCRIPT_DIR/lib/github-rate-limit.sh"

# 1. Is the issue closed?
ISSUE_STATE=$(gh_cached_api 900 "repos/${REPO}/issues/${ISSUE}" --jq '.state' 2>/dev/null)
if [ -z "$ISSUE_STATE" ]; then
  echo "{\"fixed\": false, \"repo\": \"$REPO\", \"issue\": $ISSUE, \"error\": \"api_failed\"}"
  exit 0
fi
if [ "$ISSUE_STATE" = "closed" ]; then
  if [ "$RECORD_DECISIONS" = "1" ]; then
    bash "$SCRIPT_DIR/record-decision.sh" issue_guardrail \
      --repo "$REPO" \
      --issue "$ISSUE" \
      --selected false \
      --reasoning-summary "issue is closed" \
      --metadata-json '{"reason":"issue_closed"}' >/dev/null 2>&1 || true
  fi
  echo "{\"fixed\": true, \"repo\": \"$REPO\", \"issue\": $ISSUE, \"reason\": \"issue is closed\"}"
  exit 1
fi

# 2. Recently merged PRs referencing this issue
MERGED_REFS=$(gh_cached_search_prs 1800 --repo "$REPO" "is:merged" --limit 15 --json title,body,number --jq "[.[] | select((.title // \"\") + (.body // \"\") | test(\"#${ISSUE}\"; \"i\"))] | length" 2>/dev/null || true)
MERGED_REFS=${MERGED_REFS:-0}
if [ "$MERGED_REFS" -gt 0 ]; then
  if [ "$RECORD_DECISIONS" = "1" ]; then
    bash "$SCRIPT_DIR/record-decision.sh" issue_guardrail \
      --repo "$REPO" \
      --issue "$ISSUE" \
      --selected false \
      --reasoning-summary "${MERGED_REFS} recently merged PR(s) reference this issue" \
      --metadata-json '{"reason":"already_fixed_upstream"}' >/dev/null 2>&1 || true
  fi
  echo "{\"fixed\": true, \"repo\": \"$REPO\", \"issue\": $ISSUE, \"reason\": \"${MERGED_REFS} recently merged PR(s) reference this issue\"}"
  exit 1
fi

# 3. Recent commits with fix keywords
RECENT_FIX=$(gh_cached_api 1800 "repos/${REPO}/commits?per_page=20" --jq "[.[] | select(.commit.message | test(\"fix.*#${ISSUE}|close.*#${ISSUE}|resolve.*#${ISSUE}\"; \"i\"))] | length" 2>/dev/null || true)
RECENT_FIX=${RECENT_FIX:-0}
if [ "$RECENT_FIX" -gt 0 ]; then
  if [ "$RECORD_DECISIONS" = "1" ]; then
    bash "$SCRIPT_DIR/record-decision.sh" issue_guardrail \
      --repo "$REPO" \
      --issue "$ISSUE" \
      --selected false \
      --reasoning-summary "${RECENT_FIX} recent commit(s) fix this issue" \
      --metadata-json '{"reason":"recent_fix_commit"}' >/dev/null 2>&1 || true
  fi
  echo "{\"fixed\": true, \"repo\": \"$REPO\", \"issue\": $ISSUE, \"reason\": \"${RECENT_FIX} recent commit(s) fix this issue\"}"
  exit 1
fi

echo "{\"fixed\": false, \"repo\": \"$REPO\", \"issue\": $ISSUE}"
exit 0
