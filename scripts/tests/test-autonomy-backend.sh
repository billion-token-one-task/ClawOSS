#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_PROJECT="$(mktemp -d)"
trap 'rm -rf "$TEST_PROJECT"' EXIT

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/init-workspace-state.sh" >/dev/null

DECISION_FILE=$(printf '%s\n' '{"type":"repo_select","repo":"example/project","selected":true}' | PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/spool-json-event.sh" runtime/decisions)
[ -f "$DECISION_FILE" ]
cat "$DECISION_FILE" | jq . >/dev/null

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/record-decision.sh" repo_health_gate --repo example/project --selected true --score 8 >/dev/null
ls "$TEST_PROJECT/workspace/runtime/decisions"/*.json >/dev/null

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/record-outcome.sh" pr_submitted --id deterministic-pr --repo example/project --issue 12 --pr 34 >/dev/null
[ -f "$TEST_PROJECT/workspace/runtime/outcomes/deterministic-pr.json" ]

cat > "$TEST_PROJECT/workspace/memory/work-queue-staging.md" <<'EOF'
- [11] P(78) example/project#12: Fix flaky parser | type:bug | created:2026-03-30 | direction_aligned:yes | priority:high
- [7] P(44) example/other#55: Update docs typo | type:docs | created:2026-03-28 | direction_aligned:yes | priority:normal
EOF
PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/record-queue-pick.sh" "$TEST_PROJECT/workspace/memory/work-queue-staging.md" example/project 12 >/dev/null
ls "$TEST_PROJECT/workspace/runtime/decisions"/*.json >/dev/null

REFLECTION_FILE=$(printf '%s\n' '{"scope":"daily","summary":"test reflection","confidence":0.9}' | PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/spool-json-event.sh" reflections/outbox)
[ -f "$REFLECTION_FILE" ]
cat "$REFLECTION_FILE" | jq . >/dev/null

cat > "$TEST_PROJECT/workspace/reflections/daily/reflection-test.json" <<'EOF'
{
  "id": "reflection-test",
  "scope": "daily",
  "summary": "test reflection",
  "recommendedChanges": [
    {
      "scope": "targeting",
      "change": "raise the minimum expected merge probability before high-effort execution",
      "rationale": "negative outcomes exceed reviewed outcomes"
    }
  ]
}
EOF

RUN_ONCE=1 WORKSPACE_DIR="$TEST_PROJECT/workspace" API_BASE_URL="http://127.0.0.1:9" node "$ROOT/services/worker/index.mjs" >/dev/null
RUN_ONCE=1 WORKSPACE_DIR="$TEST_PROJECT/workspace" API_BASE_URL="http://127.0.0.1:9" node "$ROOT/services/reflection/index.mjs" >/dev/null

ls "$TEST_PROJECT/workspace/strategy/history/"*.json >/dev/null

echo "Autonomy backend skeleton scripts are runnable."
