---
name: clawoss-skill
description: Run one long-running OSS maintainer cycle. Discover candidate issues across the user's configured upstream repos, filter for fit / blocklist / supersession, implement one PR, push, then commit state back to the agent-home repo. Use when running scheduled or manual maintenance cycles on owned or forked OSS projects.
---

# clawoss-skill — one cycle

Successor to the self-hosted ClawOSS gateway + dashboard architecture (frozen at `v1.0`). One invocation of this skill = **one cycle** of work against the user's `agent-home` repo. State persists by `git commit`; audit trail = `git log` of agent-home.

This skill is the public demo of a long-running agent runtime. It is intentionally narrow:

- single account (no fan-out, no account proxying)
- no paid subscription tier
- no self-evolution / no auto-tuning of its own prompts
- merge-rate is an observation, not a target

## Inputs

Working dir = the user's `agent-home` repo (a fork of `agent-home-template/`). The skill expects:

- `state/work-queue.md`, `state/budget.json`, `state/cycles.json` — readable & writable
- `config/blocklist.yml`, `config/avoid-repos.yml` — read-only inputs
- `.env` (gitignored) — `GH_TOKEN`, target repo list, budget caps
- A clean working tree on the default branch

If any of the above is missing, **abort the cycle**, append a `setup_error` entry to `cycles.json`, and exit non-zero. Do not auto-create config.

## The five steps

Each cycle runs these steps in order. Stop on first hard-fail. Every step writes a status line to `state/cycles.json` so a crash is recoverable on the next run.

### 1. discover

For each repo in the user's configured upstream list (in `.env`, not in `avoid-repos.yml`):

- Query GitHub for `is:issue is:open` with `good-first-issue`, `help-wanted`, `documentation`, or repo-specific easy labels — capped at the 20 most recently updated per repo.
- For each candidate, record: `repo`, `issue_number`, `title`, `labels`, `updated_at`, `comment_count`, `author_association`.
- Append the deduped result to the **Recently Discovered** section of `state/work-queue.md` (auto-managed block). Cap the section at 10 rows; evict by `updated_at`.

Budget guard: if `spent_usd >= budget_total_usd`, write a `budget_exhausted` entry and exit cleanly. Use `>` semantics — never `>=` on the per-cycle add (this is the off-by-one fixed in v1.0 `bf36581`).

### 2. filter

For the top candidates from step 1, apply in order:

1. **avoid-repos.yml**: drop if `repo` matches.
2. **blocklist.yml**: drop if any of {labels, title keywords, file globs touched} matches. Security-class issues are blocklisted by default.
3. **Supersession check**: drop if an open PR on the same repo already references this issue (`gh pr list --search "linked:<issue>"`).
4. **Author-association**: drop if the issue author is the bot account itself (loop guard).
5. **Merge-probability heuristic**: prefer issues with a maintainer comment in the last 60 days; deprioritize stale issues (no activity > 180 days).

Pick **one** survivor. If zero, write a `no_candidate` cycle entry and exit cleanly — this is a normal outcome.

### 3. impl

Work in a fresh worktree on a topic branch named `clawoss/<repo-slug>-<issue-number>`. Implement the smallest change that resolves the issue. Hard rules:

- One issue per PR. No drive-by refactors.
- No new dependencies without a written justification in the PR body.
- No changes to security-sensitive paths (`config/blocklist.yml: file_patterns`).
- If implementation requires more than ~200 LOC of net change, abort and append a `scope_too_large` cycle entry — escalate to human review by leaving the candidate in **Pending** of `work-queue.md`.

Run the repo's local test command if one is detectable (`package.json` scripts, `pyproject.toml`, `Makefile` targets). Do not invent test runs.

### 4. PR

Push the topic branch. Open the PR with `gh pr create`. PR body MUST contain:

- A one-line summary of the change.
- The issue link (`Fixes #N` only if the maintainers' contribution guide allows auto-close — otherwise `Refs #N`).
- A short "How I tested" section with the literal commands run.
- A disclosure line: `This PR was authored by an automated long-running agent (clawoss-skill).`

If `gh pr create` fails (rate limit, fork required, push permission), record the error in `cycles.json` and exit cleanly. Do not retry inside the same cycle.

### 5. commit state

In the agent-home repo (NOT the upstream worktree):

1. Append the cycle outcome to `state/cycles.json` — schema in `state/cycles.json` header comment.
2. Update `state/budget.json`: `spent_usd += <cycle cost>`, recompute `cost_per_merged_pr_usd` (= `spent_usd / merged_pr_count`, `null` if denominator is 0).
3. Move the candidate from **Recently Discovered** to **In Progress** in `state/work-queue.md`.
4. Rewrite the `<!-- LATEST-STATUS:START -->` / `<!-- LATEST-STATUS:END -->` block in `README.md` (α-phase dashboard).
5. `git add state/ README.md && git commit -m "cycle <ISO-timestamp>: <outcome>"` and push.

The commit is the audit record. Do not write a separate log file.

## Cost accounting

Use the Claude Code session's real API usage as the source of truth — there is no estimator and no telemetry pricing endpoint. Read it at end-of-cycle and write the delta into `state/cycles.json` and `state/budget.json`. (This is the architecture choice that makes the "5–20x estimator drift" diagnosed in v1.0 PR #2 a non-issue here.)

## Recovery / idempotence

If the previous cycle's `cycles.json` last entry has no `ended_at`, the cycle crashed mid-flight. On startup, the skill must:

1. Inspect the crashed cycle's `phase` field.
2. If `phase < impl`, mark it `aborted_crash` and start a fresh cycle.
3. If `phase >= impl`, **stop** — leave a `needs_human_review` entry and exit. Do not auto-recover open branches; human decides whether to push, delete, or resume.

## Scripts (helpers, not Skill logic)

`skill/scripts/` holds small shell helpers the Skill may shell out to:

- `check-blocklist.sh <repo> <issue-json>` — exit 0 = blocked, exit 1 = clear
- `check-supersession.sh <repo> <issue-number>` — exit 0 = superseded, exit 1 = clear
- `score-merge-prob.sh <repo> <issue-json>` — prints integer 0–100, higher = better

These are wrappers around `gh` + `jq`. Keep the Skill's prose self-sufficient; scripts exist so the prose stays readable.

## What this Skill deliberately does NOT do

- No multi-account fan-out
- No paid subscription / billing
- No metric optimization loops (no "raise merge rate by X%")
- No self-editing of `SKILL.md` or its own configs
- No dashboard writes beyond `README.md` (β-phase React dashboard is read-only against agent-home GitHub API)

These boundaries are load-bearing for the demo's narrative: a long-running agent runtime that replaces a human OSS-maintenance role within a single, auditable, version-controlled home.
