#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_PROJECT="$(mktemp -d)"
trap 'rm -rf "$TEST_PROJECT"' EXIT

mkdir -p "$TEST_PROJECT/config" "$TEST_PROJECT/scripts/lib" "$TEST_PROJECT/workspace/memory" "$TEST_PROJECT/bin" "$TEST_PROJECT/src"
cp "$ROOT/config/mission.json" "$TEST_PROJECT/config/mission.json"
cp "$ROOT/scripts/run-cycle.sh" "$TEST_PROJECT/scripts/run-cycle.sh"
cp "$ROOT/scripts/build-prompt.sh" "$TEST_PROJECT/scripts/build-prompt.sh"
cp "$ROOT/scripts/verify-result.sh" "$TEST_PROJECT/scripts/verify-result.sh"
cp "$ROOT/scripts/lib/path-helpers.sh" "$TEST_PROJECT/scripts/lib/path-helpers.sh"

cat > "$TEST_PROJECT/.env" <<'EOF'
GITHUB_TOKEN=test-token-from-env
GITHUB_USERNAME=test-user-from-env
EOF

cat > "$TEST_PROJECT/scripts/repo-health-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$TEST_PROJECT/scripts/repo-health-check.sh"

cat > "$TEST_PROJECT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
MODE="${GH_STUB_MODE:-open}"
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  printf '{"state":"OPEN","assignees":[]}\n'
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case "$MODE" in
    merged)
      printf '{"state":"MERGED","reviewDecision":"APPROVED","comments":{"totalCount":0}}\n'
      ;;
    followup)
      printf '{"state":"OPEN","reviewDecision":"CHANGES_REQUESTED","comments":{"totalCount":1}}\n'
      ;;
    *)
      printf '{"state":"OPEN","reviewDecision":"APPROVED","comments":{"totalCount":0}}\n'
      ;;
  esac
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_PROJECT/bin/gh"

cat > "$TEST_PROJECT/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

REAL_GIT="/usr/bin/git"
LOG_FILE="${GIT_STUB_LOG_FILE:-}"

if [ -n "$LOG_FILE" ]; then
  printf '%s\n' "$*" >> "$LOG_FILE"
fi

exec "$REAL_GIT" "$@"
EOF
chmod +x "$TEST_PROJECT/bin/git"

cat > "$TEST_PROJECT/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:?}"
MEMORY_DIR="$PROJECT_DIR/workspace/memory"

if [ "$1" = "system" ] && [ "$2" = "heartbeat" ] && [ "$3" = "disable" ]; then
  printf 'disabled\n' >> "$PROJECT_DIR/openclaw.log"
  exit 0
fi

if [ "$1" = "agent" ]; then
  shift
  MESSAGE=""
  SESSION_ID=""
  STUB_MODE="${OPENCLAW_STUB_MODE:-normal}"
  : "${GITHUB_TOKEN:=}"
  : "${GITHUB_USERNAME:=}"
  if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_USERNAME" ]; then
    printf '{"status":"failed","result":{"payloads":[{"text":"missing env"}],"meta":{"aborted":true,"stopReason":"missing env"}}}\n'
    exit 0
  fi
  printf '%s|%s\n' "$GITHUB_USERNAME" "$GITHUB_TOKEN" >> "$PROJECT_DIR/openclaw-env.log"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --message) MESSAGE="$2"; shift 2 ;;
      --session-id) SESSION_ID="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if printf '%s' "$MESSAGE" | grep -q -- '- name: discover'; then
    cat > "$MEMORY_DIR/candidates.json" <<'JSON'
{"candidates":[{"repo":"healthy/repo","issue_number":12,"issue_title":"Fix parsing edge case","type":"bug","rationale":"High value","estimated_difficulty":"small"}]}
JSON
  elif printf '%s' "$MESSAGE" | grep -q -- '- name: select'; then
    cat > "$MEMORY_DIR/task-envelope.json" <<'JSON'
{"task_id":"healthy-repo-12","task_type":"bug","repo":"healthy/repo","issue_number":12,"issue_title":"Fix parsing edge case","rationale":"High value","top_candidates":[],"risk_flags":[]}
JSON
  elif printf '%s' "$MESSAGE" | grep -q -- '- name: implement'; then
    if [ "$STUB_MODE" = "skip" ]; then
      printf '{"status":"completed","result":{"payloads":[{"text":"skip existing implement result"}],"meta":{"aborted":false,"stopReason":"completed","agentMeta":{"usage":{"inputTokens":10,"outputTokens":5}}}}}\n'
      exit 0
    fi
    if [ "$STUB_MODE" = "missing-implement-output" ]; then
      printf '{"status":"completed","result":{"payloads":[{"text":"implementation blocked: allowlist miss"}],"meta":{"aborted":false,"stopReason":"completed","agentMeta":{"usage":{"inputTokens":10,"outputTokens":5}}}}}\n'
      exit 0
    fi
    printf 'base\nchange\n' > "$PROJECT_DIR/src/app.txt"
    cat > "$MEMORY_DIR/last-result.json" <<'JSON'
{"task_id":"healthy-repo-12","status":"completed","branch":"clawoss/fix/parser-edge-case","repo_path":"REPLACE_PROJECT_DIR","diff_summary":"small patch","files_changed":["src/app.txt"],"tests_run":["unit"],"is_ready_to_submit":true,"risks":[]}
JSON
    sed -i "s|REPLACE_PROJECT_DIR|$PROJECT_DIR|g" "$MEMORY_DIR/last-result.json"
  elif printf '%s' "$MESSAGE" | grep -q -- '- name: submit'; then
    cat > "$MEMORY_DIR/pr-info.json" <<'JSON'
{"task_id":"healthy-repo-12","repo":"healthy/repo","issue_number":12,"pr_url":"https://example.test/pr/12","pr_number":12,"pr_state":"OPEN","commit_sha":"abc123"}
JSON
  elif printf '%s' "$MESSAGE" | grep -q -- '- name: followup'; then
    cat > "$MEMORY_DIR/followup-result.json" <<'JSON'
{"task_id":"healthy-repo-12","action_taken":"addressed review","pr_state_after":"OPEN","needs_another_round":false}
JSON
  elif printf '%s' "$MESSAGE" | grep -q -- '- name: reflect'; then
    cat > "$MEMORY_DIR/reflection-result.json" <<'JSON'
{"insights":["focus on trusted repos"],"pattern_identified":"small PRs merge faster","strategy_changes":["prefer trusted repos"],"repos_to_deprioritize":[],"repos_to_prioritize":["healthy/repo"]}
JSON
  fi

  printf '{"status":"completed","result":{"payloads":[{"text":"ok"}],"meta":{"aborted":false,"stopReason":"completed","agentMeta":{"usage":{"inputTokens":10,"outputTokens":5}}}}}\n'
  exit 0
fi

exit 1
EOF
chmod +x "$TEST_PROJECT/bin/openclaw"

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/init-workspace-state.sh" >/dev/null

git -C "$TEST_PROJECT" init >/dev/null
git -C "$TEST_PROJECT" config user.email test@example.com
git -C "$TEST_PROJECT" config user.name "Test User"
printf 'base\n' > "$TEST_PROJECT/src/app.txt"
git -C "$TEST_PROJECT" add .
git -C "$TEST_PROJECT" commit -m "init" >/dev/null
git -C "$TEST_PROJECT" checkout -b clawoss/fix/parser-edge-case >/dev/null

run_cycle() {
  local gh_mode="${1:-open}"
  local openclaw_mode="${2:-normal}"
  PATH="$TEST_PROJECT/bin:$PATH" \
    PROJECT_DIR="$TEST_PROJECT" \
    GH_BIN="$TEST_PROJECT/bin/gh" \
    GH_STUB_MODE="$gh_mode" \
    OPENCLAW_STUB_MODE="$openclaw_mode" \
    OPENCLAW_BIN="$TEST_PROJECT/bin/openclaw" \
    CLAWOSS_REPO_HEALTH_CHECK_SCRIPT="$TEST_PROJECT/scripts/repo-health-check.sh" \
    RUN_CYCLE_ONCE=1 \
    bash "$TEST_PROJECT/scripts/run-cycle.sh"
}

run_cycle
jq -e '.state == "idle" and .session_id != null' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null
test -f "$TEST_PROJECT/workspace/memory/candidates.json"

run_cycle
jq -e '.state == "task_selected" and .active_task == "healthy-repo-12"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

run_cycle
jq -e '.state == "ready_for_submit"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

run_cycle
jq -e '.state == "submitted"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null
grep -q 'https://example.test/pr/12' "$TEST_PROJECT/workspace/memory/pr-ledger.md"

run_cycle
jq -e '.state == "pr_open"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

run_cycle followup
jq -e '.state == "awaiting_followup"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

run_cycle open
jq -e '.state == "pr_open"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

run_cycle merged
jq -e '.state == "idle" and .active_task == null and .completed_tasks == 1' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{"task_id":"healthy-repo-13","task_type":"bug","repo":"healthy/repo","issue_number":13,"issue_title":"Fix other edge case","rationale":"High value","top_candidates":[],"risk_flags":[]}
EOF
jq '.state = "executing" | .active_task = "healthy-repo-13" | .session_id = "old-session"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" > "$TEST_PROJECT/workspace/memory/lifecycle-state.next"
mv "$TEST_PROJECT/workspace/memory/lifecycle-state.next" "$TEST_PROJECT/workspace/memory/lifecycle-state.json"
git -C "$TEST_PROJECT" checkout clawoss/fix/parser-edge-case >/dev/null
printf 'base\n' > "$TEST_PROJECT/src/app.txt"

run_cycle
jq -e '.state == "ready_for_submit" and .session_id != "old-session"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{"task_id":"healthy-repo-14","task_type":"bug","repo":"healthy/repo","issue_number":14,"issue_title":"Fix blocked edge case","rationale":"High value","top_candidates":[],"risk_flags":[]}
EOF
jq '.state = "task_selected" | .active_task = "healthy-repo-14" | .session_id = "blocked-session"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" > "$TEST_PROJECT/workspace/memory/lifecycle-state.next"
mv "$TEST_PROJECT/workspace/memory/lifecycle-state.next" "$TEST_PROJECT/workspace/memory/lifecycle-state.json"
rm -f "$TEST_PROJECT/workspace/memory/last-result.json"

run_cycle open missing-implement-output || true
jq -e '.state == "failed" and .last_error.type == "output_contract_failed" and .last_error.reason == "implement" and (.last_error.details | contains("allowlist miss"))' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null
jq -e '.status == "failed" and .is_ready_to_submit == false and (.diff_summary | length > 0) and (.risks | length >= 1)' "$TEST_PROJECT/workspace/memory/last-result.json" >/dev/null

run_cycle open
jq -e '.state == "idle" and .active_task == null and .consecutive_failures == 1' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null

jq '.state = "idle" | .active_task = null | .session_id = "reflect-session" | .consecutive_failures = 3' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" > "$TEST_PROJECT/workspace/memory/lifecycle-state.next"
mv "$TEST_PROJECT/workspace/memory/lifecycle-state.next" "$TEST_PROJECT/workspace/memory/lifecycle-state.json"
rm -f "$TEST_PROJECT/workspace/memory/candidates.json"

run_cycle open
jq -e '.state == "idle" and .consecutive_failures == 0' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null
test -f "$TEST_PROJECT/workspace/memory/reflection-result.json"

run_cycle open
jq -e '.state == "idle" and .consecutive_failures == 0' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null
test -f "$TEST_PROJECT/workspace/memory/candidates.json"

grep -q 'disabled' "$TEST_PROJECT/openclaw.log"
grep -q '^test-user-from-env|test-token-from-env$' "$TEST_PROJECT/openclaw-env.log"

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{"task_id":"healthy-repo-15","task_type":"bug","repo":"healthy/repo","issue_number":15,"issue_title":"Fix branch prep edge case","rationale":"High value","top_candidates":[],"risk_flags":[]}
EOF
jq '.state = "task_selected" | .active_task = "healthy-repo-15" | .session_id = "branch-prepare-session"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" > "$TEST_PROJECT/workspace/memory/lifecycle-state.next"
mv "$TEST_PROJECT/workspace/memory/lifecycle-state.next" "$TEST_PROJECT/workspace/memory/lifecycle-state.json"
printf '' > "$TEST_PROJECT/git.log"
git -C "$TEST_PROJECT" checkout -B wrong-branch >/dev/null
cat > "$TEST_PROJECT/workspace/memory/last-result.json" <<EOF
{"task_id":"healthy-repo-15","status":"completed","branch":"clawoss/issue-15","repo_path":"$TEST_PROJECT","diff_summary":"small patch","files_changed":["src/app.txt"],"tests_run":["unit"],"is_ready_to_submit":true,"risks":[]}
EOF
OPENCLAW_STUB_MODE=skip PATH="$TEST_PROJECT/bin:$PATH" GIT_STUB_LOG_FILE="$TEST_PROJECT/git.log" PROJECT_DIR="$TEST_PROJECT" GH_BIN="$TEST_PROJECT/bin/gh" GH_STUB_MODE="open" OPENCLAW_BIN="$TEST_PROJECT/bin/openclaw" CLAWOSS_REPO_HEALTH_CHECK_SCRIPT="$TEST_PROJECT/scripts/repo-health-check.sh" RUN_CYCLE_ONCE=1 bash "$TEST_PROJECT/scripts/run-cycle.sh"
jq -e '.state == "ready_for_submit"' "$TEST_PROJECT/workspace/memory/lifecycle-state.json" >/dev/null
grep -q -- "checkout -B clawoss/fix/15-fix-branch-prep-edge-case" "$TEST_PROJECT/git.log"
jq -e '.branch == "clawoss/fix/15-fix-branch-prep-edge-case"' "$TEST_PROJECT/workspace/memory/last-result.json" >/dev/null

echo "run-cycle state machine and recovery are enforced."
