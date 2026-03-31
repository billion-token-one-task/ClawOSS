#!/usr/bin/env bash
set -euo pipefail

QUEUE_FILE="${1:?Usage: record-queue-pick.sh <queue-file.md> <owner/repo> <issue> [--stage stage] [--selected true|false] [--reasoning-summary text] [--metadata-json json]}"
REPO="${2:?Usage: record-queue-pick.sh <queue-file.md> <owner/repo> <issue>}"
ISSUE="${3:?Usage: record-queue-pick.sh <queue-file.md> <owner/repo> <issue>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

STAGE="pick_new_work"
SELECTED="true"
REASONING_SUMMARY="selected from queue"
METADATA_JSON="null"

shift 3
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="$2"; shift 2 ;;
    --selected) SELECTED="$2"; shift 2 ;;
    --reasoning-summary) REASONING_SUMMARY="$2"; shift 2 ;;
    --metadata-json) METADATA_JSON="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

CANDIDATE_SET_JSON=$(bash "$SCRIPT_DIR/queue-candidates-to-json.sh" "$QUEUE_FILE")
SELECTED_ROW=$(printf '%s\n' "$CANDIDATE_SET_JSON" | jq --arg repo "$REPO" --argjson issue "$ISSUE" -c '.[] | select(.repo == $repo and .issue == $issue)' | head -n 1)

SCORE=""
EXPECTED_MERGE_PROB=""

if [ -n "$SELECTED_ROW" ]; then
  SCORE=$(printf '%s\n' "$SELECTED_ROW" | jq -r '.score // empty')
  EXPECTED_MERGE_PROB=$(printf '%s\n' "$SELECTED_ROW" | jq -r '.expectedMergeProb // empty')
fi

cmd=(
  bash "$SCRIPT_DIR/record-decision.sh" "$STAGE"
  --repo "$REPO"
  --issue "$ISSUE"
  --selected "$SELECTED"
  --reasoning-summary "$REASONING_SUMMARY"
  --candidate-set-json "$CANDIDATE_SET_JSON"
  --metadata-json "$METADATA_JSON"
)

[ -n "$SCORE" ] && cmd+=(--score "$SCORE")
[ -n "$EXPECTED_MERGE_PROB" ] && cmd+=(--expected-merge-prob "$EXPECTED_MERGE_PROB")

"${cmd[@]}"
