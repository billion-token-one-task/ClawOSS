#!/usr/bin/env bash
set -euo pipefail

echo "=== ClawOSS Setup ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
CLAWOSS_DEFAULT_MODEL="${CLAWOSS_DEFAULT_MODEL:-minimax/MiniMax-M2.7}"

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

# Validate required auth/env
if [ -z "${GITHUB_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
    echo "Error: set GITHUB_TOKEN in .env or authenticate gh before setup"
    exit 1
fi
if [ -z "${MINIMAX_API_KEY:-}" ] && [ -z "${KIMI_API_KEY:-}" ]; then
    echo "Error: set MINIMAX_API_KEY in .env (recommended) or KIMI_API_KEY for fallback mode"
    exit 1
fi
echo "[OK] Auth and model API keys configured"

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

bash "$SCRIPT_DIR/init-workspace-state.sh" >/dev/null
echo "[OK] Workspace state initialized"

# Deploy config with path substitution
echo "Deploying config..."
sed \
    -e "s|__WORKSPACE_PATH__|$WORKSPACE_DIR|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__HOME_DIR__|$HOME|g" \
    "$PROJECT_DIR/config/openclaw.json" > "$OPENCLAW_DIR/openclaw.json"

# Inject env vars into deployed config (via env vars, not shell interpolation)
_CONFIG_PATH="$OPENCLAW_DIR/openclaw.json" \
_KIMI_KEY="${KIMI_API_KEY:-}" \
_MINIMAX_KEY="${MINIMAX_API_KEY:-}" \
_GH_TOKEN="${GITHUB_TOKEN:-}" \
_DASH_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}" \
_CLAW_KEY="${CLAW_API_KEY:-}" \
_CLAWOSS_ROOT="${PROJECT_DIR}" \
_CLAWOSS_MODEL="${CLAWOSS_DEFAULT_MODEL}" \
_RECORD_DECISIONS="${CLAWOSS_RECORD_DECISIONS:-1}" \
_RECORD_OUTCOMES="${CLAWOSS_RECORD_OUTCOMES:-1}" \
python3 -c "
import json, os
config_path = os.environ['_CONFIG_PATH']
with open(config_path) as f: c = json.load(f)
c.setdefault('env', {})
env_vars = {
    'KIMI_API_KEY': os.environ.get('_KIMI_KEY', ''),
    'MINIMAX_API_KEY': os.environ.get('_MINIMAX_KEY', ''),
    'GITHUB_TOKEN': os.environ.get('_GH_TOKEN', ''),
    'DASHBOARD_URL': os.environ.get('_DASH_URL', ''),
    'CLAW_API_KEY': os.environ.get('_CLAW_KEY', ''),
    'CLAWOSS_ROOT': os.environ.get('_CLAWOSS_ROOT', ''),
    'CLAWOSS_DEFAULT_MODEL': os.environ.get('_CLAWOSS_MODEL', ''),
    'CLAWOSS_RECORD_DECISIONS': os.environ.get('_RECORD_DECISIONS', ''),
    'CLAWOSS_RECORD_OUTCOMES': os.environ.get('_RECORD_OUTCOMES', ''),
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
if clawoss_is_macos && [ -f "$PLIST_SRC" ]; then
    launchctl unload "$PLIST_DST" 2>/dev/null || true
    sed \
        -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
        -e "s|__HOME_DIR__|$HOME|g" \
        "$PLIST_SRC" > "$PLIST_DST"
    launchctl load "$PLIST_DST" 2>/dev/null || true
    echo "[OK] PR ledger sync installed (launchd, 60s interval)"
elif [ -f "$PLIST_SRC" ]; then
    echo "[INFO] Skipping PR ledger sync plist install on non-macOS"
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
