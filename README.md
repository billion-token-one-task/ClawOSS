# ClawOSS

[English](./README.md) | [中文](./README.zh-CN.md)

ClawOSS is an OpenClaw-based autonomous OSS contribution system. It continuously discovers candidate repositories and issues, evaluates contribution fit, runs implementation workers, records outcomes, and now ships with a deployable alpha control plane for reflection and strategy drafting.

This branch, `alpha/v0.1.0`, is positioned as an internal alpha:

- single-host deployment and upgrade are first-class
- AI runs autonomously for most day-to-day work
- high-risk actions are gated instead of being fully unbounded
- decisions, outcomes, reflections, and strategy proposals are structured and inspectable

## Quick Start

```bash
git clone https://github.com/billion-token-one-task/ClawOSS.git
cd ClawOSS
git switch alpha/v0.1.0
cp .env.example .env
npm run alpha:deploy
```

Upgrade an existing alpha host with:

```bash
npm run alpha:upgrade
```

## Prerequisites

Host requirements:

- `node` and `npm`
- `openclaw`
- `gh`
- `git`
- `docker` and `docker compose` for the dashboard/API sidecars

Minimum env values:

- `GITHUB_TOKEN`
- `MINIMAX_API_KEY`
- `CLAW_API_KEY`

## What Changed vs. the Previous Version

The previous version proved that a multi-agent stack could generate a large number of OSS pull requests. This alpha focuses on making that system operable, explainable, and maintainable.

| Area | Previous version | `v0.1.0-alpha` |
|---|---|---|
| Deployment | mostly author-environment oriented | one-command alpha deploy and upgrade wrappers |
| Runtime visibility | PR/results visible, but decisions were hard to replay | structured `decision`, `outcome`, `reflection`, and `strategy` telemetry |
| Targeting analysis | weak explanation of why a repo/issue was selected | candidate set, final pick, and outcome can be traced end-to-end |
| Follow-up governance | follow-up was recognized, but weakly measured | outcome events, human review queue, and alpha gates for risky paths |
| Strategy evolution | prompt and scripts carried most policy | reflection artifacts and draft strategy proposals exist as separate control objects |
| Safety | close to fully automatic behavior | autonomous by default, but high-risk actions can be gated |
| Reproducibility | hard for third parties to reproduce safely | doctor, portability fixes, smoke modes, and alpha operator docs |

What has not yet been proven by this release:

- higher merge rate in production
- lower tokens-per-merge in production
- elimination of the orchestrator cost bottleneck

This alpha improves the system's engineering surface and its ability to learn from runs. Actual efficiency gains still need runtime data.

## Operating Model

The intended alpha operating mode is:

- AI autonomously discovers, triages, implements, and reflects
- strategy proposals stay conservative and remain `draft`
- humans intervene only on a small number of high-risk actions
- the system is designed for iterative upgrades instead of one-off experiments

High-risk gates are defined in [config/alpha-gates.json](./config/alpha-gates.json).  
Queued manual checks are written to [workspace/memory/human-review-queue.md](./workspace/memory/human-review-queue.md).

## Recommended Deployment

Default recommendation:

- host machine runs `openclaw`, `gh`, and the main ClawOSS agent
- `docker compose` runs the dashboard/API plus `worker` and `reflection` sidecars
- `.env` and [workspace/strategy/current.json](./workspace/strategy/current.json) remain the main editable config surfaces

Minimal host-only mode is also possible:

- run `npm run alpha:deploy -- --no-backend`
- add the dockerized sidecars later if the host runtime is stable

This is documented in:

- [Alpha Deployment](./docs/alpha-deployment.md)
- [Reproducibility](./docs/reproducibility.md)
- [Autonomous Backend v1](./docs/autonomous-backend-v1.md)

## Vercel Limitation

Vercel can host the `dashboard` and API layer, but it cannot run the full autonomous agent.

- suitable for Vercel: Next.js dashboard, API routes, GitHub sync cron
- not suitable for Vercel: `openclaw`, the main long-running agent loop, local workspace state, shell-driven automation

If you deploy the dashboard on Vercel, use an external database such as Turso. Falling back to `/tmp` storage is ephemeral.

## Validation

This alpha was validated with:

- `npm run test`
- `node scripts/validate-config.mjs`
- isolated smoke coverage for `setup`
- isolated smoke coverage for `start`
- isolated smoke coverage for `restart`

## Release Notes

- [Release Notes: v0.1.0-alpha](./docs/release-notes-v0.1.0-alpha.md)
- [First Alpha Launch Checklist](./docs/first-alpha-launch-checklist.md)
- [Changelog](./CHANGELOG.md)
