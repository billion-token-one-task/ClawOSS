# First Alpha Launch Checklist

## Goal

Run the first internal alpha on a constrained host with minimal blast radius.

### 中文

在资源受限的主机上，以最小影响范围启动第一版内部 alpha。

## Before Launch

- confirm `.env` is present and filled:
  - `GITHUB_TOKEN`
  - `MINIMAX_API_KEY`
  - `CLAW_API_KEY`
- confirm required tools are installed:
  - `openclaw`
  - `gh`
  - `node`
  - `jq`
  - `python3`
- preview the lifecycle if needed:
  - `bash scripts/deploy-alpha.sh --dry-run --skip-tests --no-backend`
  - `bash scripts/upgrade-alpha.sh --dry-run --skip-tests --no-backend`

### 中文

- 确认 `.env` 已存在并填写：
  - `GITHUB_TOKEN`
  - `MINIMAX_API_KEY`
  - `CLAW_API_KEY`
- 确认必要工具已安装：
  - `openclaw`
  - `gh`
  - `node`
  - `jq`
  - `python3`
- 如有需要，先预览生命周期命令：
  - `bash scripts/deploy-alpha.sh --dry-run --skip-tests --no-backend`
  - `bash scripts/upgrade-alpha.sh --dry-run --skip-tests --no-backend`

## First Launch

1. run:
   ```bash
   npm run alpha:deploy -- --no-backend
   ```
2. check:
   ```bash
   bash scripts/health-check.sh
   ```
3. confirm these files exist:
   - [../workspace/strategy/current.json](../workspace/strategy/current.json)
   - [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md)
   - [../workspace/memory/pr-ledger.md](../workspace/memory/pr-ledger.md)

### 中文

1. 运行：
   ```bash
   npm run alpha:deploy -- --no-backend
   ```
2. 检查：
   ```bash
   bash scripts/health-check.sh
   ```
3. 确认以下文件存在：
   - [../workspace/strategy/current.json](../workspace/strategy/current.json)
   - [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md)
   - [../workspace/memory/pr-ledger.md](../workspace/memory/pr-ledger.md)

## Recommended Low-Risk Start Mode

For the first live run on a tight server:

1. start without docker backend sidecars
2. observe health and logs first
3. only add dockerized `api`, `worker`, and `reflection` after the host runtime is stable

Suggested sequence:

1. `npm run alpha:deploy -- --no-backend`
2. watch health and logs
3. if stable, later run:
   ```bash
   docker compose up -d --build api worker reflection
   ```

### 中文

对于资源紧张服务器的首轮实跑：

1. 先不要启动 docker sidecar
2. 先观察 health 和日志
3. 仅在主机运行稳定后，再添加 `api`、`worker`、`reflection`

建议顺序：

1. `npm run alpha:deploy -- --no-backend`
2. 观察健康状态和日志
3. 若稳定，再执行：
   ```bash
   docker compose up -d --build api worker reflection
   ```

## Manual Review Expectations

During the first alpha cycle, inspect [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md) for:

- bugfix submissions on unfamiliar repos
- large diffs
- high-round follow-up pushes
- strategy promotion requests

### 中文

在第一轮 alpha 周期中，检查 [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md) 中的：

- 陌生仓库上的 bugfix 提交
- 大 diff
- 高轮次 follow-up push
- 策略晋升请求

## Upgrade and Rollback

Upgrade after pulling changes:

```bash
npm run alpha:upgrade -- --no-backend
```

If backend sidecars are enabled:

```bash
npm run alpha:upgrade
```

Rollback sequence for unstable behavior:

1. `docker compose stop api worker reflection`
2. `npm run stop`
3. inspect:
   - [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md)
   - [../workspace/memory/pr-ledger.md](../workspace/memory/pr-ledger.md)
   - `openclaw logs`

### 中文

拉取更新后的升级命令：

```bash
npm run alpha:upgrade -- --no-backend
```

如果启用了 backend sidecar：

```bash
npm run alpha:upgrade
```

行为不稳定时的回滚步骤：

1. `docker compose stop api worker reflection`
2. `npm run stop`
3. 检查：
   - [../workspace/memory/human-review-queue.md](../workspace/memory/human-review-queue.md)
   - [../workspace/memory/pr-ledger.md](../workspace/memory/pr-ledger.md)
   - `openclaw logs`
