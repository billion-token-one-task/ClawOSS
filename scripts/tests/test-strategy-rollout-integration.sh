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
cp "$ROOT/workspace/strategy/current.json" "$TEST_PROJECT/workspace/strategy/current.json"

cat > "$TEST_PROJECT/workspace/reflections/daily/reflection-test.json" <<'EOF'
{
  "id": "reflection-test",
  "timestamp": "2026-03-31T08:00:00.000Z",
  "scope": "daily",
  "summary": "recent rejected attempts outnumber reviewed outcomes",
  "recommendedChanges": [
    {
      "scope": "targeting",
      "change": "raise the minimum expected merge probability before high-effort execution",
      "rationale": "recent rejected or abandoned attempts outnumber reviewed-or-merged outcomes"
    },
    {
      "scope": "followup",
      "change": "prefer smaller or previously trusted tasks until review responsiveness improves",
      "rationale": "selected work exists but the latest window produced no reviewed or merged outcomes"
    }
  ]
}
EOF

RUN_ONCE=1 \
GENERATE_REFLECTIONS=0 \
GENERATE_STRATEGY_PROPOSALS=1 \
WORKSPACE_DIR="$TEST_PROJECT/workspace" \
MOCK_API_SINK_DIR="$SINK_DIR" \
node "$ROOT/services/reflection/index.mjs" >/dev/null

PROPOSAL_HISTORY="$(ls "$TEST_PROJECT/workspace/strategy/history/"*.json)"
PROPOSAL_PROCESSED="$(ls "$TEST_PROJECT/workspace/strategy/processed/"*.json)"
PROPOSAL_SINK="$(ls "$SINK_DIR/"*strategy-version*.json)"
[ -f "$PROPOSAL_HISTORY" ]
[ -f "$PROPOSAL_PROCESSED" ]
[ -f "$PROPOSAL_SINK" ]

cat "$PROPOSAL_HISTORY" | jq -e '.status == "draft"' >/dev/null
cat "$PROPOSAL_HISTORY" | jq -e '.metadata.generatedBy == "strategy_rollout_mvp"' >/dev/null
cat "$PROPOSAL_HISTORY" | jq -e '.evaluation.sourceReflectionId == "reflection-test"' >/dev/null
cat "$PROPOSAL_HISTORY" | jq -e '.config.rollout.mode == "canary"' >/dev/null
cat "$PROPOSAL_HISTORY" | jq -e '.config.budget.min_expected_merge_prob == 0.35' >/dev/null

echo "Strategy rollout proposal path is runnable."
