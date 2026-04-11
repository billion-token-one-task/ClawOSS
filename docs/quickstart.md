# 快速上手

## 前置要求

- Node.js 22+
- GitHub Classic Token（`ghp_*` 格式，需要 `repo` scope）
  - Fine-grained token（`github_pat_*`）无法在别人的仓库创建 PR，不适用
- 任意 OpenAI 兼容的 LLM API key

## 1. 配置模型

复制 `.env.example` 为 `.env`，填入 API 信息：

```bash
cp .env.example .env
```

最少需要填 6 个变量：

```bash
GITHUB_TOKEN=ghp_your-classic-token      # 必须是 classic token
LLM_PROVIDER=deepseek                     # 供应商标识
LLM_BASE_URL=https://api.deepseek.com/v1  # OpenAI 兼容端点
LLM_API_KEY=sk-your-key                   # 供应商 API Key
LLM_MODEL_COMPLEX=deepseek-reasoner       # 子 agent 用的模型（需要强推理）
LLM_MODEL_SIMPLE=deepseek-chat            # 编排用的模型（轻量即可）
```

完整供应商配置参考 [model-routing.md](model-routing.md)，支持 Anthropic、OpenAI、DeepSeek、Google Gemini、Mistral、MiniMax、Kimi、GLM 等 8 家供应商。

## 2. 切换模型

改 `.env` 中的 6 个变量后重启：

```bash
bash scripts/restart.sh
```

`restart.sh` 会读取 `.env` → 替换 `config/openclaw.json` 中的占位符 → 部署到 `~/.openclaw/openclaw.json` → 重启 gateway。

验证是否生效：

```bash
# 查看 gateway 日志中的模型信息
openclaw logs 2>&1 | grep "agent model"
# 应该输出: [gateway] agent model: deepseek/deepseek-chat
```

## 3. 预算控制

### 在哪里看额度

**Dashboard → Overview 页**：顶部 metric cards 展示 24h cost 和 total cost。

**Dashboard → Health 页**：Cost Tracking Chart 展示花费趋势。

**API**：

```bash
# 健康检查接口，返回预算信息
curl http://localhost:3000/api/agent/health-check | jq '.budget'
# {
#   "totalCostUsd": 0.42,
#   "totalBudgetUsd": 20.0,
#   "remainingUsd": 19.58,
#   "exhausted": false
# }
```

### 设置预算上限

**方式 A：环境变量（启动时固定）**

```bash
BUDGET_USD_TOTAL=20.0   # 美元，0 = 不限制
```

**方式 B：Dashboard Settings（运行时可调）**

访问 Dashboard Settings 页，修改 `totalBudgetUsd` 字段。下一个 heartbeat 周期（5 分钟）立即生效，无需重启。

当累计花费超过预算时，agent 自动停止新工作，dashboard 显示 `BUDGET EXHAUSTED` 指令。提高预算后自动恢复。

### 计费精度

当前 token 数是**估算值**（基于工具调用参数的字符长度），不是 LLM API 返回的真实 token 数。实际误差可达 5-20 倍。Dashboard 上的费用是量级参考，不能直接和供应商账单对账。详见 [model-routing.md § 计费原理](model-routing.md#计费原理)。

## 4. 双轨定价

系统区分两种模型，各自独立计价：

| 角色 | 模型变量 | 定价变量 | 用途 |
|------|---------|---------|------|
| Orchestrator | `LLM_MODEL_SIMPLE` | `INPUT_COST_PER_M_SIMPLE` / `OUTPUT_COST_PER_M_SIMPLE` | heartbeat 循环、文件读写、状态路由 |
| Sub-agents | `LLM_MODEL_COMPLEX` | `INPUT_COST_PER_M_COMPLEX` / `OUTPUT_COST_PER_M_COMPLEX` | 代码实现、bug 修复、PR review |

如果不设 per-model 定价，回退到 `INPUT_COST_PER_M` / `OUTPUT_COST_PER_M`（默认 $3/$15）。

dashboard 的 token metrics 表按 `model` 列区分两种模型的用量，Health 页的 Cost Tracking Chart 展示合计趋势。

## 5. Dashboard

### 启动

```bash
cd dashboard && npm run dev     # 开发模式，http://localhost:3000
cd dashboard && npm run build && npm run start   # 生产模式
```

### 页面说明

| 页面 | 看什么 |
|------|--------|
| **Overview** | agent 状态、子 agent 槽位、token/cost metrics、merge rate、PR 漏斗 |
| **Live Feed** | agent 实时思考过程、工具调用、错误 |
| **Pull Requests** | 所有提交的 PR，按状态/仓库/质量分筛选 |
| **Repo Health** | 目标仓库的健康评分、merge 速率、推荐策略 |
| **Health** | heartbeat、token 用量趋势、花费曲线 |
| **Quality** | PR 质量分析、首次通过率、拒绝原因 |
| **Logs** | 系统审计日志 |

### 数据来源

Dashboard 数据有三个来源：

1. **GitHub Sync**（`/api/github/sync`）— 从 GitHub API 拉取 PR 数据，基于 `GITHUB_USERNAME` 搜索
2. **Ingest API**（`/api/ingest/*`）— agent 的 dashboard-reporter hook 实时推送 heartbeat、metrics、conversation
3. **本地 DB**（`dashboard/local.db`）— SQLite 存储所有数据

如果 dashboard 显示 "Disconnected"，通常是 hook 推送不通（检查 `DASHBOARD_URL` 和 `CLAW_API_KEY` 环境变量）。

## 6. GitHub Token 说明

| Token 类型 | 格式 | 能否创建跨仓库 PR |
|-----------|------|-----------------|
| Classic token | `ghp_*` | 有 `repo` scope 即可 |
| Fine-grained token | `github_pat_*` | 不能（只对指定仓库有写权限） |

ClawOSS 需要在别人的仓库 fork → push → 创建 PR，必须使用 **Classic token + `repo` scope**。
