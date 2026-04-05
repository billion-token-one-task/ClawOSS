#!/usr/bin/env bash
set -euo pipefail

echo "=== ClawOSS Health Check ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"
. "$SCRIPT_DIR/lib/runtime-status.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
GATEWAY_STATE="stopped"
RUN_CYCLE_STATE="stopped"
HEALTH_STATE="pass"
AGENT_REGISTERED="false"
WORKSPACE_LINKED="false"

# Check gateway
if openclaw gateway status 2>/dev/null | grep -q "running\|reachable"; then
    echo "[OK] Gateway is running"
    GATEWAY_STATE="running"
else
    echo "[FAIL] Gateway is not running"
    HEALTH_STATE="fail"
    clawoss_write_runtime_status "$WORKSPACE_DIR" "error" "$GATEWAY_STATE" "unknown" "$RUN_CYCLE_STATE" "$AGENT_REGISTERED" "$WORKSPACE_LINKED" "$HEALTH_STATE" "Health check failed: gateway not running" "health-check.sh"
    exit 1
fi

# Check gh auth
if gh auth status 2>/dev/null; then
    echo "[OK] GitHub CLI authenticated"
else
    echo "[FAIL] GitHub CLI not authenticated"
fi

# Check workspace
if [ -L "$HOME/.openclaw/workspace" ]; then
    echo "[OK] Workspace linked"
    WORKSPACE_LINKED="true"
else
    echo "[FAIL] Workspace not linked"
    HEALTH_STATE="fail"
fi

if bash "$SCRIPT_DIR/init-workspace-state.sh" >/dev/null 2>&1; then
    echo "[OK] Workspace state initialized"
else
    echo "[FAIL] Workspace state initialization failed"
fi

# Check run-cycle controller
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet clawoss-run-cycle.service; then
    echo "[OK] Run-cycle controller is running"
    RUN_CYCLE_STATE="running"
elif pgrep -f "scripts/run-cycle.sh" >/dev/null 2>&1; then
    echo "[OK] Run-cycle controller is running"
    RUN_CYCLE_STATE="running"
else
    echo "[FAIL] Run-cycle controller is not running"
    HEALTH_STATE="fail"
fi

# Check clawoss agent
if openclaw agents list 2>/dev/null | grep -q "clawoss"; then
    echo "[OK] Agent 'clawoss' registered"
    AGENT_REGISTERED="true"
else
    echo "[FAIL] Agent 'clawoss' not registered"
    HEALTH_STATE="fail"
fi

# Check cron jobs
CRON_COUNT=$(openclaw cron list 2>/dev/null | grep -c "clawoss" || true)
EXPECTED_CRONS=$(jq 'length' "$PROJECT_DIR/config/cron-jobs.json" 2>/dev/null || echo 0)
echo "[INFO] $CRON_COUNT cron jobs registered for clawoss (configured: $EXPECTED_CRONS)"

OVERALL_STATE="running"
if [ "$HEALTH_STATE" != "pass" ]; then
    OVERALL_STATE="degraded"
fi
clawoss_write_runtime_status "$WORKSPACE_DIR" "$OVERALL_STATE" "$GATEWAY_STATE" "unknown" "$RUN_CYCLE_STATE" "$AGENT_REGISTERED" "$WORKSPACE_LINKED" "$HEALTH_STATE" "Health check completed" "health-check.sh"

echo ""
echo "=== Health Check Complete ==="
