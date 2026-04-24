#!/usr/bin/env bash
set -euo pipefail

echo "=== ClawOSS Setup ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$PROJECT_DIR/workspace"
export CLAWOSS_PROJECT_DIR="${CLAWOSS_PROJECT_DIR:-$PROJECT_DIR}"
export CLAWOSS_WORKSPACE_DIR="${CLAWOSS_WORKSPACE_DIR:-$WORKSPACE_DIR}"

echo "Checking prerequisites..."
command -v openclaw >/dev/null 2>&1 || { echo "Error: openclaw not found. Install: npm i -g openclaw"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "Error: gh not found. Install gh first"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Error: node not found. Install Node.js"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found. Install Python 3"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq not found. Install jq first"; exit 1; }
echo "[OK] All prerequisites found"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
    echo "[OK] Loaded .env"
else
    echo "Error: .env not found. Run: cp .env.example .env && edit .env"
    exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: GITHUB_TOKEN not set in .env"
    exit 1
fi

PRIMARY_MODEL="$(node "$PROJECT_DIR/scripts/render-openclaw-config.mjs" --print-primary-model 2>/dev/null || true)"
if [ -z "$PRIMARY_MODEL" ]; then
    echo "Error: LLM runtime config is invalid. Check CLAWOSS_MODEL_* or CLAWOSS_MODEL_PROVIDERS_JSON."
    exit 1
fi
echo "[OK] Runtime configured: $PRIMARY_MODEL"

GITHUB_USERNAME="${GITHUB_USERNAME:-clawoss-agent}"
GITHUB_EMAIL="${GITHUB_EMAIL:-clawoss-agent@users.noreply.github.com}"
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$GITHUB_EMAIL"
echo "[OK] Git identity: $GITHUB_USERNAME <$GITHUB_EMAIL>"

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

echo "Deploying config..."
node "$PROJECT_DIR/scripts/render-openclaw-config.mjs" --output "$OPENCLAW_DIR/openclaw.json"
echo "[OK] Config deployed for model: $PRIMARY_MODEL"

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

PLUGIN_SRC="$PROJECT_DIR/plugins/pii-sanitizer"
PLUGIN_DST="$OPENCLAW_DIR/extensions/clawoss-pii-sanitizer"
if [ -d "$PLUGIN_SRC" ]; then
    mkdir -p "$PLUGIN_DST"
    cp -f "$PLUGIN_SRC/index.js" "$PLUGIN_DST/index.js"
    echo "[OK] PII sanitizer plugin installed"
fi

echo "Linking skills..."
mkdir -p "$OPENCLAW_DIR/skills"
for skill in "$WORKSPACE_DIR/skills"/*/; do
    [ ! -d "$skill" ] && continue
    name=$(basename "$skill")
    ln -sf "$skill" "$OPENCLAW_DIR/skills/$name"
    echo "  Linked: $name"
done

mkdir -p "$OPENCLAW_DIR/logs"
mkdir -p "$WORKSPACE_DIR/memory/repos"
mkdir -p "$WORKSPACE_DIR/memory/issues"
mkdir -p "$WORKSPACE_DIR/memory/locks"
echo "[OK] Directories ready"

echo ""
echo "=== Setup Complete ==="
echo "  Project: $PROJECT_DIR"
echo "  Workspace: $WORKSPACE_DIR"
echo "  Primary model: $PRIMARY_MODEL"
echo ""
echo "Next steps:"
echo "  bash scripts/restart.sh    # Start the agent"
echo "  openclaw logs              # Watch agent output"
