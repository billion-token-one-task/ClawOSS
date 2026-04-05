#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_PROJECT="$(mktemp -d)"
TARGET_REPO="$TEST_PROJECT/target-repo"
trap 'rm -rf "$TEST_PROJECT"' EXIT

mkdir -p "$TEST_PROJECT/config" "$TEST_PROJECT/scripts/lib" "$TEST_PROJECT/workspace/memory" "$TEST_PROJECT/bin" "$TARGET_REPO/src"
cp "$ROOT/config/mission.json" "$TEST_PROJECT/config/mission.json"
cp "$ROOT/scripts/verify-result.sh" "$TEST_PROJECT/scripts/verify-result.sh"
cp "$ROOT/scripts/lib/path-helpers.sh" "$TEST_PROJECT/scripts/lib/path-helpers.sh"

cat > "$TEST_PROJECT/scripts/repo-health-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "healthy/repo" ]; then
  echo '{"pass":true}'
  exit 0
fi
echo '{"pass":false}'
exit 1
EOF
chmod +x "$TEST_PROJECT/scripts/repo-health-check.sh"

cat > "$TEST_PROJECT/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MODE="${GH_STUB_MODE:-open}"

if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  case "$MODE" in
    issue-closed)
      printf '{"state":"CLOSED","assignees":[]}\n'
      ;;
    issue-assigned)
      printf '{"state":"OPEN","assignees":[{"login":"someone"}]}\n'
      ;;
    *)
      printf '{"state":"OPEN","assignees":[]}\n'
      ;;
  esac
  exit 0
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case "$MODE" in
    pr-open)
      printf '{"state":"OPEN","reviewDecision":"APPROVED","comments":{"totalCount":0}}\n'
      ;;
    pr-merged)
      printf '{"state":"MERGED","reviewDecision":"APPROVED","comments":{"totalCount":0}}\n'
      ;;
    pr-closed)
      printf '{"state":"CLOSED","reviewDecision":"APPROVED","comments":{"totalCount":0}}\n'
      ;;
    pr-followup)
      printf '{"state":"OPEN","reviewDecision":"CHANGES_REQUESTED","comments":{"totalCount":1}}\n'
      ;;
    pr-missing)
      exit 1
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

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/init-workspace-state.sh" >/dev/null

cat > "$TEST_PROJECT/workspace/memory/trust-repos.md" <<'EOF'
# Trusted Repos

## Tier 1 (Merged PRs)
| Repo | Merged | Open | Merge Rate | Notes |
|------|--------|------|------------|-------|
| trusted/repo | 1 | 0 | 100% | trusted |
EOF

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{
  "task_id": "healthy-repo-12",
  "task_type": "bug",
  "repo": "healthy/repo",
  "issue_number": 12,
  "issue_title": "Fix parsing edge case",
  "rationale": "High value",
  "top_candidates": [],
  "risk_flags": []
}
EOF

cat > "$TEST_PROJECT/workspace/memory/last-result.json" <<'EOF'
{
  "task_id": "healthy-repo-12",
  "status": "completed",
  "branch": "clawoss/fix/parser-edge-case",
  "repo_path": "REPLACE_TEST_PROJECT",
  "diff_summary": "small patch",
  "files_changed": ["src/app.txt"],
  "tests_run": ["unit"],
  "is_ready_to_submit": true,
  "risks": []
}
EOF
sed -i "s|REPLACE_TEST_PROJECT|$TARGET_REPO|g" "$TEST_PROJECT/workspace/memory/last-result.json"

cat > "$TEST_PROJECT/workspace/memory/pr-info.json" <<'EOF'
{
  "task_id": "healthy-repo-12",
  "repo": "healthy/repo",
  "issue_number": 12,
  "pr_url": "https://example.test/pr/12",
  "pr_number": 12,
  "pr_state": "OPEN",
  "commit_sha": "abc123"
}
EOF

cat > "$TEST_PROJECT/workspace/memory/pr-ledger.md" <<'EOF'
# PR Ledger

| pr_url | repo | issue | status | updated_at |
|--------|------|-------|--------|------------|
| https://example.test/pr/12 | healthy/repo | 12 | open | 2026-04-03T00:00:00Z |
EOF

cat > "$TEST_PROJECT/workspace/memory/failure-log.md" <<'EOF'
# Failure Log

| timestamp | repo | issue | reason | details |
|-----------|------|-------|--------|---------|
EOF

git -C "$TEST_PROJECT" init >/dev/null
git -C "$TEST_PROJECT" config user.email test@example.com
git -C "$TEST_PROJECT" config user.name "Test User"
printf 'controller\n' > "$TEST_PROJECT/controller.txt"
git -C "$TEST_PROJECT" add .
git -C "$TEST_PROJECT" commit -m "init" >/dev/null
git -C "$TEST_PROJECT" checkout -b wrong-branch >/dev/null
printf 'controller\nchange\n' > "$TEST_PROJECT/controller.txt"

git -C "$TARGET_REPO" init >/dev/null
git -C "$TARGET_REPO" config user.email test@example.com
git -C "$TARGET_REPO" config user.name "Test User"
printf 'base\n' > "$TARGET_REPO/src/app.txt"
git -C "$TARGET_REPO" add .
git -C "$TARGET_REPO" commit -m "init" >/dev/null
git -C "$TARGET_REPO" checkout -b clawoss/fix/parser-edge-case >/dev/null
printf 'base\nchange\n' > "$TARGET_REPO/src/app.txt"

run_verify() {
  local gate="$1"
  local mode="${2:-}"
  PATH="$TEST_PROJECT/bin:$PATH" \
    PROJECT_DIR="$TEST_PROJECT" \
    GH_BIN="$TEST_PROJECT/bin/gh" \
    GH_STUB_MODE="$mode" \
    CLAWOSS_REPO_HEALTH_CHECK_SCRIPT="$TEST_PROJECT/scripts/repo-health-check.sh" \
    bash "$TEST_PROJECT/scripts/verify-result.sh" "$gate"
}

TASK_ADMISSION_FAIL=$(run_verify task_admission 2>&1 || true)
echo "$TASK_ADMISSION_FAIL" | jq -e '.pass == false' >/dev/null

cat > "$TEST_PROJECT/workspace/memory/pr-ledger.md" <<'EOF'
# PR Ledger

| pr_url | repo | issue | status | updated_at |
|--------|------|-------|--------|------------|
EOF

TASK_ADMISSION_PASS=$(run_verify task_admission)
echo "$TASK_ADMISSION_PASS" | jq -e '.pass == true and (.checks_passed | index("dedup_ledger")) != null and (.checks_passed | index("task_type_scope")) != null' >/dev/null

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{
  "task_id": "healthy-repo-13",
  "task_type": "bug",
  "repo": "healthy/repo",
  "issue_number": 13,
  "issue_title": "[BUG] SSO doesn't enable",
  "rationale": "High value",
  "top_candidates": [],
  "risk_flags": []
}
EOF

TASK_ADMISSION_TITLE_PASS=$(run_verify task_admission)
echo "$TASK_ADMISSION_TITLE_PASS" | jq -e '.pass == true' >/dev/null

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{
  "task_id": "healthy-repo-12",
  "task_type": "bug",
  "repo": "healthy/repo",
  "issue_number": 12,
  "issue_title": "Fix parsing edge case",
  "rationale": "High value",
  "top_candidates": [],
  "risk_flags": []
}
EOF

cat > "$TEST_PROJECT/workspace/memory/failure-log.md" <<'EOF'
# Failure Log

| timestamp | repo | issue | reason | details |
|-----------|------|-------|--------|---------|
| 2026-04-03T00:00:00Z | healthy/repo | 12 | implement | once |
EOF

TASK_ADMISSION_SINGLE_FAILURE_PASS=$(run_verify task_admission)
echo "$TASK_ADMISSION_SINGLE_FAILURE_PASS" | jq -e '.pass == true and (.checks_passed | index("recent_failure_window")) != null' >/dev/null

cat > "$TEST_PROJECT/workspace/memory/failure-log.md" <<'EOF'
# Failure Log

| timestamp | repo | issue | reason | details |
|-----------|------|-------|--------|---------|
| 2026-04-03T00:00:00Z | healthy/repo | 12 | implement | once |
| 2026-04-03T01:00:00Z | healthy/repo | 12 | task_admission | twice |
EOF

TASK_ADMISSION_REPEAT_FAIL=$(run_verify task_admission 2>&1 || true)
echo "$TASK_ADMISSION_REPEAT_FAIL" | jq -e '.pass == false and (.failures | join(" ") | contains("recent repeated failures found for healthy/repo#12"))' >/dev/null

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{
  "task_id": "trusted-repo-99",
  "task_type": "bug",
  "repo": "trusted/repo",
  "issue_number": 99,
  "issue_title": "Fix trusted repo issue",
  "rationale": "High value",
  "top_candidates": [],
  "risk_flags": []
}
EOF

cat > "$TEST_PROJECT/scripts/repo-health-check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "healthy/repo" ]; then
  echo '{"pass":true}'
  exit 0
fi
echo '{"pass":false}'
exit 1
EOF
chmod +x "$TEST_PROJECT/scripts/repo-health-check.sh"

cat > "$TEST_PROJECT/workspace/memory/failure-log.md" <<'EOF'
# Failure Log

| timestamp | repo | issue | reason | details |
|-----------|------|-------|--------|---------|
EOF

TASK_ADMISSION_TRUSTED_PASS=$(run_verify task_admission)
echo "$TASK_ADMISSION_TRUSTED_PASS" | jq -e '.pass == true and (.checks_passed | index("repo_health")) != null' >/dev/null

cat > "$TEST_PROJECT/workspace/memory/task-envelope.json" <<'EOF'
{
  "task_id": "healthy-repo-12",
  "task_type": "bug",
  "repo": "healthy/repo",
  "issue_number": 12,
  "issue_title": "Fix parsing edge case",
  "rationale": "High value",
  "top_candidates": [],
  "risk_flags": []
}
EOF

PRE_SUBMIT_PASS=$(run_verify pre_submit)
echo "$PRE_SUBMIT_PASS" | jq -e '.pass == true and (.checks_passed | index("diff_size")) != null' >/dev/null

git -C "$TARGET_REPO" checkout -b wrong-branch >/dev/null
PRE_SUBMIT_FAIL=$(run_verify pre_submit 2>&1 || true)
echo "$PRE_SUBMIT_FAIL" | jq -e '.pass == false' >/dev/null
git -C "$TARGET_REPO" checkout clawoss/fix/parser-edge-case >/dev/null

cat > "$TEST_PROJECT/workspace/memory/pr-ledger.md" <<'EOF'
# PR Ledger

| pr_url | repo | issue | status | updated_at |
|--------|------|-------|--------|------------|
| https://example.test/pr/12 | healthy/repo | 12 | open | 2026-04-03T00:00:00Z |
EOF

POST_SUBMIT_PASS=$(run_verify post_submit pr-open)
echo "$POST_SUBMIT_PASS" | jq -e '.pass == true and (.checks_passed | index("pr_exists")) != null' >/dev/null

RESOLUTION_PASS=$(run_verify pr_resolution pr-merged)
echo "$RESOLUTION_PASS" | jq -e '.pass == true' >/dev/null

FOLLOWUP_PASS=$(run_verify followup_needed pr-followup)
echo "$FOLLOWUP_PASS" | jq -e '.pass == true' >/dev/null

echo "verify-result gates are enforced."
