#!/usr/bin/env bash
set -euo pipefail

echo "=== ClawOSS Health Check ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"

# Check gateway
if openclaw gateway status 2>/dev/null | grep -q "running\|reachable"; then
    echo "[OK] Gateway is running"
else
    echo "[FAIL] Gateway is not running"
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
else
    echo "[FAIL] Workspace not linked"
fi

if bash "$SCRIPT_DIR/init-workspace-state.sh" >/dev/null 2>&1; then
    echo "[OK] Workspace state initialized"
else
    echo "[FAIL] Workspace state initialization failed"
fi

# Check clawoss agent
if openclaw agents list 2>/dev/null | grep -q "clawoss"; then
    echo "[OK] Agent 'clawoss' registered"
else
    echo "[FAIL] Agent 'clawoss' not registered"
fi

# Check cron jobs
CRON_COUNT=$(openclaw cron list 2>/dev/null | grep -c "clawoss" || true)
EXPECTED_CRONS=$(jq 'length' "$PROJECT_DIR/config/cron-jobs.json" 2>/dev/null || echo 0)
echo "[INFO] $CRON_COUNT cron jobs registered for clawoss (configured: $EXPECTED_CRONS)"

echo ""
echo "=== Health Check Complete ==="
