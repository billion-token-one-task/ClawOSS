# Alpha Deployment

## Goal

Provide a simple single-host deployment and upgrade path for an internal ClawOSS alpha.

### 中文

为内部 ClawOSS alpha 提供简单的单机部署与升级路径。

## Recommended Shape

- the host machine runs `openclaw`, `gh`, and the main ClawOSS agent
- docker compose runs the dashboard/api plus `worker` and `reflection` sidecars
- `.env` and `workspace/strategy/current.json` remain the main editable config surfaces

### 中文

- 主机负责运行 `openclaw`、`gh` 和主 ClawOSS agent
- docker compose 负责运行 dashboard/api 以及 `worker`、`reflection` sidecar
- `.env` 与 `workspace/strategy/current.json` 仍是主要可编辑配置面

## First Deploy

```bash
cp .env.example .env
npm run alpha:deploy
```

Flags:

- `--skip-tests` skips the test suite before setup/start
- `--no-backend` disables dockerized sidecars
- `--dry-run` prints the planned actions without executing them

### 中文

```bash
cp .env.example .env
npm run alpha:deploy
```

参数说明：

- `--skip-tests` 跳过 setup/start 之前的测试
- `--no-backend` 不启动 docker sidecar
- `--dry-run` 只输出计划动作，不真正执行

## Upgrade

After pulling new repository contents:

```bash
npm run alpha:upgrade
```

The wrapper:

1. reruns doctor and config validation
2. reruns tests unless skipped
3. refreshes setup
4. rebuilds docker sidecars unless disabled
5. restarts the agent

### 中文

拉取新代码后：

```bash
npm run alpha:upgrade
```

升级包装脚本会：

1. 重新执行 doctor 和配置校验
2. 除非跳过，否则重新执行测试
3. 刷新 setup
4. 除非关闭，否则重建 docker sidecar
5. 重启 agent

## Human Gate for Alpha

The intended alpha operating mode is:

- AI autonomously discovers, triages, implements, and reflects
- strategy proposals remain in `draft`
- humans only intervene on high-risk repository entry, large changes, or strategy promotion

The gate configuration lives in [../config/alpha-gates.json](../config/alpha-gates.json).  
Queued manual decisions are written to [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md).

Manual inspection examples:

```bash
bash scripts/evaluate-alpha-gate.sh pr_submit --repo owner/repo --pr-type docs --diff-lines 18
bash scripts/evaluate-alpha-gate.sh strategy_promotion --strategy-version candidate-v2 --record
```

### 中文

alpha 的预期运行模式是：

- AI 自主完成发现、分诊、实现和反思
- 策略 proposal 保持为 `draft`
- 人只在高风险仓库进入、大改动或策略晋升时介入

门控配置位于 [../config/alpha-gates.json](../config/alpha-gates.json)。  
待人工处理的决策会写入 [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md)。

人工检查示例：

```bash
bash scripts/evaluate-alpha-gate.sh pr_submit --repo owner/repo --pr-type docs --diff-lines 18
bash scripts/evaluate-alpha-gate.sh strategy_promotion --strategy-version candidate-v2 --record
```
