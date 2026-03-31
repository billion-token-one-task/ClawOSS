# Autonomous Backend V1

## Objective

Move ClawOSS from a prompt-heavy autonomous script bundle toward a backend that can:

- run continuously without per-action human approval
- retain structured decision history
- generate reflection artifacts
- version strategy safely
- run inside containers

### 中文

把 ClawOSS 从“prompt 很重的自治脚本包”推进成一套后端系统，使其能够：

- 在不需要逐动作人工批准的情况下持续运行
- 保留结构化决策历史
- 生成反思产物
- 安全地版本化策略
- 运行在容器中

## Architecture

### API

- runs the dashboard and ingest API
- persists telemetry and strategy data
- exposes metrics for merge rate, token efficiency, and strategy health

### Worker

- consumes structured execution events from `workspace/runtime/*`
- forwards decision and outcome events to the API

### Reflection

- consumes structured reflection and strategy proposal files
- forwards them to the API
- generates daily reflection artifacts
- generates `draft` strategy proposals for alpha

### Persistence

Two layers are used:

1. workspace files for current state and handoff artifacts
2. database tables for analytics, comparison, and rollback-safe history

### 中文

### API

- 负责运行 dashboard 和 ingest API
- 持久化 telemetry 与 strategy 数据
- 暴露 merge rate、token efficiency 和 strategy health 等指标

### Worker

- 消费 `workspace/runtime/*` 下的结构化执行事件
- 向 API 转发 decision 和 outcome 事件

### Reflection

- 消费结构化 reflection 与 strategy proposal 文件
- 向 API 转发这些文件
- 生成每日 reflection 产物
- 为 alpha 生成 `draft` strategy proposal

### Persistence

系统使用两层持久化：

1. workspace 文件用于保存当前状态与交接产物
2. 数据库表用于分析、比较以及可回滚的历史记录

## Core Data Objects

- `decision_events`
- `execution_outcomes`
- `reflections`
- `strategy_versions`

These tables complement existing PR, review, token, and autonomy metrics.

### 中文

- `decision_events`
- `execution_outcomes`
- `reflections`
- `strategy_versions`

这些表与现有的 PR、review、token 和 autonomy 指标形成互补。

## Strategy Lifecycle

1. the active strategy lives at `workspace/strategy/current.json`
2. reflection emits proposal JSON into `workspace/strategy/outbox/`
3. the reflection sidecar forwards proposals to `/api/ingest/strategy-version`
4. the API stores versions as `draft`, `canary`, or `active`
5. the current alpha line only auto-generates `draft` proposals

### 中文

1. 当前生效策略保存在 `workspace/strategy/current.json`
2. reflection 会把 proposal JSON 写入 `workspace/strategy/outbox/`
3. reflection sidecar 将 proposal 转发到 `/api/ingest/strategy-version`
4. API 把版本保存为 `draft`、`canary` 或 `active`
5. 当前 alpha 线只会自动生成 `draft` proposal

## Container Layout

- `api`: Next.js dashboard plus ingest API
- `worker`: runtime event sidecar
- `reflection`: reflection and strategy sidecar
- bind-mounted workspace plus persistent database volume

### 中文

- `api`：Next.js dashboard 与 ingest API
- `worker`：运行时事件 sidecar
- `reflection`：反思与策略 sidecar
- 通过 bind mount 的 workspace 和持久化数据库 volume 组合运行

## Alpha Boundary

This backend is release-ready for internal alpha, but not yet intended as a public self-serve platform.

### 中文

这套后端已经适合内部 alpha，但还不适合作为公开的自助式平台。
