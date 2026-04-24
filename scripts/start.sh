#!/usr/bin/env bash
set -euo pipefail

echo "=== Starting ClawOSS ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AGENT_ID="clawoss"
WORKSPACE_DIR="$PROJECT_DIR/workspace"
export CLAWOSS_PROJECT_DIR="${CLAWOSS_PROJECT_DIR:-$PROJECT_DIR}"
export CLAWOSS_WORKSPACE_DIR="${CLAWOSS_WORKSPACE_DIR:-$WORKSPACE_DIR}"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

if [ ! -L "$HOME/.openclaw/workspace" ]; then
    echo "Error: workspace not linked. Run 'npm run setup' first."
    exit 1
fi

DEPLOYED_CONFIG="$HOME/.openclaw/openclaw.json"
echo "部署 OpenClaw 配置..."
bash "$PROJECT_DIR/scripts/deploy-openclaw-config.sh"

PRIMARY_MODEL="$(node "$PROJECT_DIR/scripts/render-openclaw-config.mjs" --print-primary-model)"

if openclaw agents list 2>/dev/null | grep -q "^- $AGENT_ID "; then
    echo "Agent '$AGENT_ID' already registered"
else
    echo "Registering agent '$AGENT_ID'..."
    openclaw agents add "$AGENT_ID" \
        --workspace "$WORKSPACE_DIR" \
        --model "$PRIMARY_MODEL" \
        --non-interactive
    echo "Agent '$AGENT_ID' registered"
fi

echo "Registering cron jobs..."
EXISTING_CRONS=$(openclaw cron list --json 2>/dev/null | jq -r '.jobs[] | select(.agentId == "'"$AGENT_ID"'") | .name' 2>/dev/null || true)
while IFS= read -r job; do
    name=$(echo "$job" | jq -r '.id')
    schedule=$(echo "$job" | jq -r '.schedule.expr')
    payload=$(echo "$job" | jq -r '.payload.message // .payload.text // empty')

    if echo "$EXISTING_CRONS" | grep -q "^${name}$"; then
        echo "  Exists: $name"
        continue
    fi

    cmd=(openclaw cron add --name "$name" --agent "$AGENT_ID" --cron "$schedule")
    cmd+=(--session isolated --session-key "agent:${AGENT_ID}:${name}" --message "$payload")

    "${cmd[@]}" 2>/dev/null && echo "  Added: $name" || echo "  Failed: $name"
done < <(jq -c '.[]' "$PROJECT_DIR/config/cron-jobs.json")

if openclaw gateway status 2>/dev/null | grep -q "running\|reachable"; then
    echo "OpenClaw gateway already running - restarting to pick up config..."
    openclaw gateway restart 2>/dev/null || true
else
    echo "Starting OpenClaw gateway..."
    openclaw gateway install 2>/dev/null || openclaw gateway run &
fi

if [ -n "${CLAW_API_KEY:-}" ] && [ -f "$PROJECT_DIR/scripts/dashboard-sync.sh" ]; then
    pkill -f "dashboard-sync" 2>/dev/null || true
    nohup bash "$PROJECT_DIR/scripts/dashboard-sync.sh" > /tmp/dashboard-sync.log 2>&1 &
    echo "Dashboard sync started (PID $!)"
fi

echo ""
echo "=== ClawOSS Running ==="
echo "Dashboard: check your Vercel deployment"
echo "Model: $PRIMARY_MODEL"
echo "Logs: tail -f $HOME/.openclaw/logs/openclaw-$(date +%Y-%m-%d).log"
echo "Stop: npm run stop"
