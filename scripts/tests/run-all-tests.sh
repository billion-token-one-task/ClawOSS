#!/usr/bin/env bash
# run-all-tests.sh — Test suite for ClawOSS scripts
# Usage: bash scripts/tests/run-all-tests.sh

set +e

SCRIPTS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0; TOTAL=0
TEST_PROJECT="$(mktemp -d)"
trap 'rm -rf "$TEST_PROJECT"' EXIT

mkdir -p "$TEST_PROJECT/workspace/memory"
cat > "$TEST_PROJECT/workspace/memory/trust-repos.md" <<'EOF'
# Trust Repos

## Active
| Repo | Score | Notes |
|------|-------|-------|

## Deprioritized
| Repo | Reason | Skip Until |
|------|--------|------------|
| `run-llama/llama_index` | hostile maintainer | permanent |
EOF

bash "$SCRIPTS_DIR/init-workspace-state.sh" >/dev/null 2>&1

run_test() {
  local name="$1" cmd="$2" expect_exit="$3" expect_json="${4:-false}"
  TOTAL=$((TOTAL + 1))
  echo -n "  [$TOTAL] $name... "
  
  OUTPUT=$(eval "$cmd" 2>&1)
  EXIT=$?
  
  if [ "$expect_exit" = "any" ] || [ "$EXIT" -eq "$expect_exit" ]; then
    if [ "$expect_json" = "true" ]; then
      echo "$OUTPUT" | jq . >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "PASS (exit=$EXIT, valid JSON)"
        PASS=$((PASS + 1))
      else
        echo "FAIL (exit=$EXIT ok, but invalid JSON)"
        FAIL=$((FAIL + 1))
      fi
    else
      echo "PASS (exit=$EXIT)"
      PASS=$((PASS + 1))
    fi
  else
    echo "FAIL (expected exit=$expect_exit, got exit=$EXIT)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== ClawOSS Script Test Suite ==="
echo ""

echo "mission config:"
run_test "mission.json matches required contract" "bash $SCRIPTS_DIR/tests/test-mission-config.sh" 0
echo "verify result:"
run_test "gate verification is deterministic" "bash $SCRIPTS_DIR/tests/test-verify-result.sh" 0
echo "build prompt:"
run_test "prompt builder scopes context correctly" "bash $SCRIPTS_DIR/tests/test-build-prompt.sh" 0
echo "run cycle:"
run_test "main loop state machine and recovery are deterministic" "bash $SCRIPTS_DIR/tests/test-run-cycle.sh" 0
echo "refactor surface:"
run_test "static architecture files match the refactor spec" "bash $SCRIPTS_DIR/tests/test-refactor-surface.sh" 0

# ── check-blocklist.sh ──
echo "check-blocklist.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/check-blocklist.sh 2>&1" 1
run_test "known blocked repo (llama_index)" "PROJECT_DIR=$TEST_PROJECT bash $SCRIPTS_DIR/check-blocklist.sh run-llama/llama_index" 1 true
run_test "known safe repo" "bash $SCRIPTS_DIR/check-blocklist.sh ollama/ollama" 0 true

# ── check-already-fixed.sh ──
echo "check-already-fixed.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/check-already-fixed.sh 2>&1" 1

# ── check-supersession.sh ──
echo "check-supersession.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/check-supersession.sh 2>&1" 1

# ── pr-portfolio-stats.sh ──
echo "pr-portfolio-stats.sh:"
run_test "returns valid JSON" "bash $SCRIPTS_DIR/pr-portfolio-stats.sh" 0 true

# ── heartbeat-status.sh ──
echo "heartbeat-status.sh:"
run_test "returns valid JSON" "bash $SCRIPTS_DIR/heartbeat-status.sh" 0 true

# ── compute-merge-probability.sh ──
echo "compute-merge-probability.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/compute-merge-probability.sh 2>&1" 1

# ── lock-repo.sh / unlock-repo.sh ──
echo "lock-repo.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/lock-repo.sh 2>&1" 1
echo "unlock-repo.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/unlock-repo.sh 2>&1" 1

# ── init-workspace-state.sh ──
echo "init-workspace-state.sh:"
run_test "idempotent workspace bootstrap" "PROJECT_DIR=$TEST_PROJECT bash $SCRIPTS_DIR/init-workspace-state.sh" 0 true
run_test "creates lifecycle-state.json" "test -f $TEST_PROJECT/workspace/memory/lifecycle-state.json" 0
run_test "creates failure-log.md" "test -f $TEST_PROJECT/workspace/memory/failure-log.md" 0

# ── spool-json-event.sh ──
echo "spool-json-event.sh:"
run_test "writes valid decision event file" "PROJECT_DIR=$TEST_PROJECT bash $SCRIPTS_DIR/spool-json-event.sh runtime/decisions <<'EOF'
{\"type\":\"repo_select\",\"repo\":\"example/project\",\"selected\":true}
EOF" 0

# ── record-decision.sh / record-outcome.sh ──
echo "record-decision.sh:"
run_test "writes structured decision file" "PROJECT_DIR=$TEST_PROJECT bash $SCRIPTS_DIR/record-decision.sh repo_health_gate --repo example/project --selected true --score 9" 0
echo "record-outcome.sh:"
run_test "writes structured outcome file" "PROJECT_DIR=$TEST_PROJECT bash $SCRIPTS_DIR/record-outcome.sh pr_submitted --repo example/project --issue 12 --pr 34" 0

cat > "$TEST_PROJECT/workspace/memory/work-queue-staging.md" <<'EOF'
- [11] P(78) example/project#12: Fix flaky parser | type:bug | created:2026-03-30 | direction_aligned:yes | priority:high
- [7] P(44) example/other#55: Update docs typo | type:docs | created:2026-03-28 | direction_aligned:yes | priority:normal
EOF
echo "queue-candidates-to-json.sh:"
run_test "parses queue candidates to JSON" "bash $SCRIPTS_DIR/queue-candidates-to-json.sh $TEST_PROJECT/workspace/memory/work-queue-staging.md" 0 true
echo "record-queue-pick.sh:"
run_test "records queue pick with candidate set" "PROJECT_DIR=$TEST_PROJECT bash $SCRIPTS_DIR/record-queue-pick.sh $TEST_PROJECT/workspace/memory/work-queue-staging.md example/project 12 --reasoning-summary 'picked highest merge-probability candidate'" 0

echo "reflection integration:"
run_test "generates and forwards daily reflection" "bash $SCRIPTS_DIR/tests/test-reflection-integration.sh" 0
echo "strategy rollout integration:"
run_test "generates and forwards draft strategy proposal" "bash $SCRIPTS_DIR/tests/test-strategy-rollout-integration.sh" 0
echo "alpha lifecycle:"
run_test "alpha deploy/upgrade wrappers render safe dry-run plans" "bash $SCRIPTS_DIR/tests/test-alpha-lifecycle.sh" 0
echo "alpha gate:"
run_test "alpha human gate evaluates risky actions" "bash $SCRIPTS_DIR/tests/test-alpha-gate.sh" 0
echo "restart smoke:"
run_test "restart smoke mode is runnable in isolation" "bash $SCRIPTS_DIR/tests/test-restart-smoke.sh" 0

# ── format-pr-description.sh ──
echo "format-pr-description.sh:"
run_test "no args = usage error" "bash $SCRIPTS_DIR/format-pr-description.sh 2>&1" 1

echo ""
echo "=================================="
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "=================================="

[ "$FAIL" -gt 0 ] && exit 1 || exit 0
