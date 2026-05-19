# agent-home (template)

This is the home repository of a long-running OSS maintainer agent powered by the [`clawoss-skill`](../skill/SKILL.md). Fork this template, fill in `.env`, then either run the skill manually or attach a scheduler (e.g. Claude Code `/schedule`) to invoke it on a cadence.

Everything the agent knows about its world is in this repo:
- **`state/`** — what the agent has done, what it owes, what it's working on next.
- **`config/`** — what the agent is forbidden to touch.
- **`reports/`** — long-form artifacts (post-mortems, monthly summaries) the agent writes occasionally.
- **`README.md`** — this file. The block below labelled `LATEST-STATUS` is rewritten by the agent at the end of every cycle. It is the **α-phase dashboard**.

The β-phase dashboard (React + Tailwind, inherited from ClawOSS v1.0) renders the same state via the GitHub API and is read-only; this README is the source of truth.

---

<!-- LATEST-STATUS:START -->
## Latest Status

_No cycles have run yet. After the first cycle, this block is rewritten automatically. Do not edit by hand — your edits will be overwritten._

| KPI | Value |
|---|---|
| Cost per merged PR (USD) | — |
| Merged PRs (lifetime) | 0 |
| Spent / Budget (USD) | 0.00 / 0.00 |
| Last cycle | — |

**Budget progress**

```
[░░░░░░░░░░░░░░░░░░░░] 0%
```

**Recent cycles** (most recent first, up to 5)

| Time (UTC) | Outcome | Repo | Issue | PR | Cost (USD) |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!-- LATEST-STATUS:END -->

---

## Setup

1. Use this template (`gh repo create <your-name>/agent-home --template billion-token-one-task/ClawOSS --include-all-branches`, then keep only the `agent-home-template/` subdir — or copy by hand).
2. Copy `.env.example` to `.env` and fill in:
   - `GH_TOKEN` — a fine-grained PAT scoped to the repos you actually want to maintain. **Do not grant org-wide write.**
   - `UPSTREAM_REPOS` — comma-separated `owner/name` list.
   - `BUDGET_TOTAL_USD` — hard cap. Cycle stops when reached.
3. Review `config/avoid-repos.yml` and `config/blocklist.yml`. The defaults are conservative — security-class issues are excluded.
4. Run one manual cycle to verify: invoke the `clawoss-skill` against this repo.
5. (Optional) Schedule cycles via Claude Code `/schedule` — recommended cadence: every 4–6 hours during business days. Faster is rarely better.

## How a cycle works

A cycle is five steps: **discover → filter → impl → PR → commit state**. See [`skill/SKILL.md`](../skill/SKILL.md) for the full contract. Each cycle ends with a `git commit` to this repo updating `state/`, this README's status block, and (sometimes) a file in `reports/`.

If a cycle crashes mid-flight, the next invocation reads the last entry in `state/cycles.json` and decides whether to abort, retry, or escalate. See the **Recovery** section of `SKILL.md`.

## Manual triggers

- **Pause the agent**: set `BUDGET_TOTAL_USD=0` in `.env`. Next cycle will exit cleanly with a `budget_exhausted` entry.
- **Force-skip a repo for one cycle**: temporarily add it to `config/avoid-repos.yml`, commit, run, then revert.
- **Block a specific issue**: add its full URL or `owner/repo#N` reference to `config/blocklist.yml` under `issues:`.

All three are recorded in `git log` of this repo — that is the audit path.

## State files

- [`state/work-queue.md`](state/work-queue.md) — human-readable. Top is current work, middle is in-progress, bottom is recently discovered candidates.
- [`state/budget.json`](state/budget.json) — money. Includes the headline KPI `cost_per_merged_pr_usd`.
- [`state/cycles.json`](state/cycles.json) — append-only ledger of every cycle attempt.

## Reports

The agent writes a monthly summary to `reports/YYYY-MM.md` at the end of each calendar month's first cycle. Post-mortems for `needs_human_review` cycles go in `reports/incidents/`.

## What this agent will not do

- It will not fan out across multiple GitHub accounts.
- It will not modify `config/`, `SKILL.md`, or its own prompt.
- It will not delete commits, force-push to upstream branches, or close issues it didn't open.
- It will not handle security-class issues (CVEs, vulnerabilities). Those are blocklisted by default.
