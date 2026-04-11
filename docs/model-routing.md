# 模型路由

## 目标

1. **任意主流模型**：通过环境变量切换供应商和模型，无需改代码
2. **双轨路由**：复杂任务用 Opus 级模型，简单任务用 Sonnet 级模型
3. **总预算熔断**：累计花费达到上限时服务自动暂停
4. **Dashboard 可视**：实时显示模型配置、累计花费、预算进度

## 路由规则

| 角色 | 使用模型 | 原因 |
|------|---------|------|
| Orchestrator（heartbeat 主循环） | `LLM_MODEL_SIMPLE` | 只做文件读写、状态路由 |
| 主 Agent session | `LLM_MODEL_SIMPLE` | 同上 |
| 所有 Sub-agents（实现、跟进、监控） | `LLM_MODEL_COMPLEX` | 需深度理解代码、写 patch、分析 review |

Fallback：complex 失败时回退 simple。

## 配置注入机制

```
.env
  ↓ restart.sh 读取
config/openclaw.json（含 __LLM_*__ 占位符）
  ↓ sed 替换占位符
~/.openclaw/openclaw.json（已注入实际值）
  ↓ OpenClaw gateway 启动时读取
Agent 运行（使用正确模型）
```

改了 `.env` 后必须 `bash scripts/restart.sh` 重启才能生效。

---

## 环境变量

所有变量在 `.env` 中配置，`restart.sh` 读取后注入到 OpenClaw config 和 gateway plist。

### 必填

| 变量 | 说明 | 示例 |
|------|------|------|
| `LLM_PROVIDER` | 供应商 key，作为 OpenClaw provider 块名和模型 ID 前缀 | `anthropic` |
| `LLM_BASE_URL` | OpenAI 兼容 API 端点 | `https://api.anthropic.com/v1` |
| `LLM_API_KEY` | 供应商 API 密钥 | `sk-ant-...` |
| `LLM_MODEL_COMPLEX` | 复杂任务模型 ID（sub-agents 使用） | `claude-opus-4-6` |
| `LLM_MODEL_SIMPLE` | 简单任务模型 ID（orchestrator 使用） | `claude-sonnet-4-6` |
| `GITHUB_TOKEN` | GitHub PAT，需 `public_repo` 权限 | `ghp_...` |

### 计价

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `INPUT_COST_PER_M_COMPLEX` | Complex 模型输入价（$/M token） | 读 `INPUT_COST_PER_M` |
| `OUTPUT_COST_PER_M_COMPLEX` | Complex 模型输出价（$/M token） | 读 `OUTPUT_COST_PER_M` |
| `INPUT_COST_PER_M_SIMPLE` | Simple 模型输入价（$/M token） | 读 `INPUT_COST_PER_M` |
| `OUTPUT_COST_PER_M_SIMPLE` | Simple 模型输出价（$/M token） | 读 `OUTPUT_COST_PER_M` |
| `INPUT_COST_PER_M` | 通用 fallback 输入价 | `3.0` |
| `OUTPUT_COST_PER_M` | 通用 fallback 输出价 | `15.0` |

### 模型参数

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `LLM_CONTEXT_WINDOW` | 上下文窗口（tokens） | `200000` |
| `LLM_MAX_TOKENS` | 最大输出（tokens） | `32000` |

### 预算

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `BUDGET_USD_TOTAL` | 累计总预算（美元），`0` = 不限制 | `0` |
| `MODEL_TOKEN_BUDGETS` | 每模型 token 上限的 JSON 映射，`0` 或缺省 = 不限制 | `{}` |

`MODEL_TOKEN_BUDGETS` 示例：

```bash
MODEL_TOKEN_BUDGETS='{"glm-4.6":20000000,"deepseek-chat":50000000,"claude-opus-4-6":10000000}'
```

**关键语义**：

- **key 是 bare model name**（与供应商前缀无关）。系统按 model name 的最后一段做匹配，全部小写化。`z-ai/glm-4.6`、`openrouter/glm-4.6`、`zhipu/glm-4.6` 都会被合并到同一个 `glm-4.6` 计数器，跨供应商累加。
- value 是**累计 token 上限**（input + output 之和）。
- value `0` 或缺省 = 不限制。
- 触发后行为：health-check 在 directives 顶部插入 `MODEL TOKEN BUDGET EXHAUSTED: <model> ...`，agent 停止派发使用该模型的 sub-agent。Dashboard 顶部出现红色横幅。
- **不能用 `LLM_BASE_URL` 或 provider 字段判定模型**——同一个模型可能从多个供应商接入，必须用 model name 匹配。

### Dashboard

| 变量 | 说明 |
|------|------|
| `DASHBOARD_URL` | Dashboard URL |
| `CLAW_API_KEY` | Dashboard API 共享密钥 |
| `NEXT_PUBLIC_LLM_PROVIDER` | 浏览器端显示用（镜像 `LLM_PROVIDER`） |
| `NEXT_PUBLIC_LLM_MODEL_COMPLEX` | 浏览器端显示用 |
| `NEXT_PUBLIC_LLM_MODEL_SIMPLE` | 浏览器端显示用 |

---

## 供应商配置 & 定价

> 价格：2026 年 4 月核实。使用前请在供应商文档确认最新价格。

### 价格对照表

| 供应商 | Complex 模型 | Simple 模型 | Complex 输入/输出 $/M | Simple 输入/输出 $/M |
|--------|-------------|------------|----------------------|---------------------|
| Anthropic | claude-opus-4-6 | claude-sonnet-4-6 | $5 / $25 | $3 / $15 |
| OpenAI | gpt-4o | gpt-4o-mini | $2.5 / $10 | $0.15 / $0.6 |
| Google | gemini-2.5-pro | gemini-2.5-flash | $1.25 / $10 | $0.30 / $2.50 |
| Mistral | mistral-large-3 | mistral-small-3.1 | $2 / $6 | $0.20 / $0.60 |
| DeepSeek | deepseek-reasoner | deepseek-chat | $0.28 / $0.42 | $0.28 / $0.42 |
| MiniMax | MiniMax-M2.7 | MiniMax-M2.5 | $0.30 / $1.20 | $0.30 / $1.20 |
| Kimi | kimi-k2.5 | moonshot-v1-32k | $0.60 / $3.00 | $3.29 / $3.29 |
| GLM | glm-4.7 | glm-4.5-air | $0.60 / $2.20 | $0.20 / $1.10 |

### Anthropic Claude

文档：https://platform.claude.com/docs/en/about-claude/pricing

Opus 4.6/4.5 已降价至 $5/$25（原 $15/$75）。4.6 系列支持 1M context window，标准费率。

| 模型 | 输入 $/M | 输出 $/M | Cache hit $/M | 上下文 |
|------|---------|---------|--------------|--------|
| claude-opus-4-6 | $5.0 | $25.0 | $0.50 | 1M |
| claude-sonnet-4-6 | $3.0 | $15.0 | $0.30 | 1M |
| claude-opus-4-5 | $5.0 | $25.0 | $0.50 | 1M |
| claude-sonnet-4-5 | $3.0 | $15.0 | $0.30 | 1M |
| claude-haiku-4-5 | $1.0 | $5.0 | $0.10 | 200k |

```bash
LLM_PROVIDER=anthropic
LLM_BASE_URL=https://api.anthropic.com/v1
LLM_API_KEY=sk-ant-...
LLM_MODEL_COMPLEX=claude-opus-4-6
LLM_MODEL_SIMPLE=claude-sonnet-4-6
INPUT_COST_PER_M_COMPLEX=5.0
OUTPUT_COST_PER_M_COMPLEX=25.0
INPUT_COST_PER_M_SIMPLE=3.0
OUTPUT_COST_PER_M_SIMPLE=15.0
LLM_CONTEXT_WINDOW=1000000
LLM_MAX_TOKENS=32000
NEXT_PUBLIC_LLM_PROVIDER=anthropic
NEXT_PUBLIC_LLM_MODEL_COMPLEX=claude-opus-4-6
NEXT_PUBLIC_LLM_MODEL_SIMPLE=claude-sonnet-4-6
```

### OpenAI

文档：https://openai.com/api/pricing

| 模型 | 输入 $/M | 输出 $/M | Cache hit $/M | 上下文 |
|------|---------|---------|--------------|--------|
| gpt-4o | $2.5 | $10.0 | $1.25 | 128k |
| gpt-4o-mini | $0.15 | $0.6 | $0.075 | 128k |
| o3 | $10.0 | $40.0 | -- | 200k |
| o4-mini | $1.1 | $4.4 | -- | 200k |

```bash
LLM_PROVIDER=openai
LLM_BASE_URL=https://api.openai.com/v1
LLM_API_KEY=sk-...
LLM_MODEL_COMPLEX=gpt-4o
LLM_MODEL_SIMPLE=gpt-4o-mini
INPUT_COST_PER_M_COMPLEX=2.5
OUTPUT_COST_PER_M_COMPLEX=10.0
INPUT_COST_PER_M_SIMPLE=0.15
OUTPUT_COST_PER_M_SIMPLE=0.6
LLM_CONTEXT_WINDOW=128000
LLM_MAX_TOKENS=16000
NEXT_PUBLIC_LLM_PROVIDER=openai
NEXT_PUBLIC_LLM_MODEL_COMPLEX=gpt-4o
NEXT_PUBLIC_LLM_MODEL_SIMPLE=gpt-4o-mini
```

### DeepSeek

文档：https://api-docs.deepseek.com/quick_start/pricing

`deepseek-chat` 和 `deepseek-reasoner` 现均为 DeepSeek-V3.2，价格相同。
区别：reasoner 是 thinking 模式，最大输出 32K；chat 是非 thinking，最大输出 8K。
Cache hit 价格比 cache miss 便宜 90%。

| 模型 | 输入 $/M (miss) | 输入 $/M (hit) | 输出 $/M | 上下文 |
|------|----------------|---------------|---------|--------|
| deepseek-chat | $0.28 | $0.028 | $0.42 | 128k |
| deepseek-reasoner | $0.28 | $0.028 | $0.42 | 128k |

```bash
LLM_PROVIDER=deepseek
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_API_KEY=sk-...
LLM_MODEL_COMPLEX=deepseek-reasoner
LLM_MODEL_SIMPLE=deepseek-chat
INPUT_COST_PER_M_COMPLEX=0.28
OUTPUT_COST_PER_M_COMPLEX=0.42
INPUT_COST_PER_M_SIMPLE=0.28
OUTPUT_COST_PER_M_SIMPLE=0.42
LLM_CONTEXT_WINDOW=128000
LLM_MAX_TOKENS=32000
NEXT_PUBLIC_LLM_PROVIDER=deepseek
NEXT_PUBLIC_LLM_MODEL_COMPLEX=deepseek-reasoner
NEXT_PUBLIC_LLM_MODEL_SIMPLE=deepseek-chat
```

### MiniMax

文档：https://platform.minimax.io/docs/guides/pricing-paygo

highspeed 变体延迟更低，价格翻倍。

| 模型 | 输入 $/M | 输出 $/M | 上下文 |
|------|---------|---------|--------|
| MiniMax-M2.7 | $0.30 | $1.20 | 204k |
| MiniMax-M2.7-highspeed | $0.60 | $2.40 | 204k |
| MiniMax-M2.5 | $0.30 | $1.20 | 204k |
| MiniMax-M2.5-highspeed | $0.60 | $2.40 | 204k |
| MiniMax-M2 | $0.30 | $1.20 | 204k |

```bash
LLM_PROVIDER=minimax
LLM_BASE_URL=https://api.minimaxi.com/v1
LLM_API_KEY=...
LLM_MODEL_COMPLEX=MiniMax-M2.7
LLM_MODEL_SIMPLE=MiniMax-M2.5
INPUT_COST_PER_M_COMPLEX=0.30
OUTPUT_COST_PER_M_COMPLEX=1.20
INPUT_COST_PER_M_SIMPLE=0.30
OUTPUT_COST_PER_M_SIMPLE=1.20
LLM_CONTEXT_WINDOW=204800
LLM_MAX_TOKENS=131072
NEXT_PUBLIC_LLM_PROVIDER=minimax
NEXT_PUBLIC_LLM_MODEL_COMPLEX=MiniMax-M2.7
NEXT_PUBLIC_LLM_MODEL_SIMPLE=MiniMax-M2.5
```

### Kimi / Moonshot

文档：https://platform.kimi.ai/docs/pricing/chat

kimi-k2.5 是最新编程模型，cache hit 价格比 cache miss 便宜 83%。
moonshot-v1 系列是按 token 长度统一计价的旧款通用模型。

| 模型 | 输入 $/M (miss) | 输入 $/M (hit) | 输出 $/M | 上下文 |
|------|----------------|---------------|---------|--------|
| kimi-k2.5 | $0.60 | $0.10 | $3.00 | 131k |
| kimi-k2 | $0.55 | -- | $2.20 | 131k |
| moonshot-v1-8k | $1.65 | -- | $1.65 | 8k |
| moonshot-v1-32k | $3.29 | -- | $3.29 | 32k |
| moonshot-v1-128k | $8.22 | -- | $8.22 | 128k |

```bash
LLM_PROVIDER=moonshot
LLM_BASE_URL=https://api.moonshot.cn/v1
LLM_API_KEY=sk-...
LLM_MODEL_COMPLEX=kimi-k2.5
LLM_MODEL_SIMPLE=moonshot-v1-32k
INPUT_COST_PER_M_COMPLEX=0.60
OUTPUT_COST_PER_M_COMPLEX=3.00
INPUT_COST_PER_M_SIMPLE=3.29
OUTPUT_COST_PER_M_SIMPLE=3.29
LLM_CONTEXT_WINDOW=131072
LLM_MAX_TOKENS=32000
NEXT_PUBLIC_LLM_PROVIDER=moonshot
NEXT_PUBLIC_LLM_MODEL_COMPLEX=kimi-k2.5
NEXT_PUBLIC_LLM_MODEL_SIMPLE=moonshot-v1-32k
```

### GLM / Zhipu AI

国际 API：https://api.z.ai/v1（文档：https://docs.z.ai/guides/overview/pricing）
国内 API：https://open.bigmodel.cn/api/paas/v4

`glm-4.7-flash` 和 `glm-4.5-flash` 完全免费，可用作 simple 模型把编排成本压到零。

| 模型 | 输入 $/M | 输出 $/M | 备注 |
|------|---------|---------|------|
| glm-5.1 | $1.40 | $4.40 | |
| glm-5 | $1.00 | $3.20 | |
| glm-5-turbo | $1.20 | $4.00 | |
| glm-4.7 | $0.60 | $2.20 | |
| glm-4.7-flashx | $0.07 | $0.40 | 轻量快速 |
| glm-4.7-flash | 免费 | 免费 | |
| glm-4.5 | $0.60 | $2.20 | |
| glm-4.5-x | $2.20 | $8.90 | 32B MoE |
| glm-4.5-air | $0.20 | $1.10 | 适合 simple 模型 |
| glm-4.5-airx | $1.10 | $4.50 | |
| glm-4.5-flash | 免费 | 免费 | |
| glm-4-32b-0414-128k | $0.10 | $0.10 | |

```bash
LLM_PROVIDER=z-ai
LLM_BASE_URL=https://api.z.ai/v1
LLM_API_KEY=...
LLM_MODEL_COMPLEX=glm-4.7
LLM_MODEL_SIMPLE=glm-4.5-air        # 或 glm-4.7-flash（免费）
INPUT_COST_PER_M_COMPLEX=0.60
OUTPUT_COST_PER_M_COMPLEX=2.20
INPUT_COST_PER_M_SIMPLE=0.20        # glm-4.7-flash 填 0
OUTPUT_COST_PER_M_SIMPLE=1.10       # glm-4.7-flash 填 0
LLM_CONTEXT_WINDOW=128000
LLM_MAX_TOKENS=32000
NEXT_PUBLIC_LLM_PROVIDER=z-ai
NEXT_PUBLIC_LLM_MODEL_COMPLEX=glm-4.7
NEXT_PUBLIC_LLM_MODEL_SIMPLE=glm-4.5-air
```

### Google Gemini

文档：https://ai.google.dev/gemini-api/docs/pricing

2.5 Pro 按 prompt 长度分档：≤200k 标准价，>200k 翻倍。所有模型有免费额度。

| 模型 | 输入 $/M | 输出 $/M | Cache hit $/M | 上下文 |
|------|---------|---------|--------------|--------|
| gemini-2.5-pro | $1.25 | $10.0 | $0.125 | 1M |
| gemini-2.5-flash | $0.30 | $2.50 | $0.03 | 1M |
| gemini-2.5-flash-lite | $0.10 | $0.40 | $0.01 | 1M |
| gemini-3-flash (preview) | $0.50 | $3.00 | $0.05 | 1M |
| gemini-3.1-pro (preview) | $2.00 | $12.00 | -- | 1M |

```bash
LLM_PROVIDER=google
LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai
LLM_API_KEY=...
LLM_MODEL_COMPLEX=gemini-2.5-pro
LLM_MODEL_SIMPLE=gemini-2.5-flash
INPUT_COST_PER_M_COMPLEX=1.25
OUTPUT_COST_PER_M_COMPLEX=10.0
INPUT_COST_PER_M_SIMPLE=0.30
OUTPUT_COST_PER_M_SIMPLE=2.50
LLM_CONTEXT_WINDOW=1000000
LLM_MAX_TOKENS=65536
NEXT_PUBLIC_LLM_PROVIDER=google
NEXT_PUBLIC_LLM_MODEL_COMPLEX=gemini-2.5-pro
NEXT_PUBLIC_LLM_MODEL_SIMPLE=gemini-2.5-flash
```

### Mistral AI

文档：https://mistral.ai/pricing

| 模型 | 输入 $/M | 输出 $/M | 上下文 |
|------|---------|---------|--------|
| mistral-large-3 | $2.0 | $6.0 | 128k |
| mistral-medium-3 | $1.0 | $3.0 | 128k |
| mistral-small-3.1 | $0.20 | $0.60 | 128k |
| mistral-nemo | $0.02 | $0.04 | 128k |

```bash
LLM_PROVIDER=mistral
LLM_BASE_URL=https://api.mistral.ai/v1
LLM_API_KEY=...
LLM_MODEL_COMPLEX=mistral-large-3
LLM_MODEL_SIMPLE=mistral-small-3.1
INPUT_COST_PER_M_COMPLEX=2.0
OUTPUT_COST_PER_M_COMPLEX=6.0
INPUT_COST_PER_M_SIMPLE=0.20
OUTPUT_COST_PER_M_SIMPLE=0.60
LLM_CONTEXT_WINDOW=128000
LLM_MAX_TOKENS=32000
NEXT_PUBLIC_LLM_PROVIDER=mistral
NEXT_PUBLIC_LLM_MODEL_COMPLEX=mistral-large-3
NEXT_PUBLIC_LLM_MODEL_SIMPLE=mistral-small-3.1
```

---

## 计费原理

### Token 数：估算而非真实值

OpenClaw hook 事件**不包含真实 token 数**（hook payload 中无 `usage` / `prompt_tokens` / `completion_tokens` 字段，这是平台限制）。当前系统用工具调用参数的字符长度粗估：

```
inputTokens  ≈ JSON.stringify(params).length / 4
outputTokens ≈ JSON.stringify(params).length / 8
```

**实际误差可达 5-20 倍**，因为：
- 只统计了工具调用参数的字符长度，完全忽略对话历史和 system prompt 的 token 消耗
- output 固定按 input 的一半算，没有依据
- 中文内容会低估（中文字符占更多 token）

Dashboard 上显示的 token 数和费用是量级参考，不能用来跟供应商账单对账。

### 双轨计价

每次工具调用时，根据 `sessionId` 判断模型 tier，累积到对应计数器：

```
sessionId === "main"   →  simple  →  INPUT_COST_PER_M_SIMPLE / OUTPUT_COST_PER_M_SIMPLE
sessionId !== "main"   →  complex →  INPUT_COST_PER_M_COMPLEX / OUTPUT_COST_PER_M_COMPLEX
```

`agent_end` 事件触发时，分两条 metrics 记录上报至 dashboard：

| channel | model | 计价变量 |
|---------|-------|---------|
| `orchestrator` | `LLM_PROVIDER/LLM_MODEL_SIMPLE` | `*_SIMPLE` |
| `subagent` | `LLM_PROVIDER/LLM_MODEL_COMPLEX` | `*_COMPLEX` |

### 计价变量优先级

```
INPUT_COST_PER_M_COMPLEX    →  未设置时读 INPUT_COST_PER_M   →  未设置时用 3.0
OUTPUT_COST_PER_M_COMPLEX   →  未设置时读 OUTPUT_COST_PER_M  →  未设置时用 15.0
```

Simple 模型同理。

### 改进方向

当前估算方案是 OpenClaw 平台限制下的权宜之计。已知可行的改进路径：

1. **Session JSONL 解析**：OpenClaw 在 `~/.openclaw/agents/<id>/sessions/*.jsonl` 中存储对话记录，启用 `includeTranscriptUsage` 后每个 turn 包含真实 token 数。可在 heartbeat 结束后轮询解析。
2. **供应商 Admin API**：Anthropic 提供 `/v1/organizations/usage_report/messages` 接口（需 admin key），可查真实用量。OpenAI 也有类似接口。DeepSeek/MiniMax/GLM 暂无。
3. **HTTP 代理拦截**：在 gateway 和供应商之间加代理，从 response header/body 提取真实 usage。架构侵入较大。

---

## 预算熔断

### 工作原理

每次 heartbeat 的 step 0c 调用 `GET /api/agent/health-check`，该接口会：

1. 查询 `metrics_tokens` 表的累计 `sum(cost_usd)`
2. 与预算上限比较（优先读 dashboard settings，次之读 `BUDGET_USD_TOTAL` env var）
3. 超限时在 `directives` 头部插入 `BUDGET EXHAUSTED` 指令

Agent 读到该指令后停止新工作（不 spawn 新实现、不提交 PR）。

### 配置

**方式 A：env var（启动时固定）**

```bash
BUDGET_USD_TOTAL=20.0   # 0 = 不限制
```

**方式 B：Dashboard Settings（运行时可调）**

Settings 页的 `totalBudgetUsd` 字段，修改后下一个 heartbeat 周期立即生效，无需重启。

优先级：Dashboard settings > `BUDGET_USD_TOTAL` env var > 0（不限制）。

### 恢复

在 Dashboard Settings 页提高 `totalBudgetUsd`，下一次 heartbeat 会重新评估，自动恢复工作。

### Health-check 响应格式

```json
{
  "budget": {
    "totalCostUsd": 18.42,
    "totalBudgetUsd": 20.0,
    "remainingUsd": 1.58,
    "exhausted": false
  },
  "directives": []
}
```

`exhausted: true` 时 directives 会包含：

```
BUDGET EXHAUSTED: Spent $20.01 of $20.00 total budget.
STOP all new work immediately — do NOT spawn new implementations or submit PRs.
To resume: raise totalBudgetUsd in dashboard Settings or increase BUDGET_USD_TOTAL env var and restart.
```

### 注意事项

- 熔断基于估算成本，实际账单可能有偏差（见上方计费原理）
- `totalBudgetUsd = 0` 表示不限制，不会触发熔断
- `metrics_tokens` 表有 30 天数据保留策略，超期数据会被清理，清理后累计值会重置

---

## 每模型 Token 熔断

与美元总预算并行的另一道闸门：按**模型**配置 token 上限，超限即停止使用该模型。

### 工作原理

健康检查同一接口聚合 `metrics_tokens` 表中每个模型的 `sum(input_tokens + output_tokens)`，按 **bare model name**（model 路径的最后一段，小写）归并跨供应商的用量。任何 model 的累计值 ≥ 配置上限即视为超支：

1. `directives` 顶部追加 `MODEL TOKEN BUDGET EXHAUSTED: <model> used X/Y tokens. STOP using this model across ALL providers ...`
2. 响应体新增 `modelBudgets` 字段（`exhausted` 数组、`usage` 映射、`caps` 映射）
3. Dashboard 全局横幅（`ModelBudgetBanner`）轮询 health-check，检测到 `modelBudgets.exhausted` 非空即在所有页面顶部渲染红色提示

### 配置

**方式 A：env var（启动时固定）**

```bash
MODEL_TOKEN_BUDGETS='{"glm-4.6":20000000,"deepseek-chat":50000000}'
```

**方式 B：Dashboard Settings（运行时可调）**

通过 `PUT /api/settings` 更新 `modelTokenBudgets` 字段：

```bash
curl -X PUT http://localhost:3000/api/settings \
  -H 'Content-Type: application/json' \
  -d '{"modelTokenBudgets":{"glm-4.6":20000000}}'
```

API 会自动把 key 归一化为 bare model name（小写、剥前缀）。

优先级：Dashboard settings > `MODEL_TOKEN_BUDGETS` env var > `{}`（不限制）。

### Bare-name 匹配规则

| 写入的 model 字段 | 归一化后 |
|------------------|---------|
| `z-ai/glm-4.6` | `glm-4.6` |
| `openrouter/glm-4.6` | `glm-4.6` |
| `openrouter/anthropic/claude-opus-4-6` | `claude-opus-4-6` |
| `GLM-4.6` | `glm-4.6` |
| `glm-4.6` | `glm-4.6` |

配置 key 同样会经过此归一化，因此用户可以随便写大小写或带不带前缀。

### Health-check 响应格式（新增字段）

```json
{
  "modelBudgets": {
    "exhausted": [
      { "model": "glm-4.6", "used": 20300000, "cap": 20000000 }
    ],
    "usage": { "glm-4.6": 20300000, "claude-opus-4-6": 1200000 },
    "caps":  { "glm-4.6": 20000000 }
  }
}
```

### 恢复

提高 `modelTokenBudgets["<model>"]` 的值（dashboard settings 或 env var），下一次 health-check 即可撤销 directive，banner 消失，agent 自动恢复使用该模型。
