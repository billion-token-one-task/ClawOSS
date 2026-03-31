#!/usr/bin/env bash
set -euo pipefail

OUTCOME="${1:?Usage: record-outcome.sh <outcome> [--id ID] [--repo owner/repo] ...}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
STRATEGY_FILE="$WORKSPACE_DIR/strategy/current.json"
RUNTIME_DIR="$WORKSPACE_DIR/runtime/outcomes"
PROCESSED_DIR="$WORKSPACE_DIR/runtime/processed/outcomes"

EVENT_ID=""
DECISION_ID=""
REPO=""
ISSUE_NUMBER=""
PR_NUMBER=""
TIME_TO_FIRST_REVIEW_HOURS=""
TIME_TO_MERGE_HOURS=""
TOKEN_COST=""
INPUT_TOKENS=""
OUTPUT_TOKENS=""
FAILURE_CATEGORY=""
METADATA_JSON="null"
SESSION_ID="${CLAWOSS_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
STRATEGY_VERSION=""

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --id) EVENT_ID="$2"; shift 2 ;;
    --decision-id) DECISION_ID="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE_NUMBER="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --time-to-first-review-hours) TIME_TO_FIRST_REVIEW_HOURS="$2"; shift 2 ;;
    --time-to-merge-hours) TIME_TO_MERGE_HOURS="$2"; shift 2 ;;
    --token-cost) TOKEN_COST="$2"; shift 2 ;;
    --input-tokens) INPUT_TOKENS="$2"; shift 2 ;;
    --output-tokens) OUTPUT_TOKENS="$2"; shift 2 ;;
    --failure-category) FAILURE_CATEGORY="$2"; shift 2 ;;
    --metadata-json) METADATA_JSON="$2"; shift 2 ;;
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --strategy-version) STRATEGY_VERSION="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$EVENT_ID" ]; then
  mkdir -p "$RUNTIME_DIR" "$PROCESSED_DIR"
  if [ -f "$RUNTIME_DIR/${EVENT_ID}.json" ] || [ -f "$PROCESSED_DIR/${EVENT_ID}.json" ]; then
    exit 0
  fi
fi

if [ -z "$STRATEGY_VERSION" ] && [ -f "$STRATEGY_FILE" ]; then
  STRATEGY_VERSION=$(jq -r '.version // empty' "$STRATEGY_FILE" 2>/dev/null || true)
fi

PAYLOAD=$(jq -n \
  --arg id "$EVENT_ID" \
  --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg sessionId "$SESSION_ID" \
  --arg decisionId "$DECISION_ID" \
  --arg strategyVersion "$STRATEGY_VERSION" \
  --arg repo "$REPO" \
  --arg issueNumber "$ISSUE_NUMBER" \
  --arg prNumber "$PR_NUMBER" \
  --arg outcome "$OUTCOME" \
  --arg timeToFirstReviewHours "$TIME_TO_FIRST_REVIEW_HOURS" \
  --arg timeToMergeHours "$TIME_TO_MERGE_HOURS" \
  --arg tokenCost "$TOKEN_COST" \
  --arg inputTokens "$INPUT_TOKENS" \
  --arg outputTokens "$OUTPUT_TOKENS" \
  --arg failureCategory "$FAILURE_CATEGORY" \
  --argjson metadata "$METADATA_JSON" \
  '{
    id: ($id | if . == "" then null else . end),
    timestamp: $timestamp,
    sessionId: ($sessionId | if . == "" then null else . end),
    decisionId: ($decisionId | if . == "" then null else . end),
    strategyVersion: ($strategyVersion | if . == "" then null else . end),
    repo: ($repo | if . == "" then null else . end),
    issueNumber: ($issueNumber | if . == "" then null else (. | tonumber) end),
    prNumber: ($prNumber | if . == "" then null else (. | tonumber) end),
    outcome: $outcome,
    timeToFirstReviewHours: ($timeToFirstReviewHours | if . == "" then null else (. | tonumber) end),
    timeToMergeHours: ($timeToMergeHours | if . == "" then null else (. | tonumber) end),
    tokenCost: ($tokenCost | if . == "" then null else (. | tonumber) end),
    inputTokens: ($inputTokens | if . == "" then null else (. | tonumber) end),
    outputTokens: ($outputTokens | if . == "" then null else (. | tonumber) end),
    failureCategory: ($failureCategory | if . == "" then null else . end),
    metadata: $metadata
  }')

OUTFILE=$(printf '%s\n' "$PAYLOAD" | bash "$SCRIPT_DIR/spool-json-event.sh" runtime/outcomes)

if [ -n "$EVENT_ID" ]; then
  mv "$OUTFILE" "$RUNTIME_DIR/${EVENT_ID}.json"
fi
