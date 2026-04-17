#!/usr/bin/env bash
# ClawOSS Linux container entrypoint.
#
# Responsibilities:
#   1. Validate required env vars (fail fast and loudly — the whole point of
#      Task #5 was that silent failures waste tokens).
#   2. Link the workspace into $HOME/.openclaw/ the same way setup.sh does on
#      the host.
#   3. Run scripts/restart.sh in a Linux-aware path so config gets deployed
#      into $HOME/.openclaw/openclaw.json.
#   4. Exec `openclaw gateway run` as PID 1 so Docker can supervise it.

set -euo pipefail

log() { printf '[clawoss-docker] %s\n' "$*"; }
fail() { printf '[clawoss-docker][FAIL] %s\n' "$*" >&2; exit 1; }

# ── 0. Required env vars ──────────────────────────────────────────────
REQUIRED=(GITHUB_TOKEN LLM_API_KEY LLM_PROVIDER LLM_BASE_URL LLM_MODEL_COMPLEX LLM_MODEL_SIMPLE)
MISSING=()
for v in "${REQUIRED[@]}"; do
  if [ -z "${!v:-}" ]; then
    MISSING+=("$v")
  fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
  fail "missing required env: ${MISSING[*]} (see .env.example)"
fi

# Optional but strongly recommended — warn, don't fail.
for v in BUDGET_USD_TOTAL CLAW_API_KEY DASHBOARD_URL; do
  if [ -z "${!v:-}" ]; then
    log "[WARN] $v not set"
  fi
done

# ── 1. Link workspace ─────────────────────────────────────────────────
PROJECT_DIR="/app"
WORKSPACE_DIR="$PROJECT_DIR/workspace"
OC_DIR="$HOME/.openclaw"
mkdir -p "$OC_DIR/logs" "$OC_DIR/agents"

if [ ! -L "$OC_DIR/workspace" ]; then
  ln -sfn "$WORKSPACE_DIR" "$OC_DIR/workspace"
  log "linked workspace: $OC_DIR/workspace -> $WORKSPACE_DIR"
fi

# ── 2. Deploy resolved openclaw.json ──────────────────────────────────
# Mirrors the sed substitution in scripts/restart.sh. Kept in-entrypoint so
# the container can come up without invoking the full restart.sh (which also
# does macOS-specific work like launchd).
RESOLVED_CONFIG=$(sed \
  -e "s|__WORKSPACE_PATH__|$WORKSPACE_DIR|g" \
  -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
  -e "s|__HOME_DIR__|$HOME|g" \
  -e "s|__LLM_PROVIDER__|${LLM_PROVIDER}|g" \
  -e "s|__LLM_BASE_URL__|${LLM_BASE_URL}|g" \
  -e "s|__LLM_MODEL_COMPLEX__|${LLM_MODEL_COMPLEX}|g" \
  -e "s|__LLM_MODEL_SIMPLE__|${LLM_MODEL_SIMPLE}|g" \
  -e "s|__INPUT_COST_PER_M_COMPLEX__|${INPUT_COST_PER_M_COMPLEX:-${INPUT_COST_PER_M:-3.0}}|g" \
  -e "s|__OUTPUT_COST_PER_M_COMPLEX__|${OUTPUT_COST_PER_M_COMPLEX:-${OUTPUT_COST_PER_M:-15.0}}|g" \
  -e "s|__INPUT_COST_PER_M_SIMPLE__|${INPUT_COST_PER_M_SIMPLE:-${INPUT_COST_PER_M:-3.0}}|g" \
  -e "s|__OUTPUT_COST_PER_M_SIMPLE__|${OUTPUT_COST_PER_M_SIMPLE:-${OUTPUT_COST_PER_M:-15.0}}|g" \
  -e "s|__LLM_CONTEXT_WINDOW__|${LLM_CONTEXT_WINDOW:-200000}|g" \
  -e "s|__LLM_MAX_TOKENS__|${LLM_MAX_TOKENS:-32000}|g" \
  "$PROJECT_DIR/config/openclaw.json")

# Inject env block (API key + token + budget + pricing) so openclaw has
# everything it needs to authenticate.
echo "$RESOLVED_CONFIG" | python3 -c "
import json, os, sys
merged = json.load(sys.stdin)
env = merged.setdefault('env', {})
keys = [
  'LLM_API_KEY','LLM_BASE_URL','LLM_PROVIDER',
  'LLM_MODEL_COMPLEX','LLM_MODEL_SIMPLE',
  'GITHUB_TOKEN','GITHUB_USERNAME','GITHUB_EMAIL',
  'CLAW_API_KEY','DASHBOARD_URL',
  'BUDGET_USD_TOTAL','MODEL_TOKEN_BUDGETS',
  'INPUT_COST_PER_M','OUTPUT_COST_PER_M',
  'INPUT_COST_PER_M_COMPLEX','OUTPUT_COST_PER_M_COMPLEX',
  'INPUT_COST_PER_M_SIMPLE','OUTPUT_COST_PER_M_SIMPLE',
]
for k in keys:
  v = os.environ.get(k)
  if v:
    env[k] = v
merged['env'] = env
json.dump(merged, open('$OC_DIR/openclaw.json','w'), indent=2)
"

log "deployed $OC_DIR/openclaw.json"

# ── 3. GitHub CLI auth (non-interactive token login) ──────────────────
if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1 || \
    log "[WARN] gh auth login --with-token failed; gh commands may 401"
fi

# Git identity — PRs need author info.
git config --global user.name  "${GITHUB_USERNAME:-clawoss-bot}"
git config --global user.email "${GITHUB_EMAIL:-${GITHUB_USERNAME:-clawoss-bot}@users.noreply.github.com}"

# ── 4. Register agent + hand off to gateway ───────────────────────────
AGENT_MODEL="${LLM_PROVIDER}/${LLM_MODEL_SIMPLE}"
if ! openclaw agents list 2>/dev/null | grep -q "^- clawoss "; then
  openclaw agents add clawoss \
    --workspace "$WORKSPACE_DIR" \
    --model "$AGENT_MODEL" \
    --non-interactive
  log "registered agent clawoss (model=$AGENT_MODEL)"
fi

log "starting openclaw gateway (foreground)"
exec openclaw gateway run
