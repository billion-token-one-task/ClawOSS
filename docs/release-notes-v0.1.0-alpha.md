# Release Notes — v0.1.0-alpha

## Positioning

This is the first internal alpha focused on:

- simple single-host deploy and upgrade
- autonomous AI execution with limited human gatekeeping
- structured decision, outcome, reflection, and strategy telemetry
- low-risk strategy evolution through `draft` proposals

### 中文

这是第一版内部 alpha，重点在于：

- 简单的单机部署与升级
- 带有限人工门控的 AI 自主运行
- 结构化的决策、结果、反思与策略遥测
- 通过 `draft` proposal 实现低风险策略演化

## What Is New

### Alpha Operations

- added one-command alpha wrappers:
  - `scripts/deploy-alpha.sh`
  - `scripts/upgrade-alpha.sh`
- added alpha operator docs

### Structured Autonomy Backend

- added structured runtime event files for decisions, outcomes, reflections, and strategy proposals
- added ingest APIs and schema support for strategy-learning telemetry
- added worker and reflection sidecars plus docker backend skeleton

### Reflection and Strategy Drafting

- added daily reflection generation from processed decision/outcome events
- added draft strategy proposal generation from reflection recommendations
- kept rollout conservative for alpha:
  - proposals stay `draft`
  - canary metadata is attached
  - active strategy is not auto-mutated

### Alpha Human Gate

- added alpha gate config, evaluator, and human review queue
- routed high-risk submit and follow-up actions into an inspectable manual queue

### Reproducibility and Safety

- standardized workspace bootstrap and path resolution
- added doctor and portability checks
- added isolated smoke coverage for `setup`, `start`, and `restart`
- added restart smoke mode to avoid host-global cleanup during release validation

### 中文

### Alpha 运维

- 增加了一键 alpha 包装脚本：
  - `scripts/deploy-alpha.sh`
  - `scripts/upgrade-alpha.sh`
- 增加了 alpha 运维文档

### 结构化自治后端

- 增加了决策、结果、反思和策略 proposal 的结构化运行时文件
- 增加了面向策略学习遥测的 ingest API 和 schema 支持
- 增加了 worker、reflection sidecar 和 docker 后端骨架

### 反思与策略草案

- 增加了基于 processed decision/outcome 事件的每日反思生成
- 增加了基于 reflection recommendation 的 draft 策略 proposal 生成
- 保持 alpha 阶段 rollout 的保守性：
  - proposal 保持为 `draft`
  - 附带 canary 元数据
  - 不自动改写 active strategy

### Alpha 人机门控

- 增加了 alpha gate 配置、评估脚本和人工复核队列
- 把高风险 submit 和 follow-up 动作路由到可检查的人工队列

### 可复现性与安全

- 统一了 workspace bootstrap 和路径解析
- 增加了 doctor 和 portability 检查
- 增加了 `setup`、`start`、`restart` 的隔离烟测
- 增加了 restart smoke 模式，避免在发布验证时触发主机级全局清理

## Validation

Validated with:

- `npm run test`
- `node scripts/validate-config.mjs`
- isolated `setup` smoke
- isolated `start` smoke
- isolated `restart` smoke

### 中文

验证方式包括：

- `npm run test`
- `node scripts/validate-config.mjs`
- 隔离 `setup` 烟测
- 隔离 `start` 烟测
- 隔离 `restart` 烟测

## Recommended Tag

- `v0.1.0-alpha`

### 中文

- `v0.1.0-alpha`
