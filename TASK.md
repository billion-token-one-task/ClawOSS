# ClawOSS 修复任务

## 背景
仓库地址：https://github.com/billion-token-one-task/ClawOSS/tree/v6-release
我的 fork：https://github.com/gavinnnma/ClawOSS

项目是一个自主 OSS 贡献 agent，当前代码把 LLM 配置写死了（minimax/MiniMax-M2.7 和 kimi-coding/k2p5），导致不用这两个模型就无法启动。

我的环境：
- LLM: openai/gpt-4o-mini via https://api.tokenrouter.com/v1
- GitHub 账号: gavinnnma
- 部署目标: Railway (Docker 容器) + Vercel (Dashboard)

## 任务：提 4 个 PR 到上游仓库

---

## PR1: feat: make LLM provider configurable via environment variables

### 目标
把所有硬编码的模型名、API key、base URL 改成从环境变量读取。

### 需要修改的文件

**`.env.example`** — 完全重写：
- 删除 KIMI_API_KEY
- 添加以下变量（附注释和多个 provider 示例）：
  LLM_MODEL=openai/gpt-4o-mini
  LLM_BASE_URL=https://api.tokenrouter.com/v1
  LLM_API_KEY=your-key-here
  LLM_CONTEXT_WINDOW=128000
  LLM_MAX_TOKENS=16384
  LLM_INPUT_COST_PER_MILLION=0.15
  LLM_OUTPUT_COST_PER_MILLION=0.60
- 保留 GITHUB_TOKEN, GITHUB_USERNAME, GITHUB_EMAIL, DASHBOARD_URL, CLAW_API_KEY
- 加注释示例块：OpenAI / Anthropic / DeepSeek / OpenRouter / MiniMax / Kimi

**`config/openclaw.json`** — 替换所有硬编码模型配置：
- agents.defaults.model.primary: 改成 "__LLM_MODEL__"
- agents.defaults.model.fallbacks: 改成 ["__LLM_MODEL__"]
- agents.defaults.subagents.model: 改成 "__LLM_MODEL__"
- agents.list[0].model: 改成 "__LLM_MODEL__"
- agents.list[0].heartbeat.model: 改成 "__LLM_MODEL__"
- models.providers: 把 minimax 这个 provider 块改成通用结构：
  {
    "llm": {
      "baseUrl": "__LLM_BASE_URL__",
      "apiKey": "${LLM_API_KEY}",
      "api": "openai-completions",
      "authHeader": true,
      "models": [
        {
          "id": "__LLM_MODEL_ID__",
          "name": "__LLM_MODEL__",
          "reasoning": false,
          "input": ["text"],
          "cost": { "input": "__LLM_INPUT_COST__", "output": "__LLM_OUTPUT_COST__" },
          "contextWindow": "__LLM_CONTEXT_WINDOW__",
          "maxTokens": "__LLM_MAX_TOKENS__"
        }
      ]
    }
  }

**`scripts/setup.sh`** — 修改验证逻辑：
- 删除这段（约第37行）：
  if [ -z "${KIMI_API_KEY:-}" ]; then
      echo "Error: KIMI_API_KEY not set in .env ..."
      exit 1
  fi
- 替换成：
  if [ -z "${LLM_API_KEY:-}" ]; then
      echo "Error: LLM_API_KEY not set in .env"
      exit 1
  fi
  if [ -z "${LLM_MODEL:-}" ]; then
      echo "Error: LLM_MODEL not set in .env"
      exit 1
  fi
  if [ -z "${LLM_BASE_URL:-}" ]; then
      echo "Error: LLM_BASE_URL not set in .env"
      exit 1
  fi
- 在 inject env vars 的 python3 块里，把 KIMI_API_KEY 替换成 LLM_API_KEY，加入 LLM_MODEL / LLM_BASE_URL

**`scripts/start.sh`** — 第24行：
- 把 --model "kimi-coding/k2p5" 改成 --model "${LLM_MODEL:-openai/gpt-4o-mini}"

**`scripts/restart.sh`** — 步骤5 Deploy config：
- 在 sed 命令里增加替换：
  -e "s|__LLM_MODEL__|${LLM_MODEL}|g" \
  -e "s|__LLM_BASE_URL__|${LLM_BASE_URL}|g" \
  -e "s|__LLM_MODEL_ID__|$(echo ${LLM_MODEL} | cut -d'/' -f2)|g" \
  -e "s|__LLM_INPUT_COST__|$(echo "scale=9; ${LLM_INPUT_COST_PER_MILLION:-0.15} / 1000000" | bc)|g" \
  -e "s|__LLM_OUTPUT_COST__|$(echo "scale=9; ${LLM_OUTPUT_COST_PER_MILLION:-0.60} / 1000000" | bc)|g" \
  -e "s|__LLM_CONTEXT_WINDOW__|${LLM_CONTEXT_WINDOW:-128000}|g" \
  -e "s|__LLM_MAX_TOKENS__|${LLM_MAX_TOKENS:-16384}|g"
- python3 的 env_map 里：
  把 'KIMI_API_KEY' 和 'MINIMAX_API_KEY' 替换成：
  'LLM_API_KEY': os.environ.get('_LLM_KEY', ''),
  'LLM_MODEL': os.environ.get('_LLM_MODEL', ''),
  'LLM_BASE_URL': os.environ.get('_LLM_BASE_URL', ''),
- 对应的 shell 变量传入也要改：
  _LLM_KEY="${LLM_API_KEY:-}" \
  _LLM_MODEL="${LLM_MODEL:-}" \
  _LLM_BASE_URL="${LLM_BASE_URL:-}" \
- 最后 Summary echo 改成读 $LLM_MODEL

### 验证方法
```bash
# 检查 openclaw.json 里没有任何 minimax 或 kimi 字符串
grep -r "minimax\|kimi\|MiniMax\|k2p5" config/ scripts/ --include="*.json" --include="*.sh"
# 应该零结果

# 模拟 setup 验证
LLM_API_KEY=test LLM_MODEL=openai/gpt-4o-mini LLM_BASE_URL=https://api.openai.com/v1 bash scripts/setup.sh 2>&1 | grep -E "OK|Error"
```

### PR 信息
- branch: fix/configurable-llm-provider
- title: feat: make LLM provider configurable via environment variables
- body: 说明问题（硬编码导致只能用 MiniMax/Kimi）、改动范围、新的配置方式、支持的 provider 示例

---

## PR2: fix: read LLM model from env in hooks and dashboard-sync

### 需要修改的文件

**`workspace/hooks/dashboard-reporter/handler.ts`**：
- 顶部加（第7行之后）：
  const LLM_MODEL = process.env.LLM_MODEL || "unknown";
  const LLM_PROVIDER = process.env.LLM_BASE_URL
    ? new URL(process.env.LLM_BASE_URL).hostname.split('.')[0]
    : "unknown";
  const INPUT_COST_PER_TOKEN = parseFloat(process.env.LLM_INPUT_COST_PER_MILLION || "0.15") / 1_000_000;
  const OUTPUT_COST_PER_TOKEN = parseFloat(process.env.LLM_OUTPUT_COST_PER_MILLION || "0.60") / 1_000_000;
- 删除原来写死的：
  const INPUT_COST_PER_TOKEN = 0.6 / 1_000_000;
  const OUTPUT_COST_PER_TOKEN = 3.0 / 1_000_000;
- 第171行 model: "kimi-coding/k2p5" → model: LLM_MODEL
- 第550行 model: "kimi-coding/k2p5" → model: LLM_MODEL
- 第570行 provider: "kimi-direct" → provider: LLM_PROVIDER
- 第571行 model: "kimi-coding/k2p5" → model: LLM_MODEL

**`workspace/hooks/dashboard-reporter/post-tool.sh`**：
- 第45行：
  把 model: \"kimi-coding/k2p5\"
  改成 model: \"${LLM_MODEL:-unknown}\"

**`scripts/dashboard-sync.sh`**：
- 第197行：
  把 'model': model or 'kimi-coding/k2p5'
  改成 'model': model or os.environ.get('LLM_MODEL', 'unknown')

### 验证方法
```bash
grep -n "kimi\|k2p5\|kimi-direct" \
  workspace/hooks/dashboard-reporter/handler.ts \
  workspace/hooks/dashboard-reporter/post-tool.sh \
  scripts/dashboard-sync.sh
# 应该零结果
```

### PR 信息
- branch: fix/hooks-env-model
- title: fix: read LLM model from env in hooks and dashboard-sync
- body: 说明这三个文件里残留的硬编码，以及改动方式

---

## PR3: feat: add token budget enforcement and dynamic cost calculation

### 需要修改的文件

**`.env.example`** — 在 PR1 基础上增加（如果 PR1 已合并则直接改，否则在同一文件里加）：TOKEN_BUDGET_USD=20.00
BUDGET_CHECK_INTERVAL=60

**`scripts/dashboard-sync.sh`** — 在主循环 `while true; do` 之后、`CYCLE=$((CYCLE + 1))` 之前加：

```bash
# --- Budget guard ---
if [ -n "${TOKEN_BUDGET_USD:-}" ] && [ "${TOKEN_BUDGET_USD}" != "0" ]; then
  TOTAL_COST=$(curl -s -m 5 \
    -H "Authorization: Bearer $KEY" \
    "$URL/api/metrics/overview" 2>/dev/null | \
    python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('stats',{}).get('totalCostAllTime',0))
except:
    print(0)
" 2>/dev/null || echo "0")

  OVER_BUDGET=$(python3 -c "
try:
    over = float('$TOTAL_COST') >= float('$TOKEN_BUDGET_USD')
    print('yes' if over else 'no')
except:
    print('no')
" 2>/dev/null || echo "no")

  if [ "$OVER_BUDGET" = "yes" ]; then
    log "BUDGET EXCEEDED: spent=\$$TOTAL_COST budget=\$$TOKEN_BUDGET_USD — stopping gateway"
    curl -s -m 5 -X POST "$URL/api/ingest/heartbeat" \
      -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d "{\"status\":\"offline\",\"currentTask\":\"BUDGET EXCEEDED: spent \$$TOTAL_COST of \$$TOKEN_BUDGET_USD\"}" \
      >/dev/null 2>&1
    openclaw gateway stop 2>/dev/null || true
    sleep "${BUDGET_CHECK_INTERVAL:-60}"
    continue
  fi
fi
```

**`dashboard/lib/cost-models.ts`** — 重写 computeTokenCost 和 DEFAULT_MODEL：
```typescript
// 从环境变量动态读取当前模型（Next.js 服务端）
export function getActiveModel(): string {
  return process.env.LLM_MODEL || DEFAULT_MODEL;
}

// 动态计算：优先查已知模型表，找不到则用环境变量费率
export function computeTokenCost(
  inputTokens: number,
  outputTokens: number,
  model?: string
): number {
  const m = model || getActiveModel();
  if (COST_MODELS[m]) {
    const cm = COST_MODELS[m];
    return inputTokens * cm.inputCostPerToken + outputTokens * cm.outputCostPerToken;
  }
  // Fallback: 读环境变量费率
  const inputRate = parseFloat(process.env.LLM_INPUT_COST_PER_MILLION || "0.15") / 1_000_000;
  const outputRate = parseFloat(process.env.LLM_OUTPUT_COST_PER_MILLION || "0.60") / 1_000_000;
  return inputTokens * inputRate + outputTokens * outputRate;
}
```

**`dashboard/app/api/metrics/overview/route.ts`** — 在返回 JSON 里加 budget 字段：
```typescript
// 在 return NextResponse.json({ 里加：
budgetUsd: process.env.TOKEN_BUDGET_USD
  ? parseFloat(process.env.TOKEN_BUDGET_USD)
  : null,
budgetUsedPercent: process.env.TOKEN_BUDGET_USD
  ? Math.round((totalCostAllTime / parseFloat(process.env.TOKEN_BUDGET_USD)) * 100)
  : null,
```

### 验证方法
```bash
# 单元测试：预算检查逻辑
TOKEN_BUDGET_USD=10 TOTAL_COST=15 python3 -c "
over = float('15') >= float('10')
print('PASS: budget exceeded detected' if over else 'FAIL')
"

# 检查 cost-models.ts 没有写死 fallback 模型
grep "kimi\|minimax\|MiniMax" dashboard/lib/cost-models.ts
# 只应该在 COST_MODELS 表里出现，不应该在 DEFAULT_MODEL 或 computeTokenCost 逻辑里
```

### PR 信息
- branch: feat/token-budget
- title: feat: add token budget enforcement and dynamic cost calculation
- body: 说明 TOKEN_BUDGET_USD 的工作原理，超限后的行为（停服务、dashboard 显示 offline + 原因），以及动态费率计算

---

## PR4: feat: add Docker support for Railway/Linux deployment

### 需要新建的文件

**`Dockerfile`**：
```dockerfile
FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    jq \
    python3 \
    python3-pip \
    bash \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install openclaw
RUN npm install -g openclaw

WORKDIR /app
COPY . .
RUN npm install

# Use linux-specific start script
CMD ["bash", "scripts/start-linux.sh"]
```

**`scripts/start-linux.sh`**（新建，替代 restart.sh 里的 macOS launchd 逻辑）：
```bash
#!/usr/bin/env bash
# Linux/Docker 兼容启动脚本 — 替代 restart.sh 的 macOS launchd 部分
set -euo pipefail

echo "=== ClawOSS Linux Start ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="$PROJECT_DIR/workspace"

# 验证必要环境变量
: "${LLM_API_KEY:?LLM_API_KEY is required}"
: "${LLM_MODEL:?LLM_MODEL is required}"
: "${LLM_BASE_URL:?LLM_BASE_URL is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

# Git identity
git config --global user.name "${GITHUB_USERNAME:-gavinnnma}"
git config --global user.email "${GITHUB_EMAIL:-gavinnnma@users.noreply.github.com}"

# GitHub CLI auth
echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true

# Link workspace
mkdir -p "$HOME/.openclaw"
ln -sf "$WORKSPACE_DIR" "$HOME/.openclaw/workspace" 2>/dev/null || true

# Deploy config (用 restart.sh 里相同的 python3 deep-merge 逻辑)
# ... (复制 restart.sh 步骤5的完整逻辑)

# Reset state files
mkdir -p "$WORKSPACE_DIR/memory/repos" "$WORKSPACE_DIR/memory/issues" \
         "$WORKSPACE_DIR/memory/locks" "$WORKSPACE_DIR/memory/subagent-inputs" \
         "$HOME/.openclaw/logs"

# Start gateway (前台运行，适合容器)
echo "[OK] Starting OpenClaw gateway..."
openclaw gateway run &
GATEWAY_PID=$!

sleep 8

# Start dashboard-sync in background
if [ -n "${CLAW_API_KEY:-}" ]; then
  nohup bash "$PROJECT_DIR/scripts/dashboard-sync.sh" \
    > /tmp/dashboard-sync.log 2>&1 &
fi

# Kick agent
openclaw system event \
  --text "ClawOSS Linux start. Execute HEARTBEAT.md steps 0-7. Fill all impl slots. NEVER idle." \
  --mode now 2>/dev/null || true

echo "[OK] ClawOSS running. Gateway PID: $GATEWAY_PID"

# Keep container alive
wait $GATEWAY_PID
```

**`railway.json`**（新建，Railway 部署配置）：
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "DOCKERFILE"
  },
  "deploy": {
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 3
  }
}
```

**`.dockerignore`**（新建）：
node_modules
.env
*.log
workspace/.sync-state
workspace/memory/locks
dashboard/.next
dashboard/node_modules
### 需要修改的文件

**`scripts/restart.sh`** — 步骤6（Update gateway plist PATH）和步骤15（launchd plist）整块用 OS 检测包裹：
```bash
if [[ "$(uname)" == "Darwin" ]]; then
  # ... 原来的 macOS launchd 逻辑 ...
else
  echo "[INFO] Linux detected — skipping launchd setup"
fi
```

**`README.md`** — 加 Railway 部署章节：
```markdown
## Deploy to Railway

1. Fork this repo
2. Create a new Railway project, connect your fork
3. Add environment variables (see .env.example)
4. Railway auto-deploys via Dockerfile
```

### 验证方法
```bash
# 本地 Docker 构建测试
docker build -t clawoss-test .
# 应该能成功构建，不报错

# 检查 start-linux.sh 可执行
chmod +x scripts/start-linux.sh
bash -n scripts/start-linux.sh  # 语法检查
```

### PR 信息
- branch: feat/docker-railway
- title: feat: add Docker support for Railway and Linux deployment
- body: 说明原项目只支持 macOS launchd，新增 Dockerfile 和 start-linux.sh 支持任意 Linux 容器平台（Railway/Render/VPS）

---

## 执行顺序

1. git clone https://github.com/gavinnnma/ClawOSS
2. cd ClawOSS
3. 按顺序创建4个branch，每个branch独立改动