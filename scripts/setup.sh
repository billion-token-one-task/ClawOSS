#!/usr/bin/env bash
set -euo pipefail

echo "=== ClawOSS Setup ==="

# Auto-detect paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$PROJECT_DIR/workspace"

# Check prerequisites
echo "Checking prerequisites..."
command -v openclaw >/dev/null 2>&1 || { echo "Error: openclaw not found. Install: npm i -g openclaw"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "Error: gh not found. Install: brew install gh"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Error: node not found. Install Node.js"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found. Install Python 3"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found. Install: brew install jq"; exit 1; }
echo "[OK] All prerequisites found"

# Load .env for API keys
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a; source "$PROJECT_DIR/.env"; set +a
    echo "[OK] Loaded .env"
else
    echo "Error: .env not found. Run: cp .env.example .env && edit .env"
    exit 1
fi

# Validate required env vars
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: GITHUB_TOKEN not set in .env"
    exit 1
fi
if [ -z "${LLM_API_KEY:-}" ]; then
    echo "Error: LLM_API_KEY not set in .env"
    exit 1
fi
if [ -z "${LLM_MODEL:-}" ]; then
    echo "Error: LLM_MODEL not set in .env"
    exit 1
fi
if [ -z "${LLM_BASE_URL:-}" ]; then
    echo "Error: LLM_BASE_URL not set in .env"
    exit 1
fi
echo "[OK] API keys configured"

# Configure git identity
GITHUB_USERNAME="${GITHUB_USERNAME:-BillionClaw}"
GITHUB_EMAIL="${GITHUB_EMAIL:-267901332+BillionClaw@users.noreply.github.com}"
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$GITHUB_EMAIL"
echo "[OK] Git identity: $GITHUB_USERNAME <$GITHUB_EMAIL>"

# Authenticate GitHub CLI
if gh auth status >/dev/null 2>&1; then
    echo "[OK] GitHub CLI already authenticated"
else
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
        echo "[OK] GitHub CLI authenticated via token"
    else
        echo "GitHub CLI not authenticated. Starting interactive login..."
        gh auth login
    fi
fi

# Create workspace symlink
OPENCLAW_DIR="$HOME/.openclaw"
mkdir -p "$OPENCLAW_DIR"
WORKSPACE_LINK="$OPENCLAW_DIR/workspace"

if [ -L "$WORKSPACE_LINK" ] && [ "$(readlink "$WORKSPACE_LINK")" = "$WORKSPACE_DIR" ]; then
    echo "[OK] Workspace already linked"
elif [ -L "$WORKSPACE_LINK" ] || [ -d "$WORKSPACE_LINK" ]; then
    mv "$WORKSPACE_LINK" "${WORKSPACE_LINK}.backup.$(date +%s)"
    ln -sf "$WORKSPACE_DIR" "$WORKSPACE_LINK"
    echo "[OK] Workspace linked (old backed up)"
else
    ln -sf "$WORKSPACE_DIR" "$WORKSPACE_LINK"
    echo "[OK] Workspace linked"
fi

# Deploy config with path substitution
echo "Deploying config..."
sed \
    -e "s|__WORKSPACE_PATH__|$WORKSPACE_DIR|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__HOME_DIR__|$HOME|g" \
    "$PROJECT_DIR/config/openclaw.json" > "$OPENCLAW_DIR/openclaw.json"

# Inject env vars into deployed config (via env vars, not shell interpolation)
_CONFIG_PATH="$OPENCLAW_DIR/openclaw.json" \
_LLM_KEY="${LLM_API_KEY:-}" \
_LLM_MODEL="${LLM_MODEL:-}" \
_LLM_BASE_URL="${LLM_BASE_URL:-}" \
_GH_TOKEN="${GITHUB_TOKEN:-}" \
_DASH_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}" \
_CLAW_KEY="${CLAW_API_KEY:-}" \
python3 -c "
import json, os
config_path = os.environ['_CONFIG_PATH']
with open(config_path) as f: c = json.load(f)
c.setdefault('env', {})
env_vars = {
    'LLM_API_KEY': os.environ.get('_LLM_KEY', ''),
    'LLM_MODEL': os.environ.get('_LLM_MODEL', ''),
    'LLM_BASE_URL': os.environ.get('_LLM_BASE_URL', ''),
    'GITHUB_TOKEN': os.environ.get('_GH_TOKEN', ''),
    'DASHBOARD_URL': os.environ.get('_DASH_URL', ''),
    'CLAW_API_KEY': os.environ.get('_CLAW_KEY', ''),
}
for k, v in env_vars.items():
    if v:
        c['env'][k] = v
c['env'] = {k: v for k, v in c['env'].items() if v}
with open(config_path, 'w') as f: json.dump(c, f, indent=2)
" 2>/dev/null
echo "[OK] Config deployed with env vars"

# Install PR ledger sync launchd plist
PLIST_SRC="$PROJECT_DIR/config/com.clawoss.pr-ledger-sync.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.clawoss.pr-ledger-sync.plist"
if [ -f "$PLIST_SRC" ]; then
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    sed \
        -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
        -e "s|__HOME_DIR__|$HOME|g" \
        "$PLIST_SRC" > "$PLIST_DST"
    launchctl load "$PLIST_DST" 2>/dev/null || true
    echo "[OK] PR ledger sync installed (launchd, 60s interval)"
fi

# Install PII sanitizer plugin
PLUGIN_SRC="$PROJECT_DIR/plugins/pii-sanitizer"
PLUGIN_DST="$OPENCLAW_DIR/extensions/clawoss-pii-sanitizer"
if [ -d "$PLUGIN_SRC" ]; then
    mkdir -p "$PLUGIN_DST"
    cp -f "$PLUGIN_SRC/index.js" "$PLUGIN_DST/index.js"
    echo "[OK] PII sanitizer plugin installed"
fi

# Symlink skills
echo "Linking skills..."
mkdir -p "$OPENCLAW_DIR/skills"
for skill in "$WORKSPACE_DIR/skills"/*/; do
    [ ! -d "$skill" ] && continue
    name=$(basename "$skill")
    ln -sf "$skill" "$OPENCLAW_DIR/skills/$name"
    echo "  Linked: $name"
done

# Create working directories
mkdir -p "$OPENCLAW_DIR/logs"
mkdir -p "$WORKSPACE_DIR/memory/repos"
mkdir -p "$WORKSPACE_DIR/memory/issues"
echo "[OK] Directories ready"

echo ""
echo "=== Setup Complete ==="
echo "  Project: $PROJECT_DIR"
echo "  Workspace: $WORKSPACE_DIR"
echo ""
echo "Next steps:"
echo "  bash scripts/restart.sh    # Start the agent"
echo "  openclaw logs              # Watch agent output"
