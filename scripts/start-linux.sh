#!/usr/bin/env bash
# Linux/Docker compatible start script — replaces the macOS launchd portions of restart.sh
set -euo pipefail

echo "=== ClawOSS Linux Start ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$PROJECT_DIR/workspace"
DEPLOYED_CONFIG="$HOME/.openclaw/openclaw.json"

# Validate required environment variables
: "${LLM_API_KEY:?LLM_API_KEY is required}"
: "${LLM_MODEL:?LLM_MODEL is required}"
: "${LLM_BASE_URL:?LLM_BASE_URL is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

# Git identity
GITHUB_USERNAME="${GITHUB_USERNAME:-BillionClaw}"
GITHUB_EMAIL="${GITHUB_EMAIL:-267901332+BillionClaw@users.noreply.github.com}"
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$GITHUB_EMAIL"
echo "[OK] Git identity: $GITHUB_USERNAME <$GITHUB_EMAIL>"

# GitHub CLI auth
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
if gh auth status &>/dev/null; then
    echo "[OK] GitHub CLI authenticated"
else
    echo "[WARN] GitHub CLI auth failed — gh commands may fail"
fi

# Link workspace
mkdir -p "$HOME/.openclaw"
OC_WORKSPACE="$HOME/.openclaw/workspace"
if [ ! -L "$OC_WORKSPACE" ] || [ "$(readlink "$OC_WORKSPACE" 2>/dev/null)" != "$WORKSPACE_DIR" ]; then
    rm -f "$OC_WORKSPACE" 2>/dev/null || true
    ln -sf "$WORKSPACE_DIR" "$OC_WORKSPACE"
    echo "[OK] Workspace linked: $WORKSPACE_DIR"
else
    echo "[OK] Workspace already linked"
fi

# Deploy config (same sed + python3 deep-merge logic as restart.sh step 5)
# LLM_PROVIDER_NAME: override provider key in openclaw.json (avoids conflicts with
# OpenClaw built-in providers like "openai"). Default: prefix before first "/" in LLM_MODEL.
# LLM_MODEL_API_ID: the model ID sent to the API. Default: full LLM_MODEL value.
_LLM_PROVIDER_NAME="${LLM_PROVIDER_NAME:-$(echo "${LLM_MODEL}" | cut -d'/' -f1)}"
_LLM_MODEL_API_ID="${LLM_MODEL_API_ID:-${LLM_MODEL}}"

REPO_CONFIG_RESOLVED=$(sed \
    -e "s|__WORKSPACE_PATH__|$WORKSPACE_DIR|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__HOME_DIR__|$HOME|g" \
    -e "s|__LLM_MODEL__|${LLM_MODEL}|g" \
    -e "s|__LLM_BASE_URL__|${LLM_BASE_URL}|g" \
    -e "s|__LLM_PROVIDER__|${_LLM_PROVIDER_NAME}|g" \
    -e "s|__LLM_MODEL_ID__|${_LLM_MODEL_API_ID}|g" \
    -e "s|__LLM_INPUT_COST__|$(echo "scale=9; ${LLM_INPUT_COST_PER_MILLION:-0.15} / 1000000" | bc)|g" \
    -e "s|__LLM_OUTPUT_COST__|$(echo "scale=9; ${LLM_OUTPUT_COST_PER_MILLION:-0.60} / 1000000" | bc)|g" \
    -e "s|__LLM_CONTEXT_WINDOW__|${LLM_CONTEXT_WINDOW:-128000}|g" \
    -e "s|__LLM_MAX_TOKENS__|${LLM_MAX_TOKENS:-16384}|g" \
    "$PROJECT_DIR/config/openclaw.json")

_REPO_CONFIG="$REPO_CONFIG_RESOLVED" \
_DEPLOYED="$DEPLOYED_CONFIG" \
_LLM_KEY="${LLM_API_KEY}" \
_LLM_MODEL="${LLM_MODEL}" \
_LLM_BASE_URL="${LLM_BASE_URL}" \
_GH_TOKEN="${GITHUB_TOKEN}" \
_DASH_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}" \
_CLAW_KEY="${CLAW_API_KEY:-}" \
python3 -c "
import json, os

def deep_merge(base, override):
    result = dict(base)
    for k, v in override.items():
        if k in result and isinstance(result[k], dict) and isinstance(v, dict):
            result[k] = deep_merge(result[k], v)
        else:
            result[k] = v
    return result

repo_config = json.loads(os.environ['_REPO_CONFIG'])
deployed_path = os.environ['_DEPLOYED']

# Coerce string placeholders to numbers (sed produces strings in JSON)
for m in repo_config.get('models', {}).get('providers', {}).values():
    for model in m.get('models', []):
        for k in ('contextWindow', 'maxTokens'):
            if isinstance(model.get(k), str):
                model[k] = int(model[k])
        cost = model.get('cost', {})
        for k in ('input', 'output'):
            if isinstance(cost.get(k), str):
                cost[k] = float(cost[k])

try:
    with open(deployed_path) as f:
        deployed = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    deployed = {}

merged = deep_merge(deployed, repo_config)
merged.setdefault('env', {})
env_map = {
    'LLM_API_KEY': os.environ.get('_LLM_KEY', ''),
    'LLM_MODEL': os.environ.get('_LLM_MODEL', ''),
    'LLM_BASE_URL': os.environ.get('_LLM_BASE_URL', ''),
    'GITHUB_TOKEN': os.environ.get('_GH_TOKEN', ''),
    'DASHBOARD_URL': os.environ.get('_DASH_URL', ''),
    'CLAW_API_KEY': os.environ.get('_CLAW_KEY', ''),
}
for k, v in env_map.items():
    if v:
        merged['env'][k] = v
merged['env'] = {k: v for k, v in merged['env'].items() if v}

with open(deployed_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
"
echo "[OK] Config deployed"

# Write auth-profiles.json for the clawoss agent
# OpenClaw derives the auth lookup key from the model name prefix (e.g. "openai"
# from "openai/gpt-4o-mini"), independently of the provider name in models.providers.
_AUTH_PROVIDER="$(echo "${LLM_MODEL}" | cut -d'/' -f1)"
_AUTH_DIR="$HOME/.openclaw/agents/clawoss/agent"
mkdir -p "$_AUTH_DIR"
_AUTH_FILE="$_AUTH_DIR/auth-profiles.json"
_AUTH_PROVIDER="$_AUTH_PROVIDER" \
_AUTH_KEY="${LLM_API_KEY}" \
_AUTH_BASE_URL="${LLM_BASE_URL}" \
python3 -c "
import json, os
auth_file = os.environ.get('_AUTH_FILE', '') or '$_AUTH_FILE'
provider  = os.environ['_AUTH_PROVIDER']
api_key   = os.environ['_AUTH_KEY']
base_url  = os.environ['_AUTH_BASE_URL']
try:
    with open('$_AUTH_FILE') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data[provider] = {'apiKey': api_key, 'baseUrl': base_url}
with open('$_AUTH_FILE', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
echo "[OK] Auth profile written for provider: $_AUTH_PROVIDER"

# Create required directories
mkdir -p "$HOME/.openclaw/logs" \
         "$WORKSPACE_DIR/memory/repos" \
         "$WORKSPACE_DIR/memory/issues" \
         "$WORKSPACE_DIR/memory/locks" \
         "$WORKSPACE_DIR/memory/subagent-inputs"
echo "[OK] Directories ready"

# Reset spawn state
cat > "$WORKSPACE_DIR/memory/impl-spawn-state.md" << 'SPAWNEOF'
# Implementation Spawn State — Reset by start-linux.sh

## Active Implementations (0 total)
| issue_url | repo | status | spawned_at |
|-----------|------|--------|------------|

## Active Follow-ups (0 total)
| pr_url | repo | status | round | spawned_at |
|--------|------|--------|-------|------------|
SPAWNEOF

cat > "$WORKSPACE_DIR/memory/wake-state.md" << 'WAKEEOF'
consecutive_wakes: 0
errors_this_hour: 0
last_error: none
last_wake: none
WAKEEOF

echo "[OK] State files reset"

# Start gateway in foreground (suitable for containers — process keeps container alive)
echo "[OK] Starting OpenClaw gateway (model: ${LLM_MODEL})..."
openclaw gateway run &
GATEWAY_PID=$!

sleep 8

# Start dashboard-sync in background if CLAW_API_KEY is set
# if [ -n "${CLAW_API_KEY:-}" ]; then
#     nohup bash "$PROJECT_DIR/scripts/dashboard-sync.sh" \
#         > /tmp/dashboard-sync.log 2>&1 &
#     echo "[OK] Dashboard sync started"
# fi
if [ -n "${CLAW_API_KEY:-}" ]; then
    bash "$PROJECT_DIR/scripts/dashboard-sync.sh" 2>&1 &
    echo "[OK] Dashboard sync started"
fi

# Kick the agent
openclaw system event \
    --text "ClawOSS Linux start. Execute HEARTBEAT.md steps 0-7. Fill all impl slots. NEVER idle." \
    --mode now 2>/dev/null || true

echo "[OK] ClawOSS running. Gateway PID: $GATEWAY_PID"
echo "  Model: ${LLM_MODEL}"
echo "  Logs: openclaw logs"
echo "  PRs: gh search prs --author ${GITHUB_USERNAME} --state open"

# Keep container alive
wait $GATEWAY_PID
