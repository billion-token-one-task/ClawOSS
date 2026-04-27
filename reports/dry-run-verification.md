# Dry-Run Verification

Generated: 2026-04-27T08:49:12Z

## Environment

```bash
CLAWOSS_PROJECT_DIR=/tmp/clawoss-proper
CLAWOSS_WORKSPACE=/tmp/clawoss-proper/workspace
CLAWOSS_DRY_RUN=true
CLAWOSS_TOKEN_BUDGET=1000000
CLAWOSS_COST_BUDGET=50.00
CLAWOSS_MODEL=openai/gpt-5.5
CLAWOSS_FALLBACK_MODEL=openai/gpt-5.5
```

## Script Outputs

### `bash scripts/budget-check.sh --local-only`

Exit code: 0

```json
{"within_budget": true,"tokens_used": 0,"tokens_budget": 1000000,"cost_used": 0.0,"cost_budget": 50.0}
```

Confirmed: script outputs JSON with `within_budget=true`.

### `bash scripts/dry-run-gate.sh --repo test/repo --title "Test PR" --head feat/test --base main --issue "https://github.com/test/repo/issues/1"`

Exit code: 1

```text
CLAWOSS_DRY_RUN=true; PR creation logged to /tmp/clawoss-proper/workspace/memory/dry-run-log.md
EXIT_CODE=1
```

Confirmed: script logs to `workspace/memory/dry-run-log.md` and exits 1 in dry-run mode.

### `bash scripts/heartbeat-status.sh`

Exit code: 0

```json
{
  "cycle_count": 1,
  "consecutive_wakes": 0,
  "errors_this_hour": 0,
  "lock_files": 0,
  "queue_depth": 0,
  "staging_depth": 0,
  "open_prs": 30,
  "followup_pending": 0,
  "spawned_pending": 0,
  "always_on": {
    "scout": "no reports",
    "scout_latest_report": "",
    "pr_monitor": "no reports",
    "pr_analyst": "no reports"
  },
  "timestamp": "2026-04-27T08:48:55Z"
}
```

Confirmed: script outputs JSON with a `cycle_count` field.

### `bash scripts/generate-run-report.sh`

Exit code: 0

```markdown
# ClawOSS Run Report

Generated: 2026-04-27T08:49:12.987609Z

## Runtime
- Runtime duration: 0s
- Heartbeat cycle count: 1
- First cycle: 2026-04-27T08:48:52.168174+00:00
- Last cycle: 2026-04-27T08:48:52.168174+00:00

## Runtime Identity
- Model: openai/gpt-5.5
- Fallback model: openai/gpt-5.5
- GitHub account: imwyvern

## Work Summary
- Candidates discovered: 0
- Tasks attempted: 0
- Dashboard total PRs: 0
- PRs created today: 0
- Dry-run PR steps logged: 1

## PRs Created Or Dry-Run Steps
none

## Failures
- none

## Token And Cost
- Tokens consumed: 0 / 1000000
- Cost consumed: $0.000000 / $50.00
- Within budget: true
- Budget check exit code: 0

## Budget And Pause Guardrails
- none
```

Confirmed: script generated a markdown report under `reports/`.

## Final Verification State

- `workspace/memory/heartbeat-cycles.json` simulates 3 heartbeat cycles.
- `workspace/memory/dry-run-log.md` contains 3 sample dry-run skipped PR entries.
- Final run report generated at `reports/run-report-20260427-015019.md`.
- All 4 verification scripts work correctly.

### Final Run Report Output

```markdown
# ClawOSS Run Report

Generated: 2026-04-27T08:50:28.999638Z

## Runtime
- Runtime duration: 0s
- Heartbeat cycle count: 3
- First cycle: unknown
- Last cycle: 2026-04-27T08:45:00+00:00

## Work Summary
- Candidates discovered: 0
- Tasks attempted: 0
- Dashboard total PRs: 0
- PRs created today: 0
- Dry-run PR steps logged: 3

## Token And Cost
- Tokens consumed: 0 / 1000000
- Cost consumed: $0.000000 / $50.00
- Within budget: true
- Budget check exit code: 0
```

## Fixes Applied

- Updated `scripts/generate-run-report.sh` to recognize both `last_cycle_at` and `last_cycle` heartbeat fields.
- Updated `scripts/generate-run-report.sh` to count both `PR creation skipped` dry-run gate entries and `Status: SKIPPED (dry-run)` sample log entries.
