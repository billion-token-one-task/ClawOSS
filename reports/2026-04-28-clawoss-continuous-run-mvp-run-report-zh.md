# ClawOSS 连续运行 MVP 运行报告

## 报告口径

- 报告来源：2026-04-28 晚间/凌晨本地 `reports/mvp-run-*.json`、dashboard logs、dashboard health-check、GitHub PR 状态
- 验收类型：真实 PR 证据 + 受控 dry-run 连续运行证据
- 运行结果类型：系统已完成连续运行、issue discovery、候选过滤、PR preflight，并已产出 1 个真实外部 PR 作为闭环证据
- Dashboard：https://yuanbaomao.cyou/

说明：候选过滤原因不是 PR 失败原因。本报告的“失败原因列表”只记录 PR / PR 工作流层面的失败、阻塞或风险；候选过滤结果单独作为安全过滤摘要记录。

## 运行时间 / Heartbeat Cycle

今晚本地 MVP runner 日志共 `14` 次运行：

- 时间范围：`2026-04-27T17:49:56.502Z` 到 `2026-04-28T00:23:52.783Z`
- 合计 heartbeat cycle：`18/22`
- 主验收 dry-run：`2026-04-27T19:22:02.832Z` 到 `2026-04-27T19:23:55.055Z`
- 主验收 dry-run cycle：`3/3`
- budget pause 验证：`2026-04-28T00:23:50.736Z` 到 `2026-04-28T00:23:52.783Z`
- budget pause 验证 cycle：`0/1`，在第 1 个 cycle 前停止

## 使用模型 / Provider

- 模型：`openai/gpt-5.4`
- Provider：`openai`

## 使用 GitHub 账号

- GitHub 账号：`onthebed`

## Issue Discovery / Candidate Filtering

今晚所有本地 MVP run 汇总：

- 发现候选 issue：`29`
- 通过过滤后的候选：`10`
- 尝试任务：`12`
- MVP runner 创建真实 PR：`0`

主验收 dry-run：

- 发现候选 issue：`18`
- 通过过滤后的候选：`3`
- 尝试任务：`2`
- dry-run 尝试候选：
  - `cli/cli#13283`
  - `vitest-dev/vitest#10211`

安全过滤摘要：

- `superseded`：已有 open PR 关联的候选被过滤，例如 `cli/cli#13280`、`vitest-dev/vitest#10204`、`vitest-dev/vitest#10199`、`astral-sh/ruff#24840`
- `duplicate`：同一轮 MVP run 已尝试的候选被过滤，例如 `cli/cli#13283`、`vitest-dev/vitest#10211`
- `no candidates survived MVP safety filters`：部分 cycle 在安全过滤后无剩余候选

这些属于候选过滤结果，不计入 PR 失败原因。

## PR 创建 / Dry-run 阶段

受控 dry-run：

- dry-run 创建 PR 数：`0`
- dry-run 到达阶段：已生成 PR title、PR body、PR create command，并在 `gh pr create` 前停止
- 阻止真实创建 PR 的原因：本轮 dry-run 按受控验收设计停在 `gh pr create` 前一步，避免在测试 budget / pause / filtering 时提交垃圾 PR 或重复 PR

真实 PR 产出证据：

- PR：https://github.com/cloudflare/sandbox-sdk/pull/646
- Issue：https://github.com/cloudflare/sandbox-sdk/issues/627
- 标题：`fix(examples): use published sandbox image aliases`
- 作者：`onthebed`
- 状态：`OPEN`
- 创建时间：`2026-04-27T19:52:17Z`
- 更新时间：`2026-04-27T19:58:41Z`
- Head branch：`clawoss/fix/627-example-docker-tag`
- 变更规模：`15` files，`+17 / -14`
- 当前状态：`mergeable = MERGEABLE`，`reviewDecision = REVIEW_REQUIRED`
- 当前 checks：`policy = SUCCESS`，`ci/gate = FAILURE`，`build/e2e/publish-preview = SKIPPED`

本任务验收口径：

- MVP runner 的受控 dry-run 证明连续运行、发现、过滤和 PR preflight。
- `cloudflare/sandbox-sdk#646` 证明系统实际产出了 1 个真实合规 PR。
- 本报告不声称 `#646` 已合并，也不声称 CI 已全部通过。

## PR 失败原因列表

本节只记录 PR / PR 工作流层面的失败、阻塞或风险，不记录候选过滤原因。

- `cloudflare/sandbox-sdk#646`
  - `ci/gate = FAILURE`
  - `reviewDecision = REVIEW_REQUIRED`
  - 影响：真实 PR 已创建且 mergeable，但尚不能声明 merge-ready，需要 follow-up 或确认 `ci/gate` 是否为策略 / 权限类 gate
- PR follow-up / monitoring 工作流
  - dashboard logs 记录 `pr-monitor-deep` 和 `pr-analyst` respawn 出现 gateway timeout
  - 影响：PR 后续评论处理、深度分析和策略分析可能延迟；不影响本次 MVP runner 的 3-cycle dry-run 证据
- budget guardrail / dashboard pause
  - dashboard logs 多次记录 `PAUSE NOW`，原因包括 token budget exhausted 和手动暂停
  - 影响：系统按设计停止 spawn / comment / submit；这不是绕过失败，而是安全边界生效

未列为 PR 失败的项：

- `superseded`、`duplicate`、`no candidates survived MVP safety filters` 是候选过滤原因，不是 PR 失败原因
- dry-run 停在 `gh pr create` 前一步是受控验收设计，不是 PR 创建失败

## Token / Cost 消耗

Dashboard health-check 快照：

- 快照时间：`2026-04-28T00:51:24.142Z`
- 累计 token 消耗：`89,211,989`
- token budget：`1,000,000,000`
- remaining tokens：`910,788,011`
- token usage：`8.9%`
- 累计 cost：`$0`
- cost budget：`$0`

说明：

- `mvp-runner` 的 dry-run 路径本身不调用实现型子代理，因此单次 dry-run JSON 中模型调用字段为 `0`。
- 本报告采用 dashboard health-check 的累计 budget 快照作为真实 token 消耗来源。
- cost 字段按 dashboard 当前真实返回值记录为 `$0`，未编造成本。

## Pause / Budget Guardrail

今晚本地 MVP run 中共记录 `4` 个 pause 事件：

- `2026-04-27T19:34:48.418Z`：`CLAWOSS_TOKEN_BUDGET_TOTAL=1`，暂停原因 `累计 token 已达到预算上限 (1457707661/1)`
- `2026-04-27T20:04:57.620Z`：dashboard 手动暂停，暂停原因 `已手动暂停`
- `2026-04-28T00:22:23.671Z`：`CLAWOSS_TOKEN_BUDGET_TOTAL=1`，暂停原因 `累计 token 已达到预算上限 (83124982/1)`
- `2026-04-28T00:23:50.736Z`：`CLAWOSS_TOKEN_BUDGET_TOTAL=100`，暂停原因 `累计 token 已达到预算上限 (83424312/100)`

`npm run mvp:verify-budget-pause -- 100` 验证结果：

- `cyclesCompleted = 0`
- `attemptedTasks = 0`
- `dryRunStage = null`
- `pauseEvents.length > 0`
- `budget.tokenBudgetTotal = 100`

结论：

- budget exhausted 时 runner 在 cycle 前停止，没有进入候选过滤、PR preflight、spawn 或提交
- dashboard pause 时 runner 在 cycle 前停止
- `pauseAgent=true` / `budget.paused=true` 优先级高于 `HEARTBEAT.md` 中的 `NEVER idle / ALWAYS work`

## Dashboard 可观测性

Dashboard 验收地址：

- https://yuanbaomao.cyou/

今晚日志确认 dashboard 可观察：

- runtime 状态
- budget 状态
- heartbeat 状态
- PR / attempted work 状态
- directive / pause 日志
- PR 状态列表

## 未完成 / 风险

- 不自动 merge
- 不声称外部 PR `cloudflare/sandbox-sdk#646` 已合并
- 不声称外部 PR `cloudflare/sandbox-sdk#646` CI 已全部通过
- `#646` 的 `ci/gate` failure 需要 follow-up 或确认是否为策略 / 权限类 gate
- PR monitor / analyst gateway timeout 需要后续排查，避免影响真实 PR follow-up
- dry-run token / cost 仍需要进一步升级为更细粒度的模型调用成本统计
