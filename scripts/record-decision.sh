#!/usr/bin/env bash
set -euo pipefail

STAGE="${1:?Usage: record-decision.sh <stage> [--repo owner/repo] [--issue N] [--pr N] [--selected true|false] ...}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
STRATEGY_FILE="$WORKSPACE_DIR/strategy/current.json"

REPO=""
ISSUE_NUMBER=""
PR_NUMBER=""
SELECTED="false"
SCORE=""
CONFIDENCE=""
EXPECTED_MERGE_PROB=""
EXPECTED_TOKEN_COST=""
REASONING_SUMMARY=""
CANDIDATE_SET_JSON="null"
METADATA_JSON="null"
SESSION_ID="${CLAWOSS_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
STRATEGY_VERSION=""

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE_NUMBER="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --selected) SELECTED="$2"; shift 2 ;;
    --score) SCORE="$2"; shift 2 ;;
    --confidence) CONFIDENCE="$2"; shift 2 ;;
    --expected-merge-prob) EXPECTED_MERGE_PROB="$2"; shift 2 ;;
    --expected-token-cost) EXPECTED_TOKEN_COST="$2"; shift 2 ;;
    --reasoning-summary) REASONING_SUMMARY="$2"; shift 2 ;;
    --candidate-set-json) CANDIDATE_SET_JSON="$2"; shift 2 ;;
    --metadata-json) METADATA_JSON="$2"; shift 2 ;;
    --session-id) SESSION_ID="$2"; shift 2 ;;
    --strategy-version) STRATEGY_VERSION="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$STRATEGY_VERSION" ] && [ -f "$STRATEGY_FILE" ]; then
  STRATEGY_VERSION=$(jq -r '.version // empty' "$STRATEGY_FILE" 2>/dev/null || true)
fi

PAYLOAD=$(jq -n \
  --arg stage "$STAGE" \
  --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg sessionId "$SESSION_ID" \
  --arg strategyVersion "$STRATEGY_VERSION" \
  --arg repo "$REPO" \
  --arg issueNumber "$ISSUE_NUMBER" \
  --arg prNumber "$PR_NUMBER" \
  --arg selected "$SELECTED" \
  --arg score "$SCORE" \
  --arg confidence "$CONFIDENCE" \
  --arg expectedMergeProb "$EXPECTED_MERGE_PROB" \
  --arg expectedTokenCost "$EXPECTED_TOKEN_COST" \
  --arg reasoningSummary "$REASONING_SUMMARY" \
  --argjson candidateSet "$CANDIDATE_SET_JSON" \
  --argjson metadata "$METADATA_JSON" \
  '{
    timestamp: $timestamp,
    stage: $stage,
    sessionId: ($sessionId | if . == "" then null else . end),
    strategyVersion: ($strategyVersion | if . == "" then null else . end),
    repo: ($repo | if . == "" then null else . end),
    issueNumber: ($issueNumber | if . == "" then null else (. | tonumber) end),
    prNumber: ($prNumber | if . == "" then null else (. | tonumber) end),
    selected: ($selected == "true"),
    score: ($score | if . == "" then null else (. | tonumber) end),
    confidence: ($confidence | if . == "" then null else (. | tonumber) end),
    expectedMergeProb: ($expectedMergeProb | if . == "" then null else (. | tonumber) end),
    expectedTokenCost: ($expectedTokenCost | if . == "" then null else (. | tonumber) end),
    reasoningSummary: ($reasoningSummary | if . == "" then null else . end),
    candidateSet: $candidateSet,
    metadata: $metadata
  }')

printf '%s\n' "$PAYLOAD" | bash "$SCRIPT_DIR/spool-json-event.sh" runtime/decisions >/dev/null
