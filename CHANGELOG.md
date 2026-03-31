# Changelog

**English first. Chinese follows in each section.**

## 2026-03-31 — v0.1.0-alpha Release Prep

### English

- prepared the repository for the first internal `v0.1.0-alpha` release
- added alpha deploy and upgrade wrappers:
  - `scripts/deploy-alpha.sh`
  - `scripts/upgrade-alpha.sh`
- added alpha release docs:
  - `docs/alpha-deployment.md`
  - `docs/first-alpha-launch-checklist.md`
  - `docs/release-notes-v0.1.0-alpha.md`
- added structured decision, outcome, reflection, and strategy telemetry
- added reflection generation and draft strategy proposal generation
- added alpha human gate support:
  - `config/alpha-gates.json`
  - `scripts/evaluate-alpha-gate.sh`
  - `workspace/memory/human-review-queue.md`
- added isolated smoke coverage for `setup`, `start`, and `restart`
- confirmed release readiness with:
  - `npm run test`
  - `node scripts/validate-config.mjs`

### 中文

- 为首次内部 `v0.1.0-alpha` 发布完成仓库收口
- 增加 alpha 部署与升级包装脚本：
  - `scripts/deploy-alpha.sh`
  - `scripts/upgrade-alpha.sh`
- 增加 alpha 发布文档：
  - `docs/alpha-deployment.md`
  - `docs/first-alpha-launch-checklist.md`
  - `docs/release-notes-v0.1.0-alpha.md`
- 增加结构化的决策、结果、反思与策略遥测
- 增加反思生成与 draft 策略 proposal 生成
- 增加 alpha 人机门控支持：
  - `config/alpha-gates.json`
  - `scripts/evaluate-alpha-gate.sh`
  - `workspace/memory/human-review-queue.md`
- 增加 `setup`、`start`、`restart` 的隔离烟测
- 通过以下验证确认发布就绪：
  - `npm run test`
  - `node scripts/validate-config.mjs`

## 2026-03-30 — Structured Autonomy Foundation

### English

- standardized workspace bootstrap and path resolution
- added doctor and portability checks
- added structured runtime events for decisions and outcomes
- added queue candidate and queue pick recording
- added reflection sidecar and strategy proposal plumbing
- added docker backend skeleton for `api`, `worker`, and `reflection`

### 中文

- 统一了 workspace bootstrap 和路径解析
- 增加了 doctor 和 portability 检查
- 增加了决策与结果的结构化运行时事件
- 增加了候选集与最终选项的 queue 记录
- 增加了 reflection sidecar 和 strategy proposal 链路
- 增加了 `api`、`worker`、`reflection` 的 docker 后端骨架

## 2026-03-16 — Early Build and Dashboard Foundation

### English

- created the initial OpenClaw workspace structure
- added custom OSS contribution skills and operational scripts
- established dashboard, telemetry, and GitHub identity foundations
- iterated on throughput, model selection, and autonomous orchestration

### 中文

- 创建了初始 OpenClaw workspace 结构
- 增加了自定义 OSS 贡献技能与运维脚本
- 建立了 dashboard、遥测和 GitHub 身份基础
- 持续迭代吞吐、模型选择与自治编排方案

## Notes

### English

This changelog is intentionally condensed for the alpha line. Detailed historical implementation trace remains available through Git history.

### 中文

这个 changelog 为 alpha 线做了收敛整理。更细的历史实现轨迹仍可通过 Git 提交历史查看。
