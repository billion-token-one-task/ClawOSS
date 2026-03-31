#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_PROJECT="$(mktemp -d)"
trap 'rm -rf "$TEST_PROJECT"' EXIT

PROJECT_DIR="$TEST_PROJECT" bash "$ROOT/scripts/init-workspace-state.sh" >/dev/null
mkdir -p "$TEST_PROJECT/config" "$TEST_PROJECT/scripts" "$TEST_PROJECT/workspace/memory"
cp "$ROOT/config/alpha-gates.json" "$TEST_PROJECT/config/alpha-gates.json"
cp "$ROOT/scripts/evaluate-alpha-gate.sh" "$TEST_PROJECT/scripts/evaluate-alpha-gate.sh"
cp -r "$ROOT/scripts/lib" "$TEST_PROJECT/scripts/"

cat > "$TEST_PROJECT/workspace/memory/trust-repos.md" <<'EOF'
# Trust Repos

## Active
| Repo | Score | Notes |
|------|-------|-------|
| `trusted/repo` | 8 | merged before |

## Deprioritized
| Repo | Reason | Skip Until |
|------|--------|------------|
| `blocked/repo` | hostile maintainer | permanent |
EOF

AUTO_DOCS=$(PROJECT_DIR="$TEST_PROJECT" bash "$TEST_PROJECT/scripts/evaluate-alpha-gate.sh" pr_submit --repo trusted/repo --pr-type docs --diff-lines 20)
echo "$AUTO_DOCS" | jq -e '.decision == "auto"' >/dev/null

REVIEW_BUG=$(PROJECT_DIR="$TEST_PROJECT" bash "$TEST_PROJECT/scripts/evaluate-alpha-gate.sh" pr_submit --repo unknown/repo --pr-type bugfix --diff-lines 20 --record --reasoning-summary "new repo bugfix")
echo "$REVIEW_BUG" | jq -e '.decision == "review"' >/dev/null
grep -q 'unknown/repo' "$TEST_PROJECT/workspace/memory/human-review-queue.md"

FOLLOWUP_REVIEW=$(PROJECT_DIR="$TEST_PROJECT" bash "$TEST_PROJECT/scripts/evaluate-alpha-gate.sh" followup_push --repo trusted/repo --followup-round 3 --diff-lines 30)
echo "$FOLLOWUP_REVIEW" | jq -e '.decision == "review"' >/dev/null

STRATEGY_REVIEW=$(PROJECT_DIR="$TEST_PROJECT" bash "$TEST_PROJECT/scripts/evaluate-alpha-gate.sh" strategy_promotion --strategy-version candidate-v2 --record)
echo "$STRATEGY_REVIEW" | jq -e '.decision == "review"' >/dev/null
grep -q 'strategy_promotion' "$TEST_PROJECT/workspace/memory/human-review-queue.md"

echo "Alpha gate decisions are enforced."
