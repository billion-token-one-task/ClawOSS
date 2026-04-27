#!/usr/bin/env bash
# budget-check.sh — Check token and cost budgets for continuous running.
# Usage: budget-check.sh [--local-only]

set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  echo "Usage: budget-check.sh [--local-only]"
  echo "Outputs JSON and exits 0 when within budget, 1 when exceeded."
  exit 0
fi

LOCAL_ONLY=false
if [ "${1:-}" = "--local-only" ]; then
  LOCAL_ONLY=true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAWOSS_PROJECT_DIR:-${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}}"
WORKSPACE_DIR="${CLAWOSS_WORKSPACE:-${WORKSPACE_DIR:-$PROJECT_DIR/workspace}}"
MEMORY_DIR="$WORKSPACE_DIR/memory"
USAGE_FILE="${CLAWOSS_BUDGET_USAGE_FILE:-$MEMORY_DIR/budget-usage.json}"
STATUS_FILE="${CLAWOSS_BUDGET_STATUS_FILE:-$MEMORY_DIR/budget-status.json}"
SESSIONS_DIR="${CLAWOSS_SESSIONS_DIR:-$HOME/.openclaw/agents/clawoss/sessions}"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

mkdir -p "$MEMORY_DIR"

TOKEN_BUDGET="${CLAWOSS_TOKEN_BUDGET:-1000000}"
COST_BUDGET="${CLAWOSS_COST_BUDGET:-50.00}"
DASHBOARD_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}"
MODEL="${CLAWOSS_MODEL:-openai/gpt-5.5}"

DASHBOARD_JSON=""
if [ "$LOCAL_ONLY" = false ] && command -v curl >/dev/null 2>&1; then
  DASHBOARD_JSON=$(curl -fsS --max-time 5 "$DASHBOARD_URL/api/metrics/overview" 2>/dev/null || true)
fi

_DASHBOARD_JSON="$DASHBOARD_JSON" \
_TOKEN_BUDGET="$TOKEN_BUDGET" \
_COST_BUDGET="$COST_BUDGET" \
_USAGE_FILE="$USAGE_FILE" \
_STATUS_FILE="$STATUS_FILE" \
_SESSIONS_DIR="$SESSIONS_DIR" \
_MODEL="$MODEL" \
python3 - <<'PY'
import datetime as dt
import glob
import json
import os
import sys


def number(value, default=0.0):
    try:
        if value is None or value == "":
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def int_number(value, default=0):
    return int(number(value, default))


PRICE_MODELS = {
    "openai/gpt-5.5": (5.0 / 1_000_000, 30.0 / 1_000_000),
    "openai/gpt-5.4": (2.5 / 1_000_000, 15.0 / 1_000_000),
    "openai/gpt-5": (1.25 / 1_000_000, 10.0 / 1_000_000),
    "kimi-coding/k2p5": (0.6 / 1_000_000, 3.0 / 1_000_000),
    "minimax/MiniMax-M2.7": (0.3 / 1_000_000, 1.2 / 1_000_000),
}


def token_cost(input_tokens, output_tokens, model):
    input_cost, output_cost = PRICE_MODELS.get(model, PRICE_MODELS["openai/gpt-5.5"])
    return input_tokens * input_cost + output_tokens * output_cost


def read_dashboard_usage():
    raw = os.environ.get("_DASHBOARD_JSON", "").strip()
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    stats = data.get("stats") or {}
    if not isinstance(stats, dict):
        return None
    input_tokens = int_number(stats.get("inputTokensToday"))
    output_tokens = int_number(stats.get("outputTokensToday"))
    total_tokens = int_number(stats.get("tokensUsedToday"), input_tokens + output_tokens)
    cost = number(stats.get("costToday"))
    return total_tokens, cost, "dashboard"


def read_usage_file():
    path = os.environ["_USAGE_FILE"]
    if not os.path.isfile(path):
        return None
    try:
        with open(path) as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return None

    today = dt.datetime.now().date().isoformat()
    usage_date = data.get("date") or data.get("day")
    if usage_date and usage_date != today:
        return None

    input_tokens = int_number(data.get("input_tokens") or data.get("inputTokens"))
    output_tokens = int_number(data.get("output_tokens") or data.get("outputTokens"))
    total_tokens = int_number(data.get("tokens_used") or data.get("tokensUsed"), input_tokens + output_tokens)
    cost = number(data.get("cost_used") or data.get("costUsed") or data.get("cost_usd") or data.get("costUsd"))
    return total_tokens, cost, "local_file"


def event_timestamp(event):
    raw = event.get("timestamp") or event.get("createdAt") or event.get("time")
    if not raw:
        return None
    if isinstance(raw, (int, float)):
        value = raw / 1000 if raw > 10_000_000_000 else raw
        return dt.datetime.fromtimestamp(value, tz=dt.timezone.utc)
    if isinstance(raw, str):
        try:
            return dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def read_session_usage():
    sessions_dir = os.environ["_SESSIONS_DIR"]
    default_model = os.environ.get("_MODEL") or "openai/gpt-5.5"
    if not os.path.isdir(sessions_dir):
        return 0, 0.0, "empty"

    now = dt.datetime.now().astimezone()
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    tokens = 0
    cost = 0.0

    for path in glob.glob(os.path.join(sessions_dir, "*.jsonl")):
        name = os.path.basename(path)
        if ".reset." in name or name == "sessions.json":
            continue
        try:
            if dt.datetime.fromtimestamp(os.path.getmtime(path), tz=day_start.tzinfo) < day_start:
                continue
        except OSError:
            continue
        try:
            handle = open(path)
        except OSError:
            continue
        with handle:
            for line in handle:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = event_timestamp(event)
                if ts and ts.astimezone(day_start.tzinfo) < day_start:
                    continue
                message = event.get("message") or {}
                usage = message.get("usage") or event.get("usage") or {}
                if not isinstance(usage, dict):
                    continue
                input_tokens = int_number(
                    usage.get("input")
                    or usage.get("input_tokens")
                    or usage.get("inputTokens")
                )
                output_tokens = int_number(
                    usage.get("output")
                    or usage.get("output_tokens")
                    or usage.get("outputTokens")
                )
                if input_tokens == 0 and output_tokens == 0:
                    continue
                model = message.get("model") or event.get("model") or default_model
                tokens += input_tokens + output_tokens
                cost += token_cost(input_tokens, output_tokens, model)

    return tokens, cost, "session_scan"


tokens_budget = int_number(os.environ.get("_TOKEN_BUDGET"), 1_000_000)
cost_budget = number(os.environ.get("_COST_BUDGET"), 50.0)

usage = read_dashboard_usage() or read_usage_file() or read_session_usage()
tokens_used, cost_used, source = usage

token_exceeded = tokens_budget > 0 and tokens_used > tokens_budget
cost_exceeded = cost_budget > 0 and cost_used > cost_budget
within_budget = not token_exceeded and not cost_exceeded

result = {
    "within_budget": within_budget,
    "tokens_used": int(tokens_used),
    "tokens_budget": int(tokens_budget),
    "cost_used": round(float(cost_used), 6),
    "cost_budget": round(float(cost_budget), 6),
}

status = dict(result)
status["source"] = source
status["checked_at"] = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
try:
    status_path = os.environ["_STATUS_FILE"]
    tmp_path = f"{status_path}.tmp"
    with open(tmp_path, "w") as handle:
        json.dump(status, handle, indent=2)
        handle.write("\n")
    os.replace(tmp_path, status_path)
except OSError:
    pass

print(json.dumps(result, separators=(",", ": ")))
sys.exit(0 if within_budget else 1)
PY
