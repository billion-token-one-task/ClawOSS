#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TOKEN_BUDGET="${1:-${CLAWOSS_VERIFY_TOKEN_BUDGET:-1}}"
ISSUE="${CLAWOSS_VERIFY_ISSUE:-cli/cli#13283}"
CYCLES="${CLAWOSS_VERIFY_CYCLES:-1}"

if ! [[ "$TOKEN_BUDGET" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [token_budget]" >&2
  echo "token_budget must be a non-negative integer" >&2
  exit 2
fi

export DASHBOARD_URL="${DASHBOARD_URL:-https://yuanbaomao.cyou}"
export CLAWOSS_TOKEN_BUDGET_TOTAL="$TOKEN_BUDGET"
export CLAWOSS_VERIFY_EXPECTED_CYCLES="$CYCLES"

echo "Running budget pause verification"
echo "Dashboard: $DASHBOARD_URL"
echo "Token budget: $CLAWOSS_TOKEN_BUDGET_TOTAL"
echo "Issue: $ISSUE"

set +e
OUTPUT="$(npm run mvp:dry-run -- --cycles "$CYCLES" --issue "$ISSUE" 2>&1)"
STATUS=$?
set -e

printf '%s\n' "$OUTPUT"

if [[ "$STATUS" -ne 0 ]]; then
  echo "mvp:dry-run failed before verification could inspect the report" >&2
  exit "$STATUS"
fi

REPORT_PATH="$(printf '%s\n' "$OUTPUT" | sed -n 's/^MVP report: //p' | tail -1)"

if [[ -z "$REPORT_PATH" || ! -f "$REPORT_PATH" ]]; then
  echo "Could not find the generated MVP markdown report path" >&2
  exit 1
fi

JSON_PATH="${REPORT_PATH%.md}.json"

if [[ ! -f "$JSON_PATH" ]]; then
  echo "Could not find the generated MVP JSON report: $JSON_PATH" >&2
  exit 1
fi

node - "$JSON_PATH" <<'NODE'
const fs = require("fs");

const reportPath = process.argv[2];
const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
const expectedBudget = Number(process.env.CLAWOSS_TOKEN_BUDGET_TOTAL);
const expectedCycles = Number(process.env.CLAWOSS_VERIFY_EXPECTED_CYCLES || 1);
const failures = [];

if (report.cyclesRequested !== expectedCycles) failures.push(`expected cyclesRequested=${expectedCycles}, got ${report.cyclesRequested}`);
if (report.cyclesCompleted !== 0) failures.push(`expected cyclesCompleted=0, got ${report.cyclesCompleted}`);
if (report.attemptedTasks !== 0) failures.push(`expected attemptedTasks=0, got ${report.attemptedTasks}`);
if (report.dryRunStage !== null) failures.push(`expected dryRunStage=null, got ${report.dryRunStage}`);
if (!Array.isArray(report.pauseEvents) || report.pauseEvents.length === 0) {
  failures.push("expected at least one pause event");
}
if (Number(report.budget?.tokenBudgetTotal) !== expectedBudget) {
  failures.push(`expected budget.tokenBudgetTotal=${expectedBudget}, got ${report.budget?.tokenBudgetTotal}`);
}

if (failures.length > 0) {
  console.error("Budget pause verification failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("Budget pause verification passed");
console.log(`Report: ${reportPath}`);
console.log(`Pause reason: ${report.pauseEvents[0].reason || "unknown"}`);
NODE
