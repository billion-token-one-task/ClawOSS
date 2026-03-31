# ClawOSS

**English first. Chinese follows in each section.**

## Overview

ClawOSS is an OpenClaw-based autonomous OSS contribution agent configuration focused on:

- continuous autonomous operation on a single host
- structured decision, outcome, reflection, and strategy telemetry
- low-risk alpha deployment with limited human gatekeeping
- simple upgrade and rollback workflow for internal operation

This repository is not a generic AI framework. It is an opinionated autonomous OSS contribution system with a dashboard, runtime workspace, operational scripts, sidecars, and strategy-learning scaffolding.

### 中文

ClawOSS 是一套基于 OpenClaw 的自治开源贡献 agent 配置，重点是：

- 在单机上持续自主运行
- 对决策、结果、反思、策略进行结构化留痕
- 以少量人工门控实现低风险 alpha 部署
- 面向内部运行的简单升级与回滚流程

这个仓库不是通用 AI 框架，而是一套有明确工程边界的开源贡献自治系统，包含 dashboard、运行时 workspace、运维脚本、sidecar 和策略演化骨架。

## Current Release

The current recommended internal release target is:

- `v0.1.0-alpha`

Release notes:

- [docs/release-notes-v0.1.0-alpha.md](docs/release-notes-v0.1.0-alpha.md)

### 中文

当前建议的内部发布目标为：

- `v0.1.0-alpha`

发布说明见：

- [docs/release-notes-v0.1.0-alpha.md](docs/release-notes-v0.1.0-alpha.md)

## Quick Start

### Reproducible local path

```bash
git clone https://github.com/billion-token-one-task/ClawOSS.git
cd ClawOSS
cp .env.example .env
npm run doctor
npm run validate
npm run test
npm run setup
npm run start
```

### Alpha deploy path

```bash
cp .env.example .env
npm run alpha:deploy
```

Upgrade after pulling changes:

```bash
npm run alpha:upgrade
```

### 中文

### 可复现的本地路径

```bash
git clone https://github.com/billion-token-one-task/ClawOSS.git
cd ClawOSS
cp .env.example .env
npm run doctor
npm run validate
npm run test
npm run setup
npm run start
```

### alpha 部署路径

```bash
cp .env.example .env
npm run alpha:deploy
```

拉取更新后的升级命令：

```bash
npm run alpha:upgrade
```

## Required Inputs

- `GITHUB_TOKEN`
- `MINIMAX_API_KEY` as the primary model credential
- `KIMI_API_KEY` as optional fallback
- `CLAW_API_KEY` for dashboard and sidecar ingestion

By default, `config/cron-jobs.json` is empty. The current supported reproducible mode is heartbeat-driven, not cron-driven.

### 中文

- `GITHUB_TOKEN`
- `MINIMAX_API_KEY` 作为主模型凭证
- `KIMI_API_KEY` 作为可选回退模型
- `CLAW_API_KEY` 用于 dashboard 和 sidecar 上报

默认情况下 `config/cron-jobs.json` 为空。当前支持的可复现模式是 heartbeat 驱动，而不是 cron 驱动。

## Alpha Operating Model

The intended alpha operating mode is:

- AI autonomously discovers, triages, implements, and reflects
- strategy changes are generated as `draft` proposals
- high-risk actions are routed through an alpha human gate
- humans intervene only on unfamiliar repos, large changes, late-round follow-ups, or strategy promotion

Primary gate artifacts:

- [config/alpha-gates.json](config/alpha-gates.json)
- [scripts/evaluate-alpha-gate.sh](scripts/evaluate-alpha-gate.sh)
- [workspace/memory/human-review-queue.md](workspace/memory/human-review-queue.md)

### 中文

当前 alpha 的运行模式是：

- AI 自主完成发现、分诊、实现和反思
- 策略变更先以 `draft` proposal 形式生成
- 高风险动作通过 alpha 人机门控处理
- 人只在陌生仓库、大改动、后期 follow-up 或策略晋升时介入

主要门控文件：

- [config/alpha-gates.json](config/alpha-gates.json)
- [scripts/evaluate-alpha-gate.sh](scripts/evaluate-alpha-gate.sh)
- [workspace/memory/human-review-queue.md](workspace/memory/human-review-queue.md)

## Architecture

ClawOSS currently has four main layers:

1. **Agent runtime**
   - OpenClaw gateway
   - workspace prompts, skills, memory, hooks
2. **Operational scripts**
   - setup, start, restart, doctor, health-check, sync helpers
3. **Structured autonomy backend**
   - worker sidecar
   - reflection sidecar
   - ingest APIs
   - strategy/reflection storage
4. **Dashboard**
   - operational visibility
   - PR and cost telemetry
   - strategy and reflection metrics

Architecture detail:

- [docs/autonomous-backend-v1.md](docs/autonomous-backend-v1.md)

### 中文

ClawOSS 当前主要有四层：

1. **Agent 运行时**
   - OpenClaw gateway
   - workspace prompt、skills、memory、hooks
2. **运维脚本层**
   - setup、start、restart、doctor、health-check、sync 辅助脚本
3. **结构化自治后端**
   - worker sidecar
   - reflection sidecar
   - ingest API
   - strategy/reflection 存储
4. **Dashboard**
   - 运行可观测性
   - PR 与成本遥测
   - 策略与反思指标

架构说明见：

- [docs/autonomous-backend-v1.md](docs/autonomous-backend-v1.md)

## Deployment and Launch Docs

- [docs/alpha-deployment.md](docs/alpha-deployment.md)
- [docs/first-alpha-launch-checklist.md](docs/first-alpha-launch-checklist.md)
- [docs/reproducibility.md](docs/reproducibility.md)

### 中文

- [docs/alpha-deployment.md](docs/alpha-deployment.md)
- [docs/first-alpha-launch-checklist.md](docs/first-alpha-launch-checklist.md)
- [docs/reproducibility.md](docs/reproducibility.md)

## Validation Status

Release readiness for the current alpha line is based on:

- `npm run test`
- `node scripts/validate-config.mjs`
- isolated `setup` smoke
- isolated `start` smoke
- isolated `restart` smoke

### 中文

当前 alpha 线的发布就绪判断基于以下验证：

- `npm run test`
- `node scripts/validate-config.mjs`
- 隔离 `setup` 烟测
- 隔离 `start` 烟测
- 隔离 `restart` 烟测

## Recommended First Live Run

For a constrained host, start conservatively:

1. `npm run alpha:deploy -- --no-backend`
2. observe logs and health
3. enable `docker compose` sidecars only after the host runtime is stable

### 中文

对于资源紧张的服务器，建议保守启动：

1. `npm run alpha:deploy -- --no-backend`
2. 先观察日志和健康状态
3. 仅在主机运行稳定后再启用 `docker compose` sidecar

## Release Workflow

Recommended internal release workflow:

1. run `npm run test`
2. review [docs/release-notes-v0.1.0-alpha.md](docs/release-notes-v0.1.0-alpha.md)
3. review [docs/first-alpha-launch-checklist.md](docs/first-alpha-launch-checklist.md)
4. tag the release as `v0.1.0-alpha`

### 中文

建议的内部发布流程：

1. 运行 `npm run test`
2. 检查 [docs/release-notes-v0.1.0-alpha.md](docs/release-notes-v0.1.0-alpha.md)
3. 检查 [docs/first-alpha-launch-checklist.md](docs/first-alpha-launch-checklist.md)
4. 使用 `v0.1.0-alpha` 打 tag
