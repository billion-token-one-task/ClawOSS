#!/usr/bin/env bash
# dry-run-gate.sh — Gate GitHub PR creation behind CLAWOSS_DRY_RUN.
# Usage: dry-run-gate.sh [--repo owner/repo] [--title title] [--body-file path] [--head branch] [--base branch] [--issue url]

set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  echo "Usage: dry-run-gate.sh [--repo owner/repo] [--title title] [--body-file path] [--head branch] [--base branch] [--issue url]"
  echo "Exits 1 after logging when CLAWOSS_DRY_RUN=true; exits 0 otherwise."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="${CLAWOSS_PROJECT_DIR:-${PROJECT_DIR:-$DEFAULT_PROJECT_DIR}}"
WORKSPACE_DIR="${CLAWOSS_WORKSPACE:-${WORKSPACE_DIR:-$PROJECT_DIR/workspace}}"
MEMORY_DIR="$WORKSPACE_DIR/memory"
LOG_FILE="${CLAWOSS_DRY_RUN_LOG:-$MEMORY_DIR/dry-run-log.md}"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

DRY_RUN=$(printf '%s' "${CLAWOSS_DRY_RUN:-false}" | tr '[:upper:]' '[:lower:]')
case "$DRY_RUN" in
  true|1|yes|on) ;;
  *) exit 0 ;;
esac

REPO="${GITHUB_REPOSITORY:-}"
TITLE="${PR_TITLE:-}"
BODY="${PR_BODY:-}"
BODY_FILE=""
HEAD_BRANCH=""
BASE_BRANCH=""
ISSUE_URL=""
COMMAND=""
EXTRA_ARGS=()
RAW_ARGS="$*"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      REPO="${2:-}"; shift 2 ;;
    --title)
      TITLE="${2:-}"; shift 2 ;;
    --body)
      BODY="${2:-}"; shift 2 ;;
    --body-file)
      BODY_FILE="${2:-}"; shift 2 ;;
    --head)
      HEAD_BRANCH="${2:-}"; shift 2 ;;
    --base)
      BASE_BRANCH="${2:-}"; shift 2 ;;
    --issue)
      ISSUE_URL="${2:-}"; shift 2 ;;
    --command)
      COMMAND="${2:-}"; shift 2 ;;
    *)
      EXTRA_ARGS+=("$1"); shift ;;
  esac
done

if [ -z "$HEAD_BRANCH" ]; then
  HEAD_BRANCH=$(git branch --show-current 2>/dev/null || true)
fi

mkdir -p "$MEMORY_DIR"

_LOG_FILE="$LOG_FILE" \
_REPO="$REPO" \
_TITLE="$TITLE" \
_BODY="$BODY" \
_BODY_FILE="$BODY_FILE" \
_HEAD_BRANCH="$HEAD_BRANCH" \
_BASE_BRANCH="$BASE_BRANCH" \
_ISSUE_URL="$ISSUE_URL" \
_COMMAND="$COMMAND" \
_RAW_ARGS="$RAW_ARGS" \
_PWD="$PWD" \
_EXTRA_ARGS="$(printf '%s\n' "${EXTRA_ARGS[@]:-}")" \
python3 - <<'PY'
import datetime as dt
import os
import re


def redact(value: str) -> str:
    patterns = [
        r"ghp_[A-Za-z0-9_]+",
        r"github_pat_[A-Za-z0-9_]+",
        r"sk-[A-Za-z0-9_-]+",
        r"sk-proj-[A-Za-z0-9_-]+",
    ]
    result = value or ""
    for pattern in patterns:
        result = re.sub(pattern, "[REDACTED]", result)
    return result


body = os.environ.get("_BODY", "")
body_file = os.environ.get("_BODY_FILE", "")
if body_file:
    try:
        with open(body_file) as handle:
            body = handle.read()
    except OSError as exc:
        body = f"[unable to read body file: {exc}]"

timestamp = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")
entry = f"""## {timestamp} — PR creation skipped

- repo: {redact(os.environ.get("_REPO", "")) or "unknown"}
- title: {redact(os.environ.get("_TITLE", "")) or "unknown"}
- issue: {redact(os.environ.get("_ISSUE_URL", "")) or "unknown"}
- head: {redact(os.environ.get("_HEAD_BRANCH", "")) or "unknown"}
- base: {redact(os.environ.get("_BASE_BRANCH", "")) or "unknown"}
- working_dir: {redact(os.environ.get("_PWD", ""))}
- command: {redact(os.environ.get("_COMMAND", "")) or "gh pr create"}
- raw_args: `{redact(os.environ.get("_RAW_ARGS", ""))}`

### PR Body
```markdown
{redact(body).strip() or "[no body provided]"}
```

"""

log_file = os.environ["_LOG_FILE"]
with open(log_file, "a") as handle:
    handle.write(entry)
PY

echo "CLAWOSS_DRY_RUN=true; PR creation logged to $LOG_FILE" >&2
exit 1
