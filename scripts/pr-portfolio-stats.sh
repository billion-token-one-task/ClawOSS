#!/usr/bin/env bash
# pr-portfolio-stats.sh 鈥?Quick stats on onthebed's PR portfolio
# Usage: pr-portfolio-stats.sh
# Outputs JSON with open/merged/closed counts, merge rate, approved PRs

AGENT_USER="${CLAW_AGENT_USERNAME:-${GITHUB_USERNAME:-clawoss-agent}}"

OPEN=$(gh search prs --author "$AGENT_USER" --state open --json number --jq 'length' 2>/dev/null || echo 0)
# gh search prs has no --merged flag 鈥?use "is:merged" in the query
MERGED=$(gh search prs --author "$AGENT_USER" "is:merged" --json number --jq 'length' 2>/dev/null || echo 0)
CLOSED_UNMERGED=$(gh search prs --author "$AGENT_USER" --state closed "is:unmerged" --json number --jq 'length' 2>/dev/null || echo 0)
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
