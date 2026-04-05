# ClawOSS 重构总文档

本文档是当前唯一保留的重构总文档，合并了原 `REFACTOR-PLAN.md`、`FINAL-ACCEPTANCE.md`、`.debug` 的有效信息。

## 1. 最终结论

2026-04-03 最终验收结果：

- 规格一致性：通过
- 静态配置：通过
- 确定性脚本测试：通过
- 全量回归：通过
- heartbeat 控制权切换：通过
- run-cycle 真实冒烟：通过
- 中断恢复：通过

最终结论：

- 正式版已完成

## 2. 重构目标

本次重构的目标，是把 ClawOSS 从旧的 heartbeat/多子代理常驻编排，收敛成一个更稳定、可验收、可恢复的外部主循环架构。

必须成立的核心目标：

- 控制入口收敛为 `scripts/run-cycle.sh`
- OpenClaw 作为受控执行器，而不是自动 heartbeat 编排器
- 验收逻辑由确定性脚本完成，不信 AI 自报
- 所有关键状态外部化到 `workspace/memory/`
- prompt 由 mission 驱动，而不是写死流程
- 新架构在本地测试、隔离集成测试、真实环境冒烟、真实恢复下都成立

## 3. 重构规范摘要

### 3.1 硬约束

- 不修改 `.env`
- 不改 OpenClaw 内部代码
- 直接在 `/home/ubuntu/projects/codex/ClawOSS` 上重构
- 复用已有脚本资产和 dashboard
- dashboard 与主循环并行存在，不作为主循环的一部分

### 3.2 核心架构

```
config/mission.json
    ↓
scripts/run-cycle.sh
    ↓
openclaw agent
    ↓
workspace/memory/
    ↓
scripts/verify-result.sh
```

### 3.3 关键原则

- 系统只有一个主控制入口：`scripts/run-cycle.sh`
- AI 负责执行，确定性脚本负责验收
- 验收必须读真实 git / GitHub / 文件系统状态
- 生命周期状态必须持久化到 `workspace/memory/`
- mission 定义 work units、约束、gates，主循环不写死任务领域逻辑
- 主循环重启后必须从磁盘状态恢复，而不是依赖旧 session

### 3.4 生命周期状态机

```
idle → task_selected → executing → ready_for_submit → submitted → pr_open → done
                                                                      ↓
                                                                 awaiting_followup → pr_open

任何状态 → failed → idle
done → idle
```

状态语义：

- `idle`：无 active task
- `task_selected`：已选定任务
- `executing`：实现中
- `ready_for_submit`：待提交
- `submitted`：已提交待确认 PR
- `pr_open`：PR 已存在并进入等待期
- `awaiting_followup`：需要回应 review
- `done`：工作流完成
- `failed`：工作流失败

### 3.5 主循环职责

- 维护生命周期状态
- 读取 `mission.json`
- 选择 work unit
- 调用 `build-prompt.sh`
- 调用 `openclaw agent`
- 在状态迁移前调用 `verify-result.sh`
- 记录失败、完成、ledger、恢复

### 3.6 AI 职责

- 发现候选任务
- 选择任务
- 理解 issue 和代码
- 实现修改
- 执行测试
- 创建 PR
- 按 output contract 写入结构化文件

AI 不负责：

- 最终任务是否完成的判断
- gate 是否放行
- follow-up 是否进入

### 3.7 Work Unit 调度优先级

`idle` 下固定优先级：

1. `reflect`
2. `select`
3. `discover`

### 3.8 Gate 原则

关键 gate 必须读真实系统状态：

- `task_admission`：issue open、去重、失败窗口、repo health
- `pre_submit`：真实 git diff、禁止路径、分支名
- `post_submit`：PR 真实存在且 open，ledger 条目存在
- `pr_resolution`：PR merged/closed
- `followup_needed`：PR 是否有新 review

## 4. 当前实现范围

本次重构的核心实现对象包括：

- [config/mission.json](/home/ubuntu/projects/codex/ClawOSS/config/mission.json)
- [scripts/run-cycle.sh](/home/ubuntu/projects/codex/ClawOSS/scripts/run-cycle.sh)
- [scripts/build-prompt.sh](/home/ubuntu/projects/codex/ClawOSS/scripts/build-prompt.sh)
- [scripts/verify-result.sh](/home/ubuntu/projects/codex/ClawOSS/scripts/verify-result.sh)
- [scripts/init-workspace-state.sh](/home/ubuntu/projects/codex/ClawOSS/scripts/init-workspace-state.sh)
- [config/openclaw.json](/home/ubuntu/projects/codex/ClawOSS/config/openclaw.json)
- [workspace/AGENTS.md](/home/ubuntu/projects/codex/ClawOSS/workspace/AGENTS.md)
- [workspace/HEARTBEAT.md](/home/ubuntu/projects/codex/ClawOSS/workspace/HEARTBEAT.md)

## 5. 验收顺序

最终验收按以下顺序执行：

### Step 1: 规格一致性检查

重点确认：

- `run-cycle.sh` 是唯一主控制入口
- `verify-result.sh` 使用真实 git/gh/文件系统状态做 gate
- `mission.json` 定义 work units 和 gates
- `AGENTS.md` / `HEARTBEAT.md` 不再要求旧多子代理编排

### Step 2: 静态配置与文档验收

执行：

```bash
cd /home/ubuntu/projects/codex/ClawOSS
node scripts/validate-config.mjs
bash scripts/tests/test-mission-config.sh
bash scripts/tests/test-refactor-surface.sh
```

### Step 3: 确定性脚本验收

执行：

```bash
cd /home/ubuntu/projects/codex/ClawOSS
bash scripts/tests/test-verify-result.sh
bash scripts/tests/test-build-prompt.sh
bash scripts/tests/test-run-cycle.sh
```

### Step 4: 全量本地回归

执行：

```bash
cd /home/ubuntu/projects/codex/ClawOSS
bash scripts/tests/run-all-tests.sh
```

### Step 5: 真实环境控制权验收

执行：

```bash
cd /home/ubuntu/projects/codex/ClawOSS
openclaw system heartbeat disable
```

### Step 6: 真实环境单轮冒烟

执行：

```bash
cd /home/ubuntu/projects/codex/ClawOSS
bash scripts/init-workspace-state.sh
RUN_CYCLE_ONCE=1 bash scripts/run-cycle.sh
cat workspace/memory/lifecycle-state.json
```

### Step 7: 真实环境恢复验收

目标：

- 验证中断后可从 `workspace/memory/lifecycle-state.json` 恢复
- 验证 session 可轮换，但状态推进依赖磁盘文件继续

## 6. 本次最终验收实际结果

### 6.1 本地测试结果

以下命令已通过：

- `node scripts/validate-config.mjs`
- `bash scripts/tests/test-mission-config.sh`
- `bash scripts/tests/test-refactor-surface.sh`
- `bash scripts/tests/test-verify-result.sh`
- `bash scripts/tests/test-build-prompt.sh`
- `bash scripts/tests/test-run-cycle.sh`
- `bash scripts/tests/run-all-tests.sh`

全量回归结果：

- `29 passed, 0 failed`

### 6.2 真实环境结果

已通过：

- `openclaw system heartbeat disable`
  结果：`{"ok": true, "enabled": false}`

- 真实 `RUN_CYCLE_ONCE=1 bash scripts/run-cycle.sh`
  结果：成功落盘并产出非空 `workspace/memory/candidates.json`

- 真实恢复验收
  结果：已验证主循环会基于磁盘状态恢复，并轮换 `session_id`

### 6.3 验收中发现并修复的问题

验收过程中发现的真实阻塞点：

- `scripts/run-cycle.sh` 原先未自动加载项目 `.env`
- 导致真实 `openclaw agent` 调用拿不到 `GITHUB_TOKEN` 和 `GITHUB_USERNAME`
- 本地测试未覆盖这一点，因此真实环境首次冒烟暴露了问题

修复：

- [`scripts/run-cycle.sh`](/home/ubuntu/projects/codex/ClawOSS/scripts/run-cycle.sh) 已增加项目 `.env` 自动加载逻辑
- [`scripts/tests/test-run-cycle.sh`](/home/ubuntu/projects/codex/ClawOSS/scripts/tests/test-run-cycle.sh) 已补充回归测试，确保 `.env` 会传递给 `openclaw agent`

修复后结果：

- 重跑 `bash scripts/tests/run-all-tests.sh`
- 结果仍为 `29 passed, 0 failed`
- 真实 `run-cycle` 冒烟通过
- 真实恢复验收通过

## 7. 通过标准与判定

只有同时满足以下条件，才可判定正式版完成：

1. 本地静态检查通过
2. 新增脚本测试全部通过
3. 全量回归测试通过
4. 真实 `openclaw system heartbeat disable` 成功
5. 真实 `run-cycle.sh` 单轮冒烟通过
6. 中断恢复验收通过

本次结果：

- 以上 6 项均已满足

因此判定：

- ClawOSS 已达成本轮重构目标

## 8. 备注

本次重构最关键的验收点，不是旧功能还能否继续运行，而是以下三件事是否成立：

- 系统控制权是否真正收敛到 `scripts/run-cycle.sh`
- AI 执行结果是否由确定性 gate 验收，而不是自报成功
- 系统是否能够依赖磁盘状态恢复，而不是依赖旧 session 上下文

当前结论是：

- 上述三点都已经成立
