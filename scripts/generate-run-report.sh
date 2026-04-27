#!/usr/bin/env bash
# generate-run-report.sh - Generate a markdown report for the current ClawOSS run.
# Usage: generate-run-report.sh

set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  echo "Usage: generate-run-report.sh"
  echo "Writes reports/run-report-YYYYmmdd-HHMMSS.md and prints it to stdout."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAWOSS_PROJECT_DIR:-${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}}"
WORKSPACE_DIR="${CLAWOSS_WORKSPACE:-${WORKSPACE_DIR:-$PROJECT_DIR/workspace}}"
MEMORY_DIR="$WORKSPACE_DIR/memory"
REPORT_DIR="$PROJECT_DIR/reports"
REPORT_PATH="$REPORT_DIR/run-report-$(date +%Y%m%d-%H%M%S).md"
DASHBOARD_URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

mkdir -p "$REPORT_DIR" "$MEMORY_DIR"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

write_empty_json() {
  printf '{}\n' > "$1"
}

fetch_json() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 10 "$url" > "$output" 2>/dev/null || write_empty_json "$output"
  else
    write_empty_json "$output"
  fi
}

fetch_json "$DASHBOARD_URL/api/metrics/overview" "$TMP_DIR/overview.json"
fetch_json "$DASHBOARD_URL/api/github/prs?limit=100" "$TMP_DIR/prs.json"
fetch_json "$DASHBOARD_URL/api/logs?limit=200" "$TMP_DIR/logs.json"
fetch_json "$DASHBOARD_URL/api/state" "$TMP_DIR/state.json"

set +e
PROJECT_DIR="$PROJECT_DIR" \
CLAWOSS_PROJECT_DIR="$PROJECT_DIR" \
CLAWOSS_WORKSPACE="$WORKSPACE_DIR" \
bash "$SCRIPT_DIR/budget-check.sh" > "$TMP_DIR/budget.json" 2>/dev/null
BUDGET_EXIT=$?
set -e
if ! python3 -m json.tool "$TMP_DIR/budget.json" >/dev/null 2>&1; then
  printf '{"within_budget":false,"tokens_used":0,"tokens_budget":0,"cost_used":0,"cost_budget":0}\n' > "$TMP_DIR/budget.json"
fi

GITHUB_ACCOUNT="${GITHUB_USERNAME:-unknown}"
if command -v gh >/dev/null 2>&1; then
  GITHUB_ACCOUNT=$(gh api user --jq '.login' 2>/dev/null || printf '%s' "$GITHUB_ACCOUNT")
fi

_REPORT_PATH="$REPORT_PATH" \
_PROJECT_DIR="$PROJECT_DIR" \
_WORKSPACE_DIR="$WORKSPACE_DIR" \
_MEMORY_DIR="$MEMORY_DIR" \
_OVERVIEW_JSON="$TMP_DIR/overview.json" \
_PRS_JSON="$TMP_DIR/prs.json" \
_LOGS_JSON="$TMP_DIR/logs.json" \
_STATE_JSON="$TMP_DIR/state.json" \
_BUDGET_JSON="$TMP_DIR/budget.json" \
_BUDGET_EXIT="$BUDGET_EXIT" \
_MODEL="${CLAWOSS_MODEL:-openai/gpt-5.5}" \
_FALLBACK_MODEL="${CLAWOSS_FALLBACK_MODEL:-openai/gpt-5.5}" \
_GITHUB_ACCOUNT="$GITHUB_ACCOUNT" \
python3 - <<'PY'
import datetime as dt
import json
import os
import re
from pathlib import Path


def load_json(path, default):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError):
        return default


def read_text(path, limit=80_000):
    try:
        data = Path(path).read_text()
    except OSError:
        return ""
    if len(data) > limit:
        return data[-limit:]
    return data


def count_queue_items(path):
    text = read_text(path)
    return sum(1 for line in text.splitlines() if re.match(r"^\s*-\s+\[", line))


def parse_time(value):
    if not value:
        return None
    if isinstance(value, (int, float)):
        raw = value / 1000 if value > 10_000_000_000 else value
        return dt.datetime.fromtimestamp(raw, tz=dt.timezone.utc)
    if isinstance(value, str):
        try:
            return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def human_duration(seconds):
    seconds = max(0, int(seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def table_or_none(items):
    return items if items else ["none"]


report_path = Path(os.environ["_REPORT_PATH"])
memory_dir = Path(os.environ["_MEMORY_DIR"])

overview = load_json(os.environ["_OVERVIEW_JSON"], {})
prs = load_json(os.environ["_PRS_JSON"], {})
logs = load_json(os.environ["_LOGS_JSON"], {})
state = load_json(os.environ["_STATE_JSON"], {})
budget = load_json(os.environ["_BUDGET_JSON"], {})

cycles = load_json(memory_dir / "heartbeat-cycles.json", {})
cycle_count = int(cycles.get("cycle_count") or 0)
first_cycle = parse_time(cycles.get("first_cycle_at") or cycles.get("first_cycle"))
last_cycle = parse_time(cycles.get("last_cycle_at") or cycles.get("last_cycle"))

agent_status = overview.get("agentStatus") or {}
stats = overview.get("stats") or {}
daily_budget = overview.get("dailyBudget") or {}
runtime_seconds = int(agent_status.get("uptimeSeconds") or 0)
if first_cycle and last_cycle:
    runtime_seconds = int((last_cycle - first_cycle).total_seconds())

queue_count = count_queue_items(memory_dir / "work-queue.md")
staging_count = count_queue_items(memory_dir / "work-queue-staging.md")
state_queue = ((state.get("state") or {}).get("workQueue") or [])
if isinstance(state_queue, list):
    candidates_discovered = max(queue_count + staging_count, len(state_queue))
else:
    candidates_discovered = queue_count + staging_count

impl_state = read_text(memory_dir / "impl-spawn-state.md")
tasks_attempted = 0
for line in impl_state.splitlines():
    if "|" in line and not re.search(r"issue_url|---|Active", line):
        tasks_attempted += 1

pr_data = prs.get("data") if isinstance(prs, dict) else []
if not isinstance(pr_data, list):
    pr_data = []
total_prs = int(stats.get("totalPRs") or len(pr_data))
recent_prs = [
    f"- {pr.get('repo', 'unknown')}#{pr.get('number', '?')}: {pr.get('title', '').strip()} ({pr.get('status', 'unknown')})"
    for pr in pr_data[:10]
]

dry_run_log = read_text(memory_dir / "dry-run-log.md")
dry_run_steps = len(
    re.findall(r"PR creation skipped|Status:\s*SKIPPED\s*\(dry-run\)", dry_run_log, re.I)
)

failure_log = read_text(memory_dir / "failure-log.md")
failure_reasons = []
for source in [failure_log]:
    for match in re.finditer(r"(?:failure_reason|reason)\s*[:=]\s*([A-Za-z0-9_-]+)", source):
        failure_reasons.append(match.group(1))
for entry in logs.get("entries", []) if isinstance(logs, dict) else []:
    message = str(entry.get("message", ""))
    if re.search(r"fail|error|abandon", message, re.I):
        failure_reasons.append(message[:140])
failure_reasons = list(dict.fromkeys(failure_reasons))[:20]

budget_pauses = read_text(memory_dir / "budget-pauses.md")
guardrail_triggers = []
if not budget.get("within_budget", True):
    guardrail_triggers.append("budget_exceeded")
if budget_pauses.strip():
    guardrail_triggers.append("budget_pause_logged")
for entry in logs.get("entries", []) if isinstance(logs, dict) else []:
    message = str(entry.get("message", ""))
    if re.search(r"budget|pause|guardrail", message, re.I):
        guardrail_triggers.append(message[:140])
guardrail_triggers = list(dict.fromkeys(guardrail_triggers))[:20]

generated_at = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
model = os.environ["_MODEL"]
fallback_model = os.environ["_FALLBACK_MODEL"]
github_account = os.environ["_GITHUB_ACCOUNT"]

lines = [
    f"# ClawOSS Run Report",
    "",
    f"Generated: {generated_at}",
    "",
    "## Runtime",
    f"- Runtime duration: {human_duration(runtime_seconds)}",
    f"- Heartbeat cycle count: {cycle_count}",
    f"- First cycle: {first_cycle.isoformat() if first_cycle else 'unknown'}",
    f"- Last cycle: {last_cycle.isoformat() if last_cycle else 'unknown'}",
    "",
    "## Runtime Identity",
    f"- Model: {model}",
    f"- Fallback model: {fallback_model}",
    f"- GitHub account: {github_account}",
    "",
    "## Work Summary",
    f"- Candidates discovered: {candidates_discovered}",
    f"- Tasks attempted: {tasks_attempted}",
    f"- Dashboard total PRs: {total_prs}",
    f"- PRs created today: {daily_budget.get('dailyPRs', 0)}",
    f"- Dry-run PR steps logged: {dry_run_steps}",
    "",
    "## PRs Created Or Dry-Run Steps",
    *table_or_none(recent_prs),
    "",
    "## Failures",
    *[f"- {item}" for item in table_or_none(failure_reasons)],
    "",
    "## Token And Cost",
    f"- Tokens consumed: {budget.get('tokens_used', 0)} / {budget.get('tokens_budget', 0)}",
    f"- Cost consumed: ${float(budget.get('cost_used', 0)):.6f} / ${float(budget.get('cost_budget', 0)):.2f}",
    f"- Within budget: {str(bool(budget.get('within_budget', False))).lower()}",
    f"- Budget check exit code: {os.environ['_BUDGET_EXIT']}",
    "",
    "## Budget And Pause Guardrails",
    *[f"- {item}" for item in table_or_none(guardrail_triggers)],
    "",
]

report_path.write_text("\n".join(lines))
PY

cat "$REPORT_PATH"
