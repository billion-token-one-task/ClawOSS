#!/usr/bin/env bash
# ClawOSS V10 Full Restart Script
# THE canonical way to restart ClawOSS from scratch.
# Safe to run multiple times — idempotent.
#
# DO NOT use `set -euo pipefail` — many steps use commands that may
# legitimately fail (process kills, gateway stop, launchctl unload).
# Each step handles its own errors explicitly.

echo "=== ClawOSS V10 Full Restart ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
CLAWOSS_DEFAULT_MODEL="${CLAWOSS_DEFAULT_MODEL:-minimax/MiniMax-M2.7}"
DEPLOYED_CONFIG="$HOME/.openclaw/openclaw.json"
GATEWAY_PLIST="$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
SMOKE_MODE=0

case "${CLAWOSS_SMOKE_MODE:-0}" in
    1|true|TRUE|yes|YES) SMOKE_MODE=1 ;;
esac

smoke_sleep() {
    if [ "$SMOKE_MODE" -eq 1 ]; then
        return 0
    fi
    sleep "$1"
}

# ── 0. Preflight checks ──────────────────────────────────────────────
MISSING=()
command -v python3 &>/dev/null || MISSING+=("python3")
command -v gh       &>/dev/null || MISSING+=("gh")
command -v jq       &>/dev/null || MISSING+=("jq")
command -v openclaw &>/dev/null || MISSING+=("openclaw")
command -v node     &>/dev/null || MISSING+=("node")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[FAIL] Missing required tools: ${MISSING[*]}"
    echo "       Install them and retry."
    exit 1
fi
echo "[OK] All required tools found (python3, gh, jq, openclaw, node)"
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Restart smoke mode enabled — skipping global cleanup and external side effects where possible"
fi

# 0b. Ensure `python` resolves to `python3` (macOS has no `python` binary)
# Subagents run target repo test suites that call `python` — this prevents failures.
if ! command -v python &>/dev/null && command -v python3 &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(which python3)" "$HOME/.local/bin/python"
    # Ensure ~/.local/bin is in PATH for this session
    export PATH="$HOME/.local/bin:$PATH"
    echo "[OK] Created python -> python3 symlink in ~/.local/bin"
elif command -v python &>/dev/null; then
    echo "[OK] python already available: $(which python)"
fi

# ── 1. Load environment ──────────────────────────────────────────────
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
    echo "[OK] Loaded .env"
else
    echo "[INFO] No .env found — using existing env vars"
fi

# ── 2. Git identity ──────────────────────────────────────────────────
GITHUB_USERNAME="${GITHUB_USERNAME:-BillionClaw}"
GITHUB_EMAIL="${GITHUB_EMAIL:-267901332+BillionClaw@users.noreply.github.com}"
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$GITHUB_EMAIL"
echo "[OK] Git identity: $GITHUB_USERNAME <$GITHUB_EMAIL>"

# ── 3. GitHub CLI auth (skip if already authenticated) ────────────────
if gh auth status &>/dev/null; then
    echo "[OK] GitHub CLI already authenticated"
elif [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
    if gh auth status &>/dev/null; then
        echo "[OK] GitHub CLI authenticated via token"
    else
        echo "[WARN] GitHub CLI auth failed — gh commands may fail"
    fi
else
    echo "[WARN] No GITHUB_TOKEN and gh not authenticated — gh commands may fail"
fi

# ── 4. Link workspace ────────────────────────────────────────────────
OC_WORKSPACE="$HOME/.openclaw/workspace"
if [ ! -L "$OC_WORKSPACE" ] || [ "$(readlink "$OC_WORKSPACE" 2>/dev/null)" != "$WORKSPACE_DIR" ]; then
    if [ -d "$OC_WORKSPACE" ] && [ ! -L "$OC_WORKSPACE" ]; then
        mv "$OC_WORKSPACE" "${OC_WORKSPACE}.backup.$(date +%s)"
    fi
    rm -f "$OC_WORKSPACE" 2>/dev/null || true
    ln -sf "$WORKSPACE_DIR" "$OC_WORKSPACE"
    echo "[OK] Workspace linked: $WORKSPACE_DIR"
else
    echo "[OK] Workspace already linked"
fi

# ── 5. Deploy config (deep-merge repo config into deployed config) ────
# Preserves gateway-managed sections (meta, commands, plugins, gateway.auth)
# while overlaying all agent/tool/skill settings from the repo config.

REPO_CONFIG_RESOLVED=$(sed \
    -e "s|__WORKSPACE_PATH__|$WORKSPACE_DIR|g" \
    -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
    -e "s|__HOME_DIR__|$HOME|g" \
    "$PROJECT_DIR/config/openclaw.json")

_REPO_CONFIG="$REPO_CONFIG_RESOLVED" \
_DEPLOYED="$DEPLOYED_CONFIG" \
_KIMI_KEY="${KIMI_API_KEY:-}" \
_MINIMAX_KEY="${MINIMAX_API_KEY:-}" \
_GH_TOKEN="${GITHUB_TOKEN:-}" \
_DASH_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}" \
_CLAW_KEY="${CLAW_API_KEY:-}" \
_OPENROUTER_KEY="${OPENROUTER_API_KEY:-}" \
_CLAWOSS_ROOT="${PROJECT_DIR}" \
_CLAWOSS_MODEL="${CLAWOSS_DEFAULT_MODEL}" \
_RECORD_DECISIONS="${CLAWOSS_RECORD_DECISIONS:-1}" \
_RECORD_OUTCOMES="${CLAWOSS_RECORD_OUTCOMES:-1}" \
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

try:
    with open(deployed_path) as f:
        deployed = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    deployed = {}

merged = deep_merge(deployed, repo_config)

# Inject env vars (non-empty only)
merged.setdefault('env', {})
env_map = {
    'KIMI_API_KEY': os.environ.get('_KIMI_KEY', ''),
    'MINIMAX_API_KEY': os.environ.get('_MINIMAX_KEY', ''),
    'GITHUB_TOKEN': os.environ.get('_GH_TOKEN', ''),
    'DASHBOARD_URL': os.environ.get('_DASH_URL', ''),
    'CLAW_API_KEY': os.environ.get('_CLAW_KEY', ''),
    'OPENROUTER_API_KEY': os.environ.get('_OPENROUTER_KEY', ''),
    'CLAWOSS_ROOT': os.environ.get('_CLAWOSS_ROOT', ''),
    'CLAWOSS_DEFAULT_MODEL': os.environ.get('_CLAWOSS_MODEL', ''),
    'CLAWOSS_RECORD_DECISIONS': os.environ.get('_RECORD_DECISIONS', ''),
    'CLAWOSS_RECORD_OUTCOMES': os.environ.get('_RECORD_OUTCOMES', ''),
}
for k, v in env_map.items():
    if v:
        merged['env'][k] = v
merged['env'] = {k: v for k, v in merged['env'].items() if v}

with open(deployed_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
"

if [ $? -eq 0 ]; then
    echo "[OK] Config deployed (deep-merged with env vars)"
else
    echo "[FAIL] Config merge failed — check python3 output above"
    exit 1
fi

# ── 5b. Disable cron jobs (V10: no cron dependencies) ─────────────────
# V10 architecture: heartbeat + 3 always-on subagents handle everything.
# Crons are disabled — scout handles discovery, PR monitor handles follow-ups,
# PR analyst handles reporting/analysis, heartbeat step 7 handles cleanup.
CRON_STORE="$HOME/.openclaw/cron/jobs.json"
if [ -f "$CRON_STORE" ]; then
    python3 -c "
import json
with open('$CRON_STORE') as f:
    store = json.load(f)
for job in store.get('jobs', []):
    job['enabled'] = False
with open('$CRON_STORE', 'w') as f:
    json.dump(store, f, indent=2)
print('All cron jobs disabled (V10: no cron dependencies)')
" 2>&1 || true
    echo "[OK] Cron jobs disabled (V10: heartbeat + subagents handle everything)"
fi

# ── 6. Update gateway plist PATH (ensure python3, gh, jq are reachable) ─
# The gateway spawns subagents that need these tools. launchd has a minimal
# PATH so we inject the paths we need.
if clawoss_is_macos && [ -f "$GATEWAY_PLIST" ]; then
    # Get current PATH from plist
    PLIST_PATH=$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:PATH" "$GATEWAY_PLIST" 2>/dev/null || echo "")
    NEEDS_UPDATE=false

    # Directories that must be in the plist PATH
    REQUIRED_DIRS=()
    for dir in "/opt/homebrew/bin" "/usr/local/bin" "/usr/bin" "/bin" "/usr/sbin" "/sbin"; do
        if [ -d "$dir" ] && [[ ":$PLIST_PATH:" != *":$dir:"* ]]; then
            REQUIRED_DIRS+=("$dir")
            NEEDS_UPDATE=true
        fi
    done

    # Also add nvm node path if present
    NVM_NODE_DIR="$(dirname "$(which node)" 2>/dev/null || echo "")"
    if [ -n "$NVM_NODE_DIR" ] && [[ ":$PLIST_PATH:" != *":$NVM_NODE_DIR:"* ]]; then
        REQUIRED_DIRS+=("$NVM_NODE_DIR")
        NEEDS_UPDATE=true
    fi

    # Add gh path if not already included
    GH_DIR="$(dirname "$(which gh)" 2>/dev/null || echo "")"
    if [ -n "$GH_DIR" ] && [[ ":$PLIST_PATH:" != *":$GH_DIR:"* ]]; then
        REQUIRED_DIRS+=("$GH_DIR")
        NEEDS_UPDATE=true
    fi

    # Add ~/.local/bin (python -> python3 symlink lives here)
    LOCAL_BIN="$HOME/.local/bin"
    if [ -d "$LOCAL_BIN" ] && [[ ":$PLIST_PATH:" != *":$LOCAL_BIN:"* ]]; then
        REQUIRED_DIRS+=("$LOCAL_BIN")
        NEEDS_UPDATE=true
    fi

    if [ "$NEEDS_UPDATE" = true ] && [ -n "$PLIST_PATH" ]; then
        NEW_PATH="$PLIST_PATH"
        for dir in "${REQUIRED_DIRS[@]}"; do
            NEW_PATH="$NEW_PATH:$dir"
        done
        /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:PATH $NEW_PATH" "$GATEWAY_PLIST" 2>/dev/null || true
        echo "[OK] Gateway plist PATH updated (added: ${REQUIRED_DIRS[*]})"
    else
        echo "[OK] Gateway plist PATH already includes required dirs"
    fi
else
    echo "[INFO] No gateway plist found at $GATEWAY_PLIST — gateway install will create it"
fi

# ── 7. Flush context & clean sessions ─────────────────────────────────
# Delete ALL session .jsonl files (main + subagents) to force fresh context.
# OpenClaw recreates them on next message — this is safe per DeepWiki docs.
# The heartbeat timer lives in gateway process memory, not in session files.
# Also delete sessions.json entries — they're recreated on demand.
SESSIONS_DIR="$HOME/.openclaw/agents/clawoss/sessions"
TOTAL_CLEANED=0
if [ -d "$SESSIONS_DIR" ]; then
    TOTAL_CLEANED=$(find "$SESSIONS_DIR" -name "*.jsonl*" 2>/dev/null | wc -l | tr -d ' ')
    rm -f "$SESSIONS_DIR/"*.jsonl 2>/dev/null || true
    rm -f "$SESSIONS_DIR/"*.jsonl.deleted.* 2>/dev/null || true
    rm -f "$SESSIONS_DIR/"*.jsonl.reset.* 2>/dev/null || true
    rm -f "$SESSIONS_DIR/"*.lock 2>/dev/null || true
    # Reset sessions.json to empty — gateway recreates entries on first heartbeat
    echo '{}' > "$SESSIONS_DIR/sessions.json"
fi
echo "[OK] Context flushed ($TOTAL_CLEANED session files removed, fresh start)"

# ── 7b. Reset impl-spawn-state to EMPTY ───────────────────────────────
# All subagents die on restart. The state file must be reset to show 0 active
# agents — otherwise the main agent reads "10/10 slots FULL" and refuses to
# spawn new work. This was the root cause of post-restart stalls.
cat > "$WORKSPACE_DIR/memory/impl-spawn-state.md" << 'SPAWNEOF'
# Implementation Spawn State — Reset by restart.sh

## Active Implementations (0 total)
| issue_url | repo | status | spawned_at |
|-----------|------|--------|------------|

## Active Follow-ups (0 total)
| pr_url | repo | status | round | spawned_at |
|--------|------|--------|-------|------------|
SPAWNEOF
# Also reset followup state
cat > "$WORKSPACE_DIR/memory/pr-followup-state.md" << 'FOLLOWEOF'
# PR Follow-up State — Reset by restart.sh
No active follow-ups.
FOLLOWEOF
echo "[OK] Spawn state reset to empty (0 active implementations)"

# ── 7c. Clean stale subagent result files ─────────────────────────
RESULT_COUNT=$(ls "$WORKSPACE_DIR/memory/subagent-result-"*.md 2>/dev/null | wc -l | tr -d ' ')
rm -f "$WORKSPACE_DIR/memory/subagent-result-"*.md 2>/dev/null || true
echo "[OK] Cleaned $RESULT_COUNT stale result files"

# ── 8. Reset wake state (V9: no rate-limit fields) ───────────────────
cat > "$WORKSPACE_DIR/memory/wake-state.md" << 'WAKEEOF'
consecutive_wakes: 0
errors_this_hour: 0
last_error: none
last_wake: none
WAKEEOF
echo "[OK] Wake state reset (V10)"

# ── 9. Create required directories ───────────────────────────────────
mkdir -p "$HOME/.openclaw/logs"
mkdir -p "$WORKSPACE_DIR/memory/repos"
mkdir -p "$WORKSPACE_DIR/memory/issues"
mkdir -p "$WORKSPACE_DIR/memory/locks"
mkdir -p "$WORKSPACE_DIR/memory/subagent-inputs"
echo "[OK] Directories ready (including memory/locks/ for dedup)"

# ── 10. Clean ALL lock files (restart = full cleanup) ─────────────────
ALL_LOCKS=$(find "$WORKSPACE_DIR/memory/locks/" -name "*.lock" 2>/dev/null | wc -l | tr -d ' ')
find "$WORKSPACE_DIR/memory/locks/" -name "*.lock" -delete 2>/dev/null || true
echo "[OK] All lock files cleaned ($ALL_LOCKS removed)"

# ── 11. Clean ALL /tmp workspaces (restart = full cleanup) ────────────
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Smoke mode: skipping /tmp/clawoss-* cleanup"
else
    ORPHANED=$(find /tmp -maxdepth 1 -name "clawoss-*" -type d 2>/dev/null | wc -l | tr -d ' ')
    find /tmp -maxdepth 1 -name "clawoss-*" -type d -exec rm -rf {} + 2>/dev/null || true
    echo "[OK] All /tmp workspaces cleaned ($ORPHANED removed)"
fi

# ── 12. Kill all subagents, then stop gateway ─────────────────────────
# Kill all running subagents BEFORE stopping the gateway.
# This prevents orphaned LLM inference runs that consume API tokens.
# The /subagents kill all command terminates all active subagent runs.
if openclaw gateway status 2>/dev/null | grep -qi "running\|reachable\|ok"; then
    if [ "$SMOKE_MODE" -eq 1 ]; then
        echo "[INFO] Smoke mode: skipping subagent kill event and session cleanup"
    else
        echo "[INFO] Killing all active subagents..."
        openclaw system event --text "/subagents kill all" --mode now 2>/dev/null || true
        smoke_sleep 3  # Give gateway time to process kill commands
        # Also run sessions cleanup to prune any stale entries
        openclaw sessions cleanup --agent clawoss 2>/dev/null || true
        echo "[OK] All subagents killed"
    fi
fi
openclaw gateway stop 2>/dev/null || true
smoke_sleep 2
echo "[OK] Gateway stopped"

# ── 13. Start gateway (prefer install for launchd, fallback to run) ───
# `gateway install` creates/updates the launchd plist and loads it.
# The plist has all env vars baked in (KIMI_API_KEY, GITHUB_TOKEN, etc.)
# `gateway run &` is a fallback that inherits the current shell env.
if openclaw gateway install 2>/dev/null; then
    echo "[OK] Gateway installed via launchd"
else
    echo "[WARN] gateway install failed — falling back to gateway run"
    openclaw gateway run &
    echo "[OK] Gateway started in background (PID $!)"
fi

smoke_sleep 8  # 8s to allow gateway to fully initialize heartbeat timer + session registry

# Verify gateway is running
if openclaw gateway status 2>/dev/null | grep -qi "running\|reachable\|ok"; then
    echo "[OK] Gateway verified running"
else
    echo "[FAIL] Gateway not running after startup"
    echo "       Try: openclaw gateway status"
    echo "       Try: openclaw gateway run"
    echo "       Logs: cat ~/.openclaw/logs/gateway.err.log"
    exit 1
fi

# ── 14. Dashboard sync ───────────────────────────────────────────────
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Smoke mode: skipping dashboard-sync pkill"
else
    pkill -f "dashboard-sync" 2>/dev/null || true
fi
smoke_sleep 1

if [ -f "$PROJECT_DIR/scripts/dashboard-sync.sh" ]; then
    if [ "$SMOKE_MODE" -eq 1 ]; then
        echo "[INFO] Smoke mode: skipping dashboard-sync startup"
    elif [ -z "${CLAW_API_KEY:-}" ]; then
        echo "[WARN] CLAW_API_KEY not set — dashboard-sync will not start"
    else
        nohup bash "$PROJECT_DIR/scripts/dashboard-sync.sh" > /tmp/dashboard-sync.log 2>&1 &
        echo "[OK] Dashboard sync started (PID $!)"
    fi
else
    echo "[INFO] No dashboard-sync.sh found — skipping"
fi

# ── 15. PR ledger sync (launchd, runs every 60s) ─────────────────────
LEDGER_PLIST="$HOME/Library/LaunchAgents/com.clawoss.pr-ledger-sync.plist"
if clawoss_is_macos; then
    launchctl unload "$LEDGER_PLIST" 2>/dev/null || true

    if [ -f "$PROJECT_DIR/config/com.clawoss.pr-ledger-sync.plist" ]; then
        sed \
            -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
            -e "s|__HOME_DIR__|$HOME|g" \
            "$PROJECT_DIR/config/com.clawoss.pr-ledger-sync.plist" > "$LEDGER_PLIST"
        launchctl load "$LEDGER_PLIST" 2>/dev/null || true
        echo "[OK] PR ledger sync installed (launchd, 60s interval)"
    elif [ -f "$LEDGER_PLIST" ]; then
        launchctl load "$LEDGER_PLIST" 2>/dev/null || true
        echo "[OK] PR ledger sync loaded (existing plist)"
    else
        echo "[INFO] No pr-ledger-sync plist found — skipping"
    fi
else
    echo "[INFO] PR ledger sync launchd integration is skipped on non-macOS"
fi

# ── 15b. Ensure dual push remotes (CMLKevin + billion-token-one-task) ──
cd "$PROJECT_DIR"
# Add billionclaw as second push URL so `git push origin` goes to both repos
PUSH_URLS=$(git remote get-url --push --all origin 2>/dev/null || echo "")
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Smoke mode: skipping dual push remote mutation"
elif ! echo "$PUSH_URLS" | grep -q "billion-token-one-task"; then
    git remote set-url --add --push origin https://github.com/billion-token-one-task/ClawOSS.git 2>/dev/null || true
    echo "[OK] Added billion-token-one-task as second push target"
else
    echo "[OK] Dual push remotes already configured"
fi

# ── 16. Kick the agent ───────────────────────────────────────────────
smoke_sleep 3
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Smoke mode: skipping agent wake event"
elif openclaw system event \
    --text "ClawOSS V10.1 restart. Execute HEARTBEAT.md steps 0-7. Always-on agents use runTimeoutSeconds:0 (no timeout). Discover across ALL niches. Fill all 10 impl slots. NEVER idle — always work on something." \
    --mode now 2>&1; then
    echo "[OK] Agent kicked (V10)"
else
    echo "[WARN] Agent wake event failed — agent will wake on next heartbeat timer"
fi

# ── 17. Start tmp-cleaner daemon ───────────────────────────────────────
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Smoke mode: skipping tmp-cleaner daemon"
else
    pkill -f "tmp-cleaner.sh" 2>/dev/null || true
    nohup bash "$PROJECT_DIR/scripts/tmp-cleaner.sh" > /dev/null 2>&1 &
    echo "[OK] tmp-cleaner daemon started (PID $!, cleans /tmp/clawoss-* every 5m)"
fi

# ── 18. Trigger dashboard PR sync ──────────────────────────────────────
# Sync GitHub PR data to dashboard so it shows current stats immediately
smoke_sleep 5  # Wait for gateway to be fully ready
DASH_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}"
DASH_KEY="${CLAW_API_KEY:-}"
if [ "$SMOKE_MODE" -eq 1 ]; then
    echo "[INFO] Smoke mode: skipping dashboard PR sync"
elif [ -n "$DASH_KEY" ]; then
    SYNC_RESULT=$(curl -s --max-time 30 "${DASH_URL}/api/github/sync" 2>/dev/null)
    SYNCED=$(echo "$SYNC_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('synced',0))" 2>/dev/null || echo "0")
    echo "[OK] Dashboard PR sync: $SYNCED PRs synced"
else
    echo "[WARN] CLAW_API_KEY not set — skipping dashboard sync"
fi

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== ClawOSS V10 Running ==="
echo "  Model: minimax/m2.7 (MiniMax M2.7, 204k context) + kimi-coding/k2p5 fallback"
echo "  Dashboard: https://clawoss-dashboard.vercel.app"
echo "  Slots: 3 always-on (scout + PR monitor + PR analyst) + 10 impl/followup = 13"
echo "  Heartbeat: 5m"
echo "  Logs: openclaw logs"
echo "  PRs: gh search prs --author BillionClaw --state open"
echo "  Stop: openclaw gateway stop && pkill -f dashboard-sync"
echo ""
echo "V10.1 features: P(merge) scoring, no per-repo PR cap,"
echo "7-niche discovery, always-on agents with no timeout (runTimeoutSeconds:0),"
echo "rework-not-close, lock-file dedup, CLA auto-signing, unconditional ANNOUNCE_SKIP."
echo ""
echo "The agent runs independently via OpenClaw gateway — no manual intervention needed."
