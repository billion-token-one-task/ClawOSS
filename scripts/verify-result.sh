#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
MEMORY_DIR="$WORKSPACE_DIR/memory"
MISSION_PATH="${MISSION_PATH:-$PROJECT_DIR/config/mission.json}"
GH_BIN="${GH_BIN:-gh}"
REPO_HEALTH_SCRIPT="${CLAWOSS_REPO_HEALTH_CHECK_SCRIPT:-$PROJECT_DIR/scripts/repo-health-check.sh}"

GATE_NAME="${1:-}"
if [ -z "$GATE_NAME" ]; then
  echo '{"pass":false,"error":"Usage: verify-result.sh <gate-name>"}'
  exit 1
fi

if [ ! -f "$MISSION_PATH" ]; then
  echo "{\"pass\":false,\"gate\":$(printf '%s' "$GATE_NAME" | jq -R .),\"error\":\"mission file not found: $MISSION_PATH\"}"
  exit 1
fi

json_string() {
  jq -Rn --arg value "$1" '$value'
}

json_array_from_lines() {
  if [ $# -eq 0 ]; then
    printf '[]\n'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

resolve_project_path() {
  local rel="$1"
  printf '%s/%s\n' "$PROJECT_DIR" "$rel"
}

gate_exists="$(jq -r --arg gate "$GATE_NAME" '.gates[$gate] != null' "$MISSION_PATH")"
if [ "$gate_exists" != "true" ]; then
  echo "{\"pass\":false,\"gate\":$(json_string "$GATE_NAME"),\"error\":\"unknown gate\"}"
  exit 1
fi

mapfile -t required_files < <(jq -r --arg gate "$GATE_NAME" '.gates[$gate].requires_files[]? // empty' "$MISSION_PATH")
mapfile -t checks < <(jq -r --arg gate "$GATE_NAME" '.gates[$gate].checks[]? // empty' "$MISSION_PATH")

failures=()
passes=()

find_required_fields_for_file() {
  local rel="$1"
  jq -r --arg rel "$rel" '
    .work_units
    | to_entries[]
    | select(.value.output.file == $rel)
    | .value.output.required_fields[]?
  ' "$MISSION_PATH"
}

validate_output_contract_file() {
  local rel="$1"
  local abs
  abs="$(resolve_project_path "$rel")"

  if [ ! -f "$abs" ]; then
    failures+=("missing required file: $rel")
    return 1
  fi

  if ! jq . "$abs" >/dev/null 2>&1; then
    failures+=("invalid json: $rel")
    return 1
  fi

  local missing=()
  while IFS= read -r field; do
    [ -z "$field" ] && continue
    if ! jq -e --arg field "$field" 'has($field) and .[$field] != null' "$abs" >/dev/null 2>&1; then
      missing+=("$field")
    fi
  done < <(find_required_fields_for_file "$rel")

  if [ "${#missing[@]}" -gt 0 ]; then
    failures+=("missing required fields in $rel: ${missing[*]}")
    return 1
  fi

  return 0
}

check_output_contract() {
  local failed=0
  local rel
  for rel in "${required_files[@]}"; do
    if ! validate_output_contract_file "$rel"; then
      failed=1
    fi
  done
  return "$failed"
}

read_task_field() {
  local field="$1"
  jq -r --arg field "$field" '.[$field]' "$(resolve_project_path "workspace/memory/task-envelope.json")"
}

read_pr_field() {
  local field="$1"
  jq -r --arg field "$field" '.[$field]' "$(resolve_project_path "workspace/memory/pr-info.json")"
}

read_result_field() {
  local field="$1"
  jq -r --arg field "$field" '.[$field]' "$(resolve_project_path "workspace/memory/last-result.json")"
}

resolve_pre_submit_repo_dir() {
  local repo_path
  repo_path="$(read_result_field "repo_path")"

  if [ -z "$repo_path" ] || [ "$repo_path" = "null" ]; then
    failures+=("last-result repo_path is missing")
    return 1
  fi

  if [ ! -d "$repo_path" ]; then
    failures+=("last-result repo_path does not exist: $repo_path")
    return 1
  fi

  if ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    failures+=("last-result repo_path is not a git worktree: $repo_path")
    return 1
  fi

  printf '%s\n' "$repo_path"
}

check_dedup_ledger() {
  local repo issue ledger
  repo="$(read_task_field "repo")"
  issue="$(read_task_field "issue_number")"
  ledger="$MEMORY_DIR/pr-ledger.md"

  if [ ! -f "$ledger" ]; then
    failures+=("missing ledger: workspace/memory/pr-ledger.md")
    return 1
  fi

  if grep -F "$repo" "$ledger" | grep -Eq "(#|\\|[[:space:]]*)${issue}(\\||[[:space:]]|$)"; then
    failures+=("repo+issue already exists in pr-ledger.md: ${repo}#${issue}")
    return 1
  fi

  return 0
}

check_recent_failure_window() {
  local task_file log_file recent_failure_message
  task_file="$(resolve_project_path "workspace/memory/task-envelope.json")"
  log_file="$MEMORY_DIR/failure-log.md"

  [ -f "$log_file" ] || return 0

  recent_failure_message="$(python3 - "$task_file" "$log_file" <<'PY'
import json
import sys
from datetime import datetime, timedelta, timezone

task_path, log_path = sys.argv[1], sys.argv[2]
task = json.load(open(task_path, "r", encoding="utf-8"))
repo = str(task.get("repo", ""))
issue = str(task.get("issue_number", ""))
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
count = 0

for raw in open(log_path, "r", encoding="utf-8"):
    line = raw.strip()
    if not line.startswith("|") or line.startswith("| timestamp ") or line.startswith("|-----------"):
        continue
    parts = [p.strip() for p in line.strip("|").split("|")]
    if len(parts) < 4:
        continue
    timestamp, entry_repo, entry_issue = parts[0], parts[1], parts[2]
    if entry_repo != repo or entry_issue not in {issue, f"#{issue}"}:
        continue
    try:
        when = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        continue
    if when >= cutoff:
        count += 1

if count >= 2:
    print(f"recent repeated failures found for {repo}#{issue}: {count}")
    sys.exit(1)

sys.exit(0)
PY
)"
  if [ -n "$recent_failure_message" ]; then
    failures+=("$recent_failure_message")
    return 1
  fi
  return 0
}

check_issue_open() {
  local repo issue payload state assignees
  repo="$(read_task_field "repo")"
  issue="$(read_task_field "issue_number")"
  payload="$("$GH_BIN" issue view "$issue" --repo "$repo" --json state,assignees 2>/dev/null)" || {
    failures+=("gh issue view failed for ${repo}#${issue}")
    return 1
  }

  state="$(printf '%s' "$payload" | jq -r '.state // empty')"
  assignees="$(printf '%s' "$payload" | jq -r '.assignees | length')"

  if [ "$state" != "OPEN" ]; then
    failures+=("issue is not open: ${repo}#${issue} state=${state:-unknown}")
    return 1
  fi

  if [ "$assignees" -gt 0 ]; then
    failures+=("issue has assignees: ${repo}#${issue}")
    return 1
  fi

  return 0
}

repo_is_trusted() {
  local repo trust_file
  repo="$1"
  trust_file="$MEMORY_DIR/trust-repos.md"
  [ -f "$trust_file" ] || return 1
  grep -F "$repo" "$trust_file" >/dev/null 2>&1
}

check_repo_health() {
  local repo
  repo="$(read_task_field "repo")"
  if ! "$REPO_HEALTH_SCRIPT" "$repo" >/dev/null 2>&1; then
    if repo_is_trusted "$repo"; then
      return 0
    fi
    failures+=("repo health check failed: $repo")
    return 1
  fi
  return 0
}

check_task_type_scope() {
  local task_type
  task_type="$(read_task_field "task_type")"
  case "$task_type" in
    bug|docs|typo|test)
      return 0
      ;;
    *)
      failures+=("task type is outside mission scope: ${task_type:-<empty>}")
      return 1
      ;;
  esac
}

check_diff_size() {
  local max_lines total repo_dir
  repo_dir="$(resolve_pre_submit_repo_dir)" || return 1
  max_lines="$(jq -r '.constraints.resource_limits.max_pr_size_lines' "$MISSION_PATH")"
  total="$(git -C "$repo_dir" diff --numstat HEAD 2>/dev/null | awk 'BEGIN{sum=0} $1 ~ /^[0-9]+$/ {sum += $1} $2 ~ /^[0-9]+$/ {sum += $2} END {print sum+0}')"
  if [ "${total:-0}" -gt "$max_lines" ]; then
    failures+=("diff too large: ${total} > ${max_lines}")
    return 1
  fi
  return 0
}

check_forbidden_paths() {
  local path repo_dir bad=()
  repo_dir="$(resolve_pre_submit_repo_dir)" || return 1
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      case "$path" in
        $pattern)
          bad+=("$path")
          break
          ;;
      esac
    done < <(jq -r '.constraints.forbidden_paths[]' "$MISSION_PATH")
  done < <(git -C "$repo_dir" diff --name-only HEAD 2>/dev/null)

  if [ "${#bad[@]}" -gt 0 ]; then
    failures+=("forbidden paths changed: ${bad[*]}")
    return 1
  fi
  return 0
}

check_branch_name() {
  local branch matched=1 repo_dir
  repo_dir="$(resolve_pre_submit_repo_dir)" || return 1
  branch="$(git -C "$repo_dir" branch --show-current 2>/dev/null || true)"
  while IFS= read -r prefix; do
    if [[ "$branch" == "$prefix"* ]]; then
      matched=0
      break
    fi
  done < <(jq -r '.constraints.branch_prefixes[]' "$MISSION_PATH")

  if [ "$matched" -ne 0 ]; then
    failures+=("branch name does not match allowed prefixes: ${branch:-<empty>}")
    return 1
  fi
  return 0
}

check_pr_exists() {
  local pr_url
  pr_url="$(read_pr_field "pr_url")"
  if ! "$GH_BIN" pr view "$pr_url" --json state >/dev/null 2>&1; then
    failures+=("gh pr view failed for $pr_url")
    return 1
  fi
  return 0
}

check_pr_is_open() {
  local pr_url state
  pr_url="$(read_pr_field "pr_url")"
  state="$("$GH_BIN" pr view "$pr_url" --json state 2>/dev/null | jq -r '.state // empty')" || {
    failures+=("gh pr view failed for $pr_url")
    return 1
  }
  if [ "$state" != "OPEN" ]; then
    failures+=("pr is not open: ${pr_url} state=${state:-unknown}")
    return 1
  fi
  return 0
}

check_ledger_entry_present() {
  local repo issue pr_url ledger
  repo="$(read_pr_field "repo")"
  issue="$(read_pr_field "issue_number")"
  pr_url="$(read_pr_field "pr_url")"
  ledger="$MEMORY_DIR/pr-ledger.md"

  if ! grep -F "$pr_url" "$ledger" >/dev/null 2>&1 || ! grep -F "$repo" "$ledger" >/dev/null 2>&1; then
    failures+=("pr ledger entry missing for $pr_url")
    return 1
  fi

  if ! grep -F "$issue" "$ledger" >/dev/null 2>&1; then
    failures+=("pr ledger issue number missing for $pr_url")
    return 1
  fi

  return 0
}

check_pr_resolved() {
  local pr_url state
  pr_url="$(read_pr_field "pr_url")"
  state="$("$GH_BIN" pr view "$pr_url" --json state 2>/dev/null | jq -r '.state // empty')" || {
    failures+=("gh pr view failed for $pr_url")
    return 1
  }
  case "$state" in
    MERGED|CLOSED) return 0 ;;
    *)
      failures+=("pr not resolved yet: ${pr_url} state=${state:-unknown}")
      return 1
      ;;
  esac
}

check_followup_detected() {
  local pr_url payload decision comments_count
  pr_url="$(read_pr_field "pr_url")"
  payload="$("$GH_BIN" pr view "$pr_url" --json reviewDecision,comments 2>/dev/null)" || {
    failures+=("gh pr view failed for $pr_url")
    return 1
  }
  decision="$(printf '%s' "$payload" | jq -r '.reviewDecision // empty')"
  comments_count="$(printf '%s' "$payload" | jq -r '.comments | if type == "object" and has("totalCount") then .totalCount else length end')"

  if [ "$decision" = "CHANGES_REQUESTED" ]; then
    return 0
  fi

  if [ "${comments_count:-0}" -gt 0 ]; then
    return 0
  fi

  failures+=("no follow-up signal detected for $pr_url")
  return 1
}

for check in "${checks[@]}"; do
  if "check_${check}"; then
    passes+=("$check")
  fi
done

if [ "${#failures[@]}" -gt 0 ]; then
  printf '{"pass":false,"gate":%s,"checks_passed":%s,"failures":%s}\n' \
    "$(json_string "$GATE_NAME")" \
    "$(json_array_from_lines "${passes[@]}")" \
    "$(json_array_from_lines "${failures[@]}")"
  exit 1
fi

printf '{"pass":true,"gate":%s,"checks_passed":%s,"failures":[]}\n' \
  "$(json_string "$GATE_NAME")" \
  "$(json_array_from_lines "${passes[@]}")"
