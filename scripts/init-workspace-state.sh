#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
MEMORY_DIR="$WORKSPACE_DIR/memory"

mkdir -p \
  "$MEMORY_DIR" \
  "$MEMORY_DIR/locks" \
  "$MEMORY_DIR/repos" \
  "$MEMORY_DIR/issues" \
  "$WORKSPACE_DIR/runtime/decisions" \
  "$WORKSPACE_DIR/runtime/outcomes" \
  "$WORKSPACE_DIR/runtime/processed/decisions" \
  "$WORKSPACE_DIR/runtime/processed/outcomes" \
  "$WORKSPACE_DIR/reflections/daily" \
  "$WORKSPACE_DIR/reflections/post-pr" \
  "$WORKSPACE_DIR/reflections/outbox" \
  "$WORKSPACE_DIR/reflections/processed" \
  "$WORKSPACE_DIR/strategy" \
  "$WORKSPACE_DIR/strategy/history" \
  "$WORKSPACE_DIR/strategy/outbox" \
  "$WORKSPACE_DIR/strategy/processed"

write_if_missing() {
  local path="$1"
  shift

  if [ -f "$path" ]; then
    return 0
  fi

  cat > "$path"
}

write_if_missing "$MEMORY_DIR/trust-repos.md" <<'EOF'
# Trust Repos

## Active
| Repo | Score | Notes |
|------|-------|-------|

## Deprioritized
| Repo | Reason | Skip Until |
|------|--------|------------|
EOF

write_if_missing "$MEMORY_DIR/human-review-queue.md" <<'EOF'
# Human Review Queue

| created_at | action | repo | decision | reasons | context |
|------------|--------|------|----------|---------|---------|
EOF

write_if_missing "$MEMORY_DIR/impl-spawn-state.md" <<'EOF'
# Implementation Spawn State

## Active Implementations (0 total)
| issue_url | repo | status | spawned_at |
|-----------|------|--------|------------|

## Active Follow-ups (0 total)
| pr_url | repo | status | round | spawned_at |
|--------|------|--------|-------|------------|
EOF

write_if_missing "$MEMORY_DIR/pr-followup-state.md" <<'EOF'
# PR Follow-up State

| pr_url | repo | status | round | updated_at |
|--------|------|--------|-------|------------|
EOF

write_if_missing "$MEMORY_DIR/work-queue.md" <<'EOF'
# Work Queue

<!-- Pending implementation work items -->
EOF

write_if_missing "$MEMORY_DIR/work-queue-staging.md" <<'EOF'
# Work Queue Staging

<!-- Newly discovered work items before triage -->
EOF

write_if_missing "$MEMORY_DIR/followup-staging.md" <<'EOF'
# Follow-up Staging

<!-- PRs waiting to enter the follow-up queue -->
EOF

write_if_missing "$MEMORY_DIR/pr-ledger.md" <<'EOF'
# PR Ledger

| pr_url | repo | issue | status | updated_at |
|--------|------|-------|--------|------------|
EOF

write_if_missing "$MEMORY_DIR/pipeline-state.md" <<'EOF'
# Pipeline State

No active pipeline state yet.
EOF

write_if_missing "$MEMORY_DIR/wake-state.md" <<'EOF'
# Wake State

consecutive_wakes: 0
errors_this_hour: 0
last_wake: never
EOF

write_if_missing "$WORKSPACE_DIR/strategy/current.json" <<'EOF'
{
  "version": "bootstrap-v1",
  "status": "active",
  "targeting": {
    "prefer_trusted_repos": true,
    "repo_health_weight": 0.25,
    "merge_probability_weight": 0.35,
    "expected_token_efficiency_weight": 0.2,
    "novelty_weight": 0.1,
    "followup_priority_weight": 0.1
  },
  "execution": {
    "max_diff_lines_soft": 120,
    "max_diff_lines_hard": 200,
    "prefer_docs_test_bugfix_ratio": [0.35, 0.25, 0.4],
    "max_parallel_impl": 8
  },
  "followup": {
    "max_rounds": 3,
    "stale_ping_hours": 72,
    "merge_when_green": true
  },
  "budget": {
    "daily_token_budget": 3000000,
    "max_expected_tokens_per_attempt": 250000,
    "min_expected_merge_prob": 0.3
  },
  "rollout": {
    "mode": "stable",
    "traffic_share": 1.0
  }
}
EOF

echo "{\"initialized\": true, \"project_dir\": \"$PROJECT_DIR\", \"workspace_dir\": \"$WORKSPACE_DIR\"}"
