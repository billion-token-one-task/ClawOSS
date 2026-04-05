#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_PROJECT="$(mktemp -d)"
trap 'rm -rf "$TEST_PROJECT"' EXIT

mkdir -p "$TEST_PROJECT/config" "$TEST_PROJECT/scripts/lib" "$TEST_PROJECT/workspace/memory"
cp "$ROOT/config/mission.json" "$TEST_PROJECT/config/mission.json"
cp "$ROOT/scripts/build-prompt.sh" "$TEST_PROJECT/scripts/build-prompt.sh"
cp "$ROOT/scripts/lib/path-helpers.sh" "$TEST_PROJECT/scripts/lib/path-helpers.sh"

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/init-workspace-state.sh" >/dev/null

cat > "$TEST_PROJECT/workspace/memory/lifecycle-state.json" <<'EOF'
{
  "state": "task_selected",
  "active_task": "healthy-repo-12",
  "session_id": "session-2",
  "turn_count": 1,
  "consecutive_failures": 0,
  "completed_tasks": 3,
  "updated_at": "2026-04-03T00:00:00Z"
}
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

cat > "$TEST_PROJECT/workspace/memory/trust-repos.md" <<'EOF'
# Trust Repos

| Repo | Score | Notes |
|------|-------|-------|
| healthy/repo | 9 | merged before |
EOF

cat > "$TEST_PROJECT/workspace/memory/pr-ledger.md" <<'EOF'
# PR Ledger

| pr_url | repo | issue | status | updated_at |
|--------|------|-------|--------|------------|
| https://example.test/pr/11 | healthy/repo | 11 | merged | 2026-04-01T00:00:00Z |
EOF

cat > "$TEST_PROJECT/workspace/memory/failure-log.md" <<'EOF'
# Failure Log

| timestamp | repo | issue | reason | details |
|-----------|------|-------|--------|---------|
| 2026-04-02T00:00:00Z | healthy/repo | 9 | stale_closed | recent |
| 2026-03-20T00:00:00Z | old/repo | 1 | stale_closed | old |
EOF

{
  printf '# Work Queue\n\n'
  for i in $(seq 1 25); do
    printf 'candidate-%02d\n' "$i"
  done
} > "$TEST_PROJECT/workspace/memory/work-queue.md"

PROMPT="$(PROJECT_DIR="$TEST_PROJECT" bash "$TEST_PROJECT/scripts/build-prompt.sh" implement)"

echo "$PROMPT" | grep -q '^# Mission'
echo "$PROMPT" | grep -q 'Fix parsing edge case'
echo "$PROMPT" | grep -q 'write_file: workspace/memory/last-result.json'
echo "$PROMPT" | grep -q 'required_field: repo_path'
echo "$PROMPT" | grep -q 'required_field: is_ready_to_submit'
echo "$PROMPT" | grep -q '^## Autonomous Execution Override'
echo "$PROMPT" | grep -q 'Do not ask the user for approval, clarification, or a design sign-off.'
echo "$PROMPT" | grep -q '/tmp/clawoss-12-<timestamp>'
echo "$PROMPT" | grep -q 'Use `gh repo clone healthy/repo $WORKDIR -- --depth=50` instead of ad-hoc chained clone commands.'
echo "$PROMPT" | grep -q 'If the cloned repo is a Python project with `pyproject.toml` and `uv.lock`, bootstrap the test environment before the first pytest run, preferring `uv sync --group tests`.'
echo "$PROMPT" | grep -q 'Create or switch to a mission-compliant branch with prefix `clawoss/` in the cloned repo before concluding implementation, and record that branch in `workspace/memory/last-result.json`.'
echo "$PROMPT" | grep -q 'Write the absolute clone path you actually used to `repo_path` in `workspace/memory/last-result.json`.'
echo "$PROMPT" | grep -q 'Do not stop because a generic brainstorming skill asks for user approval.'
echo "$PROMPT" | grep -q 'candidate-25'
if echo "$PROMPT" | grep -q 'candidate-01'; then
  echo "tail_20 snapshot unexpectedly included early queue entries" >&2
  exit 1
fi
echo "$PROMPT" | grep -q '2026-04-02T00:00:00Z'
if echo "$PROMPT" | grep -q '2026-03-20T00:00:00Z'; then
  echo "recent_7d snapshot unexpectedly included old failure entries" >&2
  exit 1
fi

echo "build-prompt output is scoped and complete."
