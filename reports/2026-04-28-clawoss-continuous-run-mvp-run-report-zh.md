# ClawOSS 连续运行 MVP 运行报告

## 验收结论

- 验收类型：真实 PR 证据 + 受控 dry-run 连续运行证据
- 结论：满足“连续运行至少 3 个 heartbeat cycle，并产生可验证 PR 工作流结果”的 MVP 验收口径
- Dashboard：https://yuanbaomao.cyou/
- 关联真实 PR：https://github.com/cloudflare/sandbox-sdk/pull/646
- 关联 issue：https://github.com/cloudflare/sandbox-sdk/issues/627

## 运行时间 / Heartbeat Cycle

- 主 3-cycle dry-run 时间：`2026-04-27T19:22:02.832Z` 到 `2026-04-27T19:23:55.055Z`
- 主 dry-run heartbeat cycle：`3/3`
- budget pause 验证时间：`2026-04-28T00:23:50.735Z`
- budget pause 验证 cycle：`0/1`，在第 1 个 cycle 前停止

## 使用模型 / Provider

- 模型：`openai/gpt-5.4`
- Provider：`openai`

## 使用 GitHub 账号

- GitHub 账号：`onthebed`

## Issue Discovery / Candidate Filtering

- 发现候选 issue：`18`
- 通过过滤后的候选：`3`
- 尝试任务：`2`
- dry-run 尝试候选：
  - `cli/cli#13283`
  - `vitest-dev/vitest#10211`

基础过滤覆盖：

- CLA
- duplicate
- already-fixed
- blocklist
- avoidRepos
- linked PR / supersession

## PR 创建 / Dry-run 阶段

- dry-run 创建 PR 数：`0`
- dry-run 到达阶段：已生成 PR title、PR body、PR create command，并在 `gh pr create` 前停止

真实 PR 产出证据：

- PR：https://github.com/cloudflare/sandbox-sdk/pull/646
- Issue：https://github.com/cloudflare/sandbox-sdk/issues/627
- 标题：`fix(examples): use published sandbox image aliases`
- 作者：`onthebed`
- 状态：`OPEN`
- Head branch：`clawoss/fix/627-example-docker-tag`
- 变更规模：`15` files，`+17 / -14`
- 当前状态：`mergeable = MERGEABLE`，`reviewDecision = REVIEW_REQUIRED`
- 当前风险：`ci/gate = FAILURE`

说明：`#646` 是真实 PR 产出证据；主 dry-run 是连续运行、候选发现、过滤和 PR preflight 的复现证据。报告不声称 `#646` 已合并或 CI 全部通过。

## 失败原因列表

- `superseded`
  - `cli/cli#13280`：已有 open PR 关联
  - `vitest-dev/vitest#10204`：已有 open PR 关联
  - `vitest-dev/vitest#10199`：已有 open PR 关联
  - `astral-sh/ruff#24840`：已有 open PR 关联
- `duplicate`
  - `cli/cli#13283`：同一轮 MVP run 已尝试
  - `vitest-dev/vitest#10211`：同一轮 MVP run 已尝试
- `no candidates survived MVP safety filters`
- 真实 PR `cloudflare/sandbox-sdk#646` 后续风险：
  - `ci/gate` 当前为 failure
  - `reviewDecision` 当前为 review required

## Token / Cost 消耗

Dashboard budget 快照：

- 快照时间：`2026-04-28T00:38:10.986Z`
- 累计 token 消耗：`86,220,330`
- token budget：`1,000,000,000`
- remaining tokens：`913,779,670`
- token usage：`8.6%`
- 累计 cost：`$0`
- cost budget：`$0`

说明：`mvp-runner` 的 dry-run 路径本身不调用实现型子代理，因此单次 dry-run JSON 中模型调用字段为 `0`。本报告使用 dashboard health-check 的累计 budget 快照作为真实 token 消耗来源；cost 字段按 dashboard 当前真实返回值记录为 `$0`。

## Pause / Budget Guardrail

- 是否触发 pause / budget guardrail：是
- 验证命令：`npm run mvp:verify-budget-pause -- 100`
- 临时 token 上限：`100`
- 实际暂停原因：`累计 token 已达到预算上限 (83424312/100)`
- 验证结果：
  - `cyclesCompleted = 0`
  - `attemptedTasks = 0`
  - `dryRunStage = null`
  - `pauseEvents.length > 0`
  - `budget.tokenBudgetTotal = 100`

Dashboard pause 也已验证：

- `agentPaused=true` 时 runner 在 cycle 前停止
- `pauseAgent=true` 优先级高于 `HEARTBEAT.md` 中的 `NEVER idle / ALWAYS work`

## Dashboard 可观测性

Dashboard 验收地址：

- https://yuanbaomao.cyou/

可观察项：

- runtime 状态
- budget 状态
- heartbeat 状态
- PR / attempted work 状态
- 失败原因与日志

## 未完成 / 风险

- 不自动 merge
- 不声称外部 PR `cloudflare/sandbox-sdk#646` 已合并
- 不声称外部 PR `cloudflare/sandbox-sdk#646` CI 已全部通过
- `#646` 的 `ci/gate` failure 需要 follow-up 或确认是否为策略 / 权限类 gate
- dry-run token / cost 仍需要进一步升级为更细粒度的模型调用成本统计
