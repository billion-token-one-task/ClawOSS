# ClawOSS

[English](./README.md) | [中文](./README.zh-CN.md)

ClawOSS 是一个基于 OpenClaw 的自治 OSS 贡献系统。它会持续发现候选仓库和 issue，评估贡献价值，调度实现 worker，记录执行结果，并在当前 `alpha/v0.1.0` 分支中提供可部署的反思与策略草案控制面。

这个分支 `alpha/v0.1.0` 的定位是内部 alpha：

- 把单机部署和升级作为一等能力
- 大部分日常动作由 AI 自主运行
- 高风险动作加入门控，而不是完全裸奔自动化
- 决策、结果、反思和策略 proposal 都是结构化且可检查的

## 快速开始

```bash
git clone https://github.com/billion-token-one-task/ClawOSS.git
cd ClawOSS
git switch alpha/v0.1.0
cp .env.example .env
npm run alpha:deploy
```

已有 alpha 环境升级：

```bash
npm run alpha:upgrade
```

## 前置依赖

宿主机需要具备：

- `node` 和 `npm`
- `openclaw`
- `gh`
- `git`
- 如果要启用 dashboard/API sidecar，还需要 `docker` 和 `docker compose`

最少需要配置的环境变量：

- `GITHUB_TOKEN`
- `MINIMAX_API_KEY`
- `CLAW_API_KEY`

## 相对上一版的变化

上一版证明了多 Agent 架构可以高密度地产出 OSS PR。这一版 alpha 的重点则是把系统变成可运维、可解释、可维护的内部版本。

| 维度 | 上一版 | `v0.1.0-alpha` |
|---|---|---|
| 部署 | 更偏作者个人环境 | 增加一键 alpha 部署和升级包装脚本 |
| 运行可见性 | 能看到 PR 和结果，但难重放决策过程 | 增加结构化 `decision`、`outcome`、`reflection`、`strategy` 数据面 |
| 选题分析 | 很难回答“为什么选了这个 repo/issue” | 候选集、最终 pick 和结果可以端到端追踪 |
| follow-up 治理 | 知道要跟进，但度量与闭环较弱 | 增加 outcome 事件、人工复核队列和 alpha 门控 |
| 策略演化 | 策略大量埋在 prompt 和脚本里 | 反思产物与 draft strategy proposal 独立存在 |
| 安全性 | 接近完全自动化 | 默认自治，但高风险动作可门控 |
| 可复现性 | 第三方难以安全复现 | 增加 doctor、可移植性修复、smoke 模式和 alpha 运维文档 |

这一版仍然没有直接证明：

- 线上 merge rate 已经更高
- 线上 tokens per merge 已经更低
- orchestrator 的成本瓶颈已经被根治

这一版主要提升的是工程成熟度，以及系统从运行结果中学习和修正的能力。真实效率提升仍然需要后续运行数据验证。

## 运行模式

当前 alpha 的预期运行方式是：

- AI 自主完成发现、分诊、实现和反思
- 策略 proposal 保持为保守的 `draft`
- 只有少量高风险动作需要人介入
- 系统以可持续升级为目标，而不是一次性实验

高风险门控配置见 [config/alpha-gates.json](./config/alpha-gates.json)。  
待人工处理的队列写入 [workspace/memory/human-review-queue.md](./workspace/memory/human-review-queue.md)。

## 推荐部署方式

默认推荐：

- 主机负责运行 `openclaw`、`gh` 和主 ClawOSS agent
- `docker compose` 负责运行 dashboard/API 以及 `worker`、`reflection` sidecar
- `.env` 与 [workspace/strategy/current.json](./workspace/strategy/current.json) 是主要可编辑配置面

也支持最小主机模式：

- 执行 `npm run alpha:deploy -- --no-backend`
- 等主机运行稳定后，再补上 docker sidecar

相关文档：

- [Alpha Deployment](./docs/alpha-deployment.md)
- [Reproducibility](./docs/reproducibility.md)
- [Autonomous Backend v1](./docs/autonomous-backend-v1.md)

## Vercel 限制

Vercel 可以承载 `dashboard` 和 API 层，但不能运行完整的自治 agent。

- 适合放到 Vercel：Next.js dashboard、API 路由、GitHub sync cron
- 不适合放到 Vercel：`openclaw`、主循环常驻 agent、本地 workspace 状态、shell 驱动自动化

如果把 dashboard 部署到 Vercel，数据库应使用 Turso 之类的外部存储，不要依赖 `/tmp` 的临时文件。

## 验证

当前 alpha 的验证方式包括：

- `npm run test`
- `node scripts/validate-config.mjs`
- `setup` 的隔离 smoke 测试
- `start` 的隔离 smoke 测试
- `restart` 的隔离 smoke 测试

## 发布说明

- [Release Notes: v0.1.0-alpha](./docs/release-notes-v0.1.0-alpha.md)
- [First Alpha Launch Checklist](./docs/first-alpha-launch-checklist.md)
- [Changelog](./CHANGELOG.md)
