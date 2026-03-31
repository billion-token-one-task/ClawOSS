# Reproducibility Guide

## Goal

Get ClawOSS into a predictable local state before attempting a live autonomous run.

### 中文

在尝试真实自治运行前，把 ClawOSS 整理到可预测的本地状态。

## Required

- `openclaw`
- `gh`
- `node`
- `jq`
- `python3`
- one model API key:
  - `MINIMAX_API_KEY` recommended
  - `KIMI_API_KEY` optional fallback
- GitHub auth via `GITHUB_TOKEN` or an existing `gh auth login`

### 中文

- `openclaw`
- `gh`
- `node`
- `jq`
- `python3`
- 一个模型 API key：
  - 推荐 `MINIMAX_API_KEY`
  - 可选回退 `KIMI_API_KEY`
- 通过 `GITHUB_TOKEN` 或已有 `gh auth login` 完成 GitHub 认证

## Recommended Flow

```bash
cp .env.example .env
npm run doctor
npm run validate
npm run test
npm run setup
npm run start
```

### 中文

```bash
cp .env.example .env
npm run doctor
npm run validate
npm run test
npm run setup
npm run start
```

## Notes

- `config/cron-jobs.json` is intentionally empty by default
- the current reproducible mode is heartbeat-driven rather than cron-driven
- `CLAWOSS_ROOT` is auto-detected by scripts and injected during setup and restart
- `scripts/init-workspace-state.sh` bootstraps the expected `workspace/memory/*` files

### 中文

- `config/cron-jobs.json` 默认有意保持为空
- 当前可复现模式是 heartbeat 驱动，而不是 cron 驱动
- `CLAWOSS_ROOT` 会由脚本自动探测，并在 setup/restart 时注入
- `scripts/init-workspace-state.sh` 会初始化预期的 `workspace/memory/*` 文件
