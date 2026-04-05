#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_PROJECT="$(mktemp -d)"
SINK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_PROJECT"
  rm -rf "$SINK_DIR"
}
trap cleanup EXIT

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/init-workspace-state.sh" >/dev/null

DECISION_TS="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(hours=2)).isoformat().replace("+00:00", "Z"))
PY
)"

OUTCOME_TS="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(hours=1)).isoformat().replace("+00:00", "Z"))
PY
)"

cat > "$TEST_PROJECT/workspace/runtime/processed/decisions/decision-1.json" <<EOF
{
  "id": "decision-1",
  "timestamp": "$DECISION_TS",
  "stage": "queue_pick",
  "repo": "example/project",
  "issueNumber": 12,
  "selected": true,
  "score": 0.82,
  "expectedMergeProb": 0.71,
  "expectedTokenCost": 120000
}
EOF

cat > "$TEST_PROJECT/workspace/runtime/processed/outcomes/outcome-1.json" <<EOF
{
  "id": "outcome-1",
  "timestamp": "$OUTCOME_TS",
  "repo": "example/project",
  "issueNumber": 12,
  "outcome": "reviewed",
  "tokenCost": 18.5,
  "inputTokens": 1200,
  "outputTokens": 300
}
EOF

RUN_ONCE=1 \
GENERATE_REFLECTIONS=1 \
REFLECTION_WINDOW_HOURS=72 \
WORKSPACE_DIR="$TEST_PROJECT/workspace" \
MOCK_API_SINK_DIR="$SINK_DIR" \
node "$ROOT/services/reflection/index.mjs" >/dev/null

REFLECTION_ARTIFACT="$(ls "$TEST_PROJECT/workspace/reflections/daily/"*.json)"
REFLECTION_PROCESSED="$(ls "$TEST_PROJECT/workspace/reflections/processed/"*.json)"
REFLECTION_SINK="$(ls "$SINK_DIR/"*.json)"
[ -f "$REFLECTION_ARTIFACT" ]
[ -f "$REFLECTION_PROCESSED" ]
[ -f "$REFLECTION_SINK" ]

cat "$REFLECTION_SINK" | jq -e '.metadata.generatedBy == "reflection_mvp"' >/dev/null

cat "$REFLECTION_ARTIFACT" | jq -e '.scope == "daily"' >/dev/null
cat "$REFLECTION_ARTIFACT" | jq -e '.metadata.decisionsSummary.selected == 1' >/dev/null
cat "$REFLECTION_ARTIFACT" | jq -e '.metadata.outcomesSummary.counts.reviewed == 1' >/dev/null

echo "Reflection integration path is runnable."
