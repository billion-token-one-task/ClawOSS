#!/usr/bin/env bash
set -euo pipefail

echo "=== Stopping ClawOSS ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"
. "$SCRIPT_DIR/lib/runtime-status.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"

# Remove ClawOSS cron jobs (don't stop the gateway — other agents may be running)
echo "Removing ClawOSS cron jobs..."
while IFS= read -r job_id; do
    openclaw cron rm "$job_id" 2>/dev/null && echo "  Removed cron: $job_id" || true
done < <(jq -r '.[].id' "$PROJECT_DIR/config/cron-jobs.json")

# Stop PR ledger sync
PLIST="$HOME/Library/LaunchAgents/com.clawoss.pr-ledger-sync.plist"
if clawoss_is_macos && [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" 2>/dev/null && echo "  Stopped PR ledger sync" || true
fi

# Stop dashboard sync
pkill -f "dashboard-sync" 2>/dev/null && echo "  Stopped dashboard sync" || true
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files | grep -q '^clawoss-run-cycle.service'; then
  systemctl --user stop clawoss-run-cycle.service 2>/dev/null && echo "  Stopped run-cycle controller" || true
else
  pkill -f "scripts/run-cycle.sh" 2>/dev/null && echo "  Stopped run-cycle controller" || true
fi

if openclaw gateway status 2>/dev/null | grep -q "running\|reachable"; then
  GATEWAY_STATE="running"
else
  GATEWAY_STATE="stopped"
fi
clawoss_write_runtime_status \
  "$WORKSPACE_DIR" \
  "stopped" \
  "$GATEWAY_STATE" \
  "stopped" \
  "stopped" \
  "true" \
  "true" \
  "unknown" \
  "ClawOSS stopped; gateway may remain running" \
  "stop.sh"

echo "ClawOSS stopped."
echo "Note: Gateway left running (other agents may depend on it)."
echo "To stop the gateway entirely: openclaw gateway stop"
