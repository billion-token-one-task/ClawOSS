#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
MEMORY_DIR="$WORKSPACE_DIR/memory"
MISSION_PATH="${MISSION_PATH:-$PROJECT_DIR/config/mission.json}"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
BUILD_PROMPT_SCRIPT="${BUILD_PROMPT_SCRIPT:-$PROJECT_DIR/scripts/build-prompt.sh}"
VERIFY_RESULT_SCRIPT="${VERIFY_RESULT_SCRIPT:-$PROJECT_DIR/scripts/verify-result.sh}"
INIT_WORKSPACE_SCRIPT="${INIT_WORKSPACE_SCRIPT:-$PROJECT_DIR/scripts/init-workspace-state.sh}"
RUN_CYCLE_ONCE="${RUN_CYCLE_ONCE:-0}"
AGENT_ID="${AGENT_ID:-clawoss}"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-900}"

STATE_FILE="$MEMORY_DIR/lifecycle-state.json"
LAST_AGENT_OUTPUT_FILE="$MEMORY_DIR/.last-agent-output.txt"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$PROJECT_DIR/.env"
  set +a
fi

if [ ! -f "$STATE_FILE" ]; then
  PROJECT_DIR="$PROJECT_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" bash "$INIT_WORKSPACE_SCRIPT" >/dev/null
fi

if [ ! -f "$MISSION_PATH" ]; then
  echo "mission file not found: $MISSION_PATH" >&2
  exit 1
fi

json_string() {
  jq -Rn --arg value "$1" '$value'
}

json_last_error() {
  local type="$1"
  local reason="$2"
  local details="${3:-}"
  jq -cn \
    --arg type "$type" \
    --arg reason "$reason" \
    --arg details "$details" \
    '
      {
        type: $type,
        reason: $reason
      }
      + (if ($details | length) > 0 then {details: $details} else {} end)
    '
}

new_session_id() {
  printf 'cycle-%s-%04d\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$RANDOM"
}

read_state_field() {
  local field="$1"
  jq -r --arg field "$field" '.[$field]' "$STATE_FILE"
}

write_state() {
  local expr="$1"
  local tmp
  tmp="$(mktemp)"
  jq "$expr" "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

set_state_values() {
  local state="$1"
  local active_task_json="$2"
  local session_id_json="$3"
  local retry_count="$4"
  local last_error_json="$5"
  local turn_count="$6"
  local consecutive_failures="$7"
  local completed_tasks="$8"
  local updated_at
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local tmp
  tmp="$(mktemp)"
  jq \
    --arg state "$state" \
    --argjson active_task "$active_task_json" \
    --argjson session_id "$session_id_json" \
    --argjson retry_count "$retry_count" \
    --argjson last_error "$last_error_json" \
    --argjson turn_count "$turn_count" \
    --argjson consecutive_failures "$consecutive_failures" \
    --argjson completed_tasks "$completed_tasks" \
    --arg updated_at "$updated_at" \
    '.state = $state
     | .active_task = $active_task
     | .session_id = $session_id
     | .retry_count = $retry_count
     | .last_error = $last_error
     | .turn_count = $turn_count
     | .consecutive_failures = $consecutive_failures
     | .completed_tasks = $completed_tasks
     | .updated_at = $updated_at' \
    "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

mission_required_fields_for_unit() {
  local unit="$1"
  jq -r --arg unit "$unit" '.work_units[$unit].output.required_fields[]?' "$MISSION_PATH"
}

mission_output_file_for_unit() {
  local unit="$1"
  jq -r --arg unit "$unit" '.work_units[$unit].output.file' "$MISSION_PATH"
}

validate_work_unit_output() {
  local unit="$1"
  local rel abs missing=()
  rel="$(mission_output_file_for_unit "$unit")"
  abs="$PROJECT_DIR/$rel"

  [ -f "$abs" ] || return 1
  jq . "$abs" >/dev/null 2>&1 || return 1

  while IFS= read -r field; do
    [ -z "$field" ] && continue
    if ! jq -e --arg field "$field" 'has($field) and .[$field] != null' "$abs" >/dev/null 2>&1; then
      missing+=("$field")
    fi
  done < <(mission_required_fields_for_unit "$unit")

  [ "${#missing[@]}" -eq 0 ]
}

implement_result_completed() {
  local result_file status
  result_file="$MEMORY_DIR/last-result.json"
  validate_work_unit_output "implement" || return 1
  status="$(jq -r '.status // empty' "$result_file" 2>/dev/null || true)"
  case "$status" in
    in_progress|"")
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

seed_implement_result_contract() {
  local task_file result_file branch branch_prefix issue slug task_type
  task_file="$MEMORY_DIR/task-envelope.json"
  result_file="$MEMORY_DIR/last-result.json"
  [ -f "$task_file" ] || return 0
  [ -f "$result_file" ] && return 0

  issue="$(jq -r '.issue_number // "task"' "$task_file")"
  task_type="$(jq -r '.task_type // "bug"' "$task_file")"
  slug="$(jq -r '.issue_title // "issue"' "$task_file" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40)"
  [ -n "$slug" ] || slug="issue"
  case "$task_type" in
    docs) branch_prefix="clawoss/docs" ;;
    test) branch_prefix="clawoss/test" ;;
    typo) branch_prefix="clawoss/typo" ;;
    *) branch_prefix="clawoss/fix" ;;
  esac
  branch="${branch_prefix}/${issue}-${slug}"

  jq -n \
    --arg task_id "$(jq -r '.task_id // ""' "$task_file")" \
    --arg branch "$branch" \
    --arg repo_path "" \
    --arg diff_summary "implementation started; result pending" \
    '{
      task_id: $task_id,
      status: "in_progress",
      branch: $branch,
      repo_path: $repo_path,
      diff_summary: $diff_summary,
      files_changed: [],
      tests_run: [],
      is_ready_to_submit: false,
      risks: []
    }' > "$result_file"
}

record_implement_failure_result() {
  local details="$1"
  local result_file tmp
  result_file="$MEMORY_DIR/last-result.json"
  seed_implement_result_contract
  tmp="$(mktemp)"
  jq \
    --arg details "$details" \
    '.status = "failed"
     | .diff_summary = (if ($details | length) > 0 then $details else "implementation failed before producing a complete result" end)
     | .is_ready_to_submit = false
     | .risks = ((.risks // []) + [ (if ($details | length) > 0 then $details else "implementation failed before producing a complete result" end) ])' \
    "$result_file" > "$tmp"
  mv "$tmp" "$result_file"
}

prepare_submit_branch() {
  local result_file repo_path branch normalized_branch issue slug task_file task_type
  result_file="$MEMORY_DIR/last-result.json"
  [ -f "$result_file" ] || return 1

  repo_path="$(jq -r '.repo_path // empty' "$result_file" 2>/dev/null || true)"
  branch="$(jq -r '.branch // empty' "$result_file" 2>/dev/null || true)"
  task_file="$MEMORY_DIR/task-envelope.json"

  if [ -z "$repo_path" ] || [ "$repo_path" = "null" ]; then
    return 1
  fi
  if [ ! -f "$task_file" ]; then
    return 1
  fi
  issue="$(jq -r '.issue_number // "task"' "$task_file" 2>/dev/null || true)"
  task_type="$(jq -r '.task_type // "bug"' "$task_file" 2>/dev/null || true)"
  slug="$(jq -r '.issue_title // "issue"' "$task_file" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-40)"
  [ -n "$slug" ] || slug="issue"
  case "$task_type" in
    docs) normalized_branch="clawoss/docs/${issue}-${slug}" ;;
    test) normalized_branch="clawoss/test/${issue}-${slug}" ;;
    typo) normalized_branch="clawoss/typo/${issue}-${slug}" ;;
    *) normalized_branch="clawoss/fix/${issue}-${slug}" ;;
  esac
  if [ -z "$branch" ] || [ "$branch" = "null" ]; then
    branch="$normalized_branch"
  fi
  case "$branch" in
    clawoss/fix/*|clawoss/docs/*|clawoss/test/*|clawoss/typo/*)
      ;;
    *)
      branch="$normalized_branch"
      ;;
  esac
  if [ -z "$branch" ]; then
    return 1
  fi
  if [ ! -d "$repo_path" ]; then
    return 1
  fi
  git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git -C "$repo_path" checkout -B "$branch" >/dev/null 2>&1 || return 1
  if [ "$branch" != "$(jq -r '.branch // empty' "$result_file" 2>/dev/null || true)" ]; then
    jq --arg branch "$branch" '.branch = $branch' "$result_file" > "${result_file}.tmp"
    mv "${result_file}.tmp" "$result_file"
  fi
}

ensure_heartbeat_disabled() {
  "$OPENCLAW_BIN" system heartbeat disable >/dev/null
}

maybe_rotate_session_on_restart() {
  local state old_session new_session
  state="$(read_state_field state)"
  old_session="$(read_state_field session_id)"
  if [ "$state" != "idle" ] && [ "$old_session" != "null" ]; then
    new_session="$(new_session_id)"
    set_state_values \
      "$state" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(json_string "$new_session")" \
      "$(read_state_field retry_count)" \
      "$(jq '.last_error' "$STATE_FILE")" \
      "$(read_state_field turn_count)" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  fi
}

reflect_triggered() {
  local every_n fail_threshold completed failures
  every_n="$(jq -r '.session_strategy.reflect_on_every_n_tasks // 5' "$MISSION_PATH")"
  fail_threshold="$(jq -r '.session_strategy.reflect_on_consecutive_failures // 3' "$MISSION_PATH")"
  completed="$(read_state_field completed_tasks)"
  failures="$(read_state_field consecutive_failures)"

  if [ "$failures" -ge "$fail_threshold" ]; then
    return 0
  fi
  if [ "$completed" -gt 0 ] && [ $((completed % every_n)) -eq 0 ]; then
    return 0
  fi
  return 1
}

has_candidates() {
  local file
  file="$MEMORY_DIR/candidates.json"
  [ -f "$file" ] || return 1
  jq -e '.candidates | type == "array" and length > 0' "$file" >/dev/null 2>&1
}

choose_idle_work_unit() {
  if reflect_triggered; then
    printf 'reflect\n'
  elif has_candidates; then
    printf 'select\n'
  else
    printf 'discover\n'
  fi
}

record_failure() {
  local reason details repo issue task_file now
  reason="$(jq -r '.last_error.reason // "failed"' "$STATE_FILE")"
  details="$(jq -r '.last_error.details // .last_error.type // "run-cycle"' "$STATE_FILE")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  task_file="$MEMORY_DIR/task-envelope.json"
  repo=""
  issue=""
  if [ -f "$task_file" ]; then
    repo="$(jq -r '.repo // ""' "$task_file")"
    issue="$(jq -r '.issue_number // ""' "$task_file")"
  fi
  printf '| %s | %s | %s | %s | %s |\n' "$now" "${repo:-}" "${issue:-}" "$reason" "$details" >> "$MEMORY_DIR/failure-log.md"
}

cleanup_workflow_files() {
  rm -f \
    "$LAST_AGENT_OUTPUT_FILE" \
    "$MEMORY_DIR/candidates.json" \
    "$MEMORY_DIR/task-envelope.json" \
    "$MEMORY_DIR/last-result.json" \
    "$MEMORY_DIR/pr-info.json" \
    "$MEMORY_DIR/followup-result.json"
}

finalize_terminal_state() {
  local state
  state="$(read_state_field state)"
  case "$state" in
    done)
      set_state_values \
        "idle" \
        "null" \
        "null" \
        0 \
        "null" \
        "$(read_state_field turn_count)" \
        0 \
        "$(( $(read_state_field completed_tasks) + 1 ))"
      cleanup_workflow_files
      ;;
    failed)
      record_failure "$(jq -r '.last_error.reason // "failed"' "$STATE_FILE")"
      set_state_values \
        "idle" \
        "null" \
        "null" \
        0 \
        "null" \
        "$(read_state_field turn_count)" \
        "$(( $(read_state_field consecutive_failures) + 1 ))" \
        "$(read_state_field completed_tasks)"
      cleanup_workflow_files
      ;;
  esac
}

append_pr_ledger_entry() {
  local pr_file pr_url repo issue now
  pr_file="$MEMORY_DIR/pr-info.json"
  [ -f "$pr_file" ] || return 0
  pr_url="$(jq -r '.pr_url // empty' "$pr_file")"
  repo="$(jq -r '.repo // empty' "$pr_file")"
  issue="$(jq -r '.issue_number // empty' "$pr_file")"
  [ -n "$pr_url" ] || return 0
  if grep -F "$pr_url" "$MEMORY_DIR/pr-ledger.md" >/dev/null 2>&1; then
    return 0
  fi
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '| %s | %s | %s | open | %s |\n' "$pr_url" "$repo" "$issue" "$now" >> "$MEMORY_DIR/pr-ledger.md"
}

run_agent_work_unit() {
  local unit="$1" session_id prompt tmp status aborted stop_reason payload_text failure_details
  session_id="$(read_state_field session_id)"
  if [ "$session_id" = "null" ]; then
    session_id="$(new_session_id)"
    tmp="$(mktemp)"
    jq --arg sid "$session_id" '.session_id = $sid' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
  fi

  prompt="$(PROJECT_DIR="$PROJECT_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" MISSION_PATH="$MISSION_PATH" bash "$BUILD_PROMPT_SCRIPT" "$unit")"
  tmp="$(mktemp)"

  if ! "$OPENCLAW_BIN" agent --agent "$AGENT_ID" --session-id "$session_id" --message "$prompt" --json --timeout "$AGENT_TIMEOUT" >"$tmp"; then
    set_state_values \
      "failed" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(json_string "$session_id")" \
      0 \
      "$(json_last_error "system_error" "openclaw agent failed")" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
    rm -f "$tmp"
    return 1
  fi

  status="$(jq -r '.status // empty' "$tmp")"
  aborted="$(jq -r '.result.meta.aborted // false' "$tmp")"
  stop_reason="$(jq -r '.result.meta.stopReason // empty' "$tmp")"
  payload_text="$(jq -r '[.result.payloads[]?.text? | select(length > 0)] | last // empty' "$tmp")"
  printf '%s\n' "$payload_text" > "$LAST_AGENT_OUTPUT_FILE"

  if [ "$aborted" = "true" ] || [ "$status" = "failed" ]; then
    failure_details="${payload_text:-$stop_reason}"
    set_state_values \
      "failed" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(json_string "$session_id")" \
      0 \
      "$(json_last_error "agent_aborted" "${stop_reason:-agent_aborted}" "$failure_details")" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
    rm -f "$tmp"
    return 1
  fi

  rm -f "$tmp"
  return 0
}

run_gate_check() {
  local gate="$1"
  local output details
  output="$(PROJECT_DIR="$PROJECT_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" MISSION_PATH="$MISSION_PATH" bash "$VERIFY_RESULT_SCRIPT" "$gate" 2>/dev/null || true)"
  if [ -z "$output" ]; then
    printf '%s\n' "$(json_last_error "gate_failed" "$gate" "verify-result produced no output")"
    return 1
  fi
  if printf '%s' "$output" | jq -e '.pass == true' >/dev/null 2>&1; then
    return 0
  fi
  details="$(printf '%s' "$output" | jq -r '.failures | if type == "array" then join("; ") else empty end' 2>/dev/null || true)"
  printf '%s\n' "$(json_last_error "gate_failed" "$gate" "$details")"
  return 1
}

task_id_json() {
  local task_file
  task_file="$MEMORY_DIR/task-envelope.json"
  if [ -f "$task_file" ]; then
    jq '.task_id' "$task_file"
  else
    printf 'null\n'
  fi
}

step_idle() {
  local unit
  unit="$(choose_idle_work_unit)"

  if [ "$(read_state_field session_id)" = "null" ]; then
    local tmp sid
    sid="$(new_session_id)"
    tmp="$(mktemp)"
    jq --arg sid "$sid" '.session_id = $sid' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
  fi

  run_agent_work_unit "$unit" || return 0

  case "$unit" in
    discover|reflect)
      local next_failures
      next_failures="$(read_state_field consecutive_failures)"
      if [ "$unit" = "reflect" ]; then
        next_failures=0
      fi
      set_state_values \
        "idle" \
        "null" \
        "$(jq '.session_id' "$STATE_FILE")" \
        0 \
        "null" \
        "$(( $(read_state_field turn_count) + 1 ))" \
        "$next_failures" \
        "$(read_state_field completed_tasks)"
      ;;
    select)
      if gate_error_json="$(run_gate_check task_admission)"; then
        set_state_values \
          "task_selected" \
          "$(task_id_json)" \
          "$(jq '.session_id' "$STATE_FILE")" \
          0 \
          "null" \
          "$(( $(read_state_field turn_count) + 1 ))" \
          "$(read_state_field consecutive_failures)" \
          "$(read_state_field completed_tasks)"
      else
        set_state_values \
          "failed" \
          "$(task_id_json)" \
          "$(jq '.session_id' "$STATE_FILE")" \
          0 \
          "$gate_error_json" \
          "$(( $(read_state_field turn_count) + 1 ))" \
          "$(read_state_field consecutive_failures)" \
          "$(read_state_field completed_tasks)"
      fi
      ;;
  esac
}

step_task_selected() {
  local gate_error_json agent_details
  set_state_values \
    "executing" \
    "$(task_id_json)" \
    "$(jq '.session_id' "$STATE_FILE")" \
    0 \
    "null" \
    "$(read_state_field turn_count)" \
    "$(read_state_field consecutive_failures)" \
    "$(read_state_field completed_tasks)"
  seed_implement_result_contract
  run_agent_work_unit "implement" || return 0
  if ! implement_result_completed; then
    agent_details="$(cat "$LAST_AGENT_OUTPUT_FILE" 2>/dev/null || true)"
    record_implement_failure_result "${agent_details:-implement completed without required output}"
    set_state_values \
      "failed" \
      "$(task_id_json)" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "$(json_last_error "output_contract_failed" "implement" "${agent_details:-implement completed without required output}")" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  elif ! prepare_submit_branch; then
    record_implement_failure_result "controller could not switch target repo to the mission-compliant submit branch"
    set_state_values \
      "failed" \
      "$(task_id_json)" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "$(json_last_error "branch_prepare_failed" "implement" "controller could not switch target repo to the mission-compliant submit branch")" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  elif gate_error_json="$(run_gate_check pre_submit)"; then
    set_state_values \
      "ready_for_submit" \
      "$(task_id_json)" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "null" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  else
    set_state_values \
      "failed" \
      "$(task_id_json)" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "$gate_error_json" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  fi
}

step_ready_for_submit() {
  run_agent_work_unit "submit" || return 0
  if validate_work_unit_output "submit"; then
    append_pr_ledger_entry
    set_state_values \
      "submitted" \
      "$(task_id_json)" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "null" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  else
    set_state_values \
      "failed" \
      "$(task_id_json)" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      '{"type":"output_contract_failed","reason":"submit"}' \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  fi
}

step_submitted() {
  if run_gate_check post_submit >/dev/null; then
    set_state_values \
      "pr_open" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "null" \
      "$(read_state_field turn_count)" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  fi
}

step_pr_open() {
  if PROJECT_DIR="$PROJECT_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" MISSION_PATH="$MISSION_PATH" bash "$VERIFY_RESULT_SCRIPT" pr_resolution >/dev/null 2>&1; then
    set_state_values \
      "done" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "null" \
      "$(read_state_field turn_count)" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
    finalize_terminal_state
    return 0
  fi

  if PROJECT_DIR="$PROJECT_DIR" WORKSPACE_DIR="$WORKSPACE_DIR" MISSION_PATH="$MISSION_PATH" bash "$VERIFY_RESULT_SCRIPT" followup_needed >/dev/null 2>&1; then
    set_state_values \
      "awaiting_followup" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "null" \
      "$(read_state_field turn_count)" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  fi
}

step_awaiting_followup() {
  run_agent_work_unit "followup" || return 0
  if validate_work_unit_output "followup"; then
    set_state_values \
      "pr_open" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      "null" \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  else
    set_state_values \
      "failed" \
      "$(jq '.active_task' "$STATE_FILE")" \
      "$(jq '.session_id' "$STATE_FILE")" \
      0 \
      '{"type":"output_contract_failed","reason":"followup"}' \
      "$(( $(read_state_field turn_count) + 1 ))" \
      "$(read_state_field consecutive_failures)" \
      "$(read_state_field completed_tasks)"
  fi
}

ensure_heartbeat_disabled
maybe_rotate_session_on_restart

while true; do
  case "$(read_state_field state)" in
    idle) step_idle ;;
    task_selected) step_task_selected ;;
    executing) step_task_selected ;;
    ready_for_submit) step_ready_for_submit ;;
    submitted) step_submitted ;;
    pr_open) step_pr_open ;;
    awaiting_followup) step_awaiting_followup ;;
    done|failed) finalize_terminal_state ;;
    *)
      set_state_values \
        "failed" \
        "$(jq '.active_task' "$STATE_FILE")" \
        "$(jq '.session_id' "$STATE_FILE")" \
        0 \
        '{"type":"system_error","reason":"unknown lifecycle state"}' \
        "$(read_state_field turn_count)" \
        "$(read_state_field consecutive_failures)" \
        "$(read_state_field completed_tasks)"
      finalize_terminal_state
      ;;
  esac

  if [ "$RUN_CYCLE_ONCE" = "1" ]; then
    break
  fi

  sleep 2
done
