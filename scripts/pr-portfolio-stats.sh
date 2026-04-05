#!/usr/bin/env bash
# pr-portfolio-stats.sh — Quick stats on the configured GitHub account's PR portfolio
# Usage: pr-portfolio-stats.sh
# Outputs JSON with open/merged/closed counts, merge rate, approved PRs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/github-rate-limit.sh"
AGENT_USER="${GITHUB_USERNAME:-${CLAW_AGENT_USERNAME:-clawoss-bot}}"

OPEN=$(gh_cached_search_prs 300 --author "$AGENT_USER" --state open --json number --jq 'length' 2>/dev/null || echo 0)
# gh search prs has no --merged flag — use "is:merged" in the query
MERGED=$(gh_cached_search_prs 900 --author "$AGENT_USER" "is:merged" --json number --jq 'length' 2>/dev/null || echo 0)
CLOSED_UNMERGED=$(gh_cached_search_prs 900 --author "$AGENT_USER" --state closed "is:unmerged" --json number --jq 'length' 2>/dev/null || echo 0)
TOTAL=$((OPEN + MERGED + CLOSED_UNMERGED))

if [ "$TOTAL" -gt 0 ]; then
  MERGE_RATE=$(python3 -c "print(round($MERGED / $TOTAL * 100, 1))")
else
  MERGE_RATE="0"
fi

cat <<ENDJSON
{
  "open": $OPEN,
  "merged": $MERGED,
  "closed_unmerged": $CLOSED_UNMERGED,
  "total": $TOTAL,
  "merge_rate_pct": $MERGE_RATE,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
ENDJSON
