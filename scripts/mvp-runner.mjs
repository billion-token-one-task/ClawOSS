#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const WORKSPACE = process.env.CLAWOSS_WORKSPACE_DIR || join(ROOT, "workspace");
const MEMORY = join(WORKSPACE, "memory");
const REPORTS = join(ROOT, "reports");

loadEnv(join(ROOT, ".env"));

const args = parseArgs(process.argv.slice(2));
const cycleTarget = numberFrom(args.cycles, process.env.CLAWOSS_MVP_CYCLES, 3);
const maxCandidates = numberFrom(args["max-candidates"], process.env.CLAWOSS_MVP_MAX_CANDIDATES, 20);
const dryRun = !args["real-pr"];
const dashboardUrl = stripTrailingSlash(
  process.env.DASHBOARD_URL || "https://clawoss-dashboard.vercel.app"
);
const dashboardKey = process.env.CLAW_API_KEY || "";
const provider = process.env.CLAWOSS_PRIMARY_PROVIDER || process.env.CLAWOSS_PROVIDER_ID || null;
const model =
  process.env.CLAWOSS_PRIMARY_MODEL ||
  (process.env.CLAWOSS_PROVIDER_ID && process.env.CLAWOSS_MODEL_ID
    ? `${process.env.CLAWOSS_PROVIDER_ID}/${process.env.CLAWOSS_MODEL_ID}`
    : process.env.CLAWOSS_MODEL_ID || null);
const modelName = process.env.CLAWOSS_MODEL_NAME || model;
let childEnv = {
  ...process.env,
  GH_TOKEN: process.env.GH_TOKEN || process.env.GITHUB_TOKEN || "",
  CLAWOSS_PROJECT_DIR: process.env.CLAWOSS_PROJECT_DIR || ROOT,
  CLAWOSS_WORKSPACE_DIR: WORKSPACE,
};
const githubUser =
  process.env.CLAW_AGENT_USERNAME ||
  process.env.GITHUB_USERNAME ||
  runText("gh", ["api", "user", "--jq", ".login"], { allowFailure: true }).trim() ||
  "unknown";
const discoveryRepos = parseCsv(
  process.env.CLAWOSS_MVP_DISCOVERY_REPOS ||
    "cli/cli,vitest-dev/vitest,astral-sh/ruff,expressjs/express,pallets/flask,psf/requests"
);

childEnv = {
  ...childEnv,
  CLAW_AGENT_USERNAME: githubUser,
};

const runId = new Date().toISOString().replace(/[:.]/g, "-");
const report = {
  runId,
  startedAt: new Date().toISOString(),
  finishedAt: null,
  mode: dryRun ? "dry-run" : "real-pr",
  cyclesRequested: cycleTarget,
  cyclesCompleted: 0,
  provider,
  model,
  modelName,
  githubAccount: githubUser,
  dashboardUrl,
  dashboardTelemetry: dashboardKey ? "enabled" : "disabled",
  candidatesDiscovered: 0,
  candidatesAfterFilters: 0,
  attemptedTasks: 0,
  createdPrs: 0,
  dryRunStage: null,
  tokenUsage: {
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    costUsd: 0,
  },
  budget: {
    tokenBudgetTotal: numberOrNull(process.env.CLAWOSS_TOKEN_BUDGET_TOTAL),
    costBudgetUsdTotal: numberOrNull(process.env.CLAWOSS_COST_BUDGET_USD_TOTAL),
    latestDashboardBudget: null,
  },
  pauseEvents: [],
  failures: [],
  discovered: [],
  filtered: [],
  attempts: [],
};

const attemptedKeys = new Set();
let dashboardPolicy = { avoidRepos: [], reposWithOpenPRs: [], directives: [] };

main().catch((error) => {
  recordFailure("runner", error?.message || String(error));
  finish(1);
});

async function main() {
  if (!Number.isFinite(cycleTarget) || cycleTarget < 1) {
    throw new Error("--cycles must be a positive number");
  }
  mkdirSync(REPORTS, { recursive: true });

  log("info", `MVP runner started: mode=${report.mode} cycles=${cycleTarget}`);
  await postHeartbeat("alive", "mvp-runner started", { phase: "start" });
  await postMetric("start");

  for (let cycle = 1; cycle <= cycleTarget; cycle += 1) {
    const pauseState = await getPauseState();
    dashboardPolicy = pauseState.policy || dashboardPolicy;
    if (pauseState.budget) report.budget.latestDashboardBudget = pauseState.budget;

    if (pauseState.paused) {
      const event = {
        cycle,
        at: new Date().toISOString(),
        source: pauseState.source,
        reason: pauseState.reason || "dashboard requested pause",
      };
      report.pauseEvents.push(event);
      await postHeartbeat("degraded", `paused: ${event.reason}`, {
        phase: "paused",
        cycle,
        pause: event,
      });
      await postState("paused", null, [], { cycle, pause: event });
      log("warn", `pause active before cycle ${cycle}: ${event.reason}`);
      break;
    }

    report.cyclesCompleted += 1;
    await postHeartbeat("alive", `mvp cycle ${cycle}/${cycleTarget}`, {
      phase: "cycle",
      cycle,
    });

    const candidates = discoverCandidates(maxCandidates);
    report.candidatesDiscovered += candidates.length;
    report.discovered.push(
      ...candidates.map((candidate) => ({ cycle, ...candidateRef(candidate) }))
    );
    log("info", `cycle ${cycle}: discovered ${candidates.length} candidate issue(s)`);

    const filtered = filterCandidates(candidates, cycle);
    report.candidatesAfterFilters += filtered.length;
    report.filtered.push(
      ...filtered.map((candidate) => ({ cycle, ...candidateRef(candidate) }))
    );

    await postState("oss-triage", filtered[0] || null, filtered, {
      phase: "filtered",
      cycle,
      discovered: candidates.length,
      filtered: filtered.length,
      policy: dashboardPolicy,
    });

    if (filtered.length === 0) {
      recordFailure("filter", "no candidates survived MVP safety filters", { cycle });
      continue;
    }

    const attempt = createPrPreflight(filtered[0], cycle);
    attemptedKeys.add(`${attempt.repo}#${attempt.issue}`);
    report.attempts.push(attempt);
    report.attemptedTasks += 1;
    report.dryRunStage = dryRun
      ? "PR title/body/command generated; stopped before gh pr create"
      : report.dryRunStage;

    await postState("oss-submit", filtered[0], filtered, {
      phase: "pr-preflight",
      cycle,
      attempt,
    });
    log("info", `cycle ${cycle}: PR preflight ready for ${attempt.repo}#${attempt.issue}`);

    if (!dryRun) {
      recordFailure(
        "real-pr",
        "real PR mode requires an implementation workspace and verified patch before gh pr create",
        { cycle, repo: attempt.repo, issue: attempt.issue }
      );
      break;
    }
  }

  await postMetric("complete");
  await postHeartbeat("alive", "mvp-runner complete", { phase: "complete" });
  finish(0);
}

function discoverCandidates(limit) {
  if (args.issue) {
    const parsed = parseIssueArg(args.issue);
    if (!parsed) return [];
    const issue = fetchIssue(parsed.repo, parsed.number);
    return [issue || parsed];
  }

  const queries = [
    'is:issue is:open label:"good first issue" archived:false',
    'is:issue is:open label:"help wanted" archived:false',
    'is:issue is:open label:bug archived:false',
    'is:issue is:open label:documentation archived:false',
    'is:issue is:open label:test archived:false',
  ];

  const seen = new Set();
  const candidates = [];
  for (const query of queries) {
    const perQuery = Math.max(5, Math.ceil(limit / queries.length));
    const out = runText(
      "gh",
      [
        "search",
        "issues",
        query,
        "--limit",
        String(perQuery),
        "--json",
        "repository,number,title,url,labels,createdAt,updatedAt",
      ],
      { allowFailure: true }
    );
    for (const item of parseJson(out, [])) {
      const repo = item.repository?.nameWithOwner || item.repository?.fullName;
      if (!repo || !item.number) continue;
      const key = `${repo}#${item.number}`;
      if (seen.has(key)) continue;
      seen.add(key);
      candidates.push({
        repo,
        number: item.number,
        title: item.title || "",
        url: item.url || `https://github.com/${repo}/issues/${item.number}`,
        labels: (item.labels || []).map((label) => label.name || label).filter(Boolean),
        createdAt: item.createdAt || null,
        updatedAt: item.updatedAt || null,
      });
      if (candidates.length >= limit) return candidates;
    }
  }

  if (candidates.length === 0) {
    return discoverCandidatesFromRepos(limit);
  }

  return candidates;
}

function discoverCandidatesFromRepos(limit) {
  const seen = new Set();
  const candidates = [];
  const perRepo = Math.max(8, Math.ceil(limit * 1.5));

  for (const repo of discoveryRepos) {
    const out = runText(
      "gh",
      [
        "issue",
        "list",
        "--repo",
        repo,
        "--state",
        "open",
        "--limit",
        String(perRepo),
        "--json",
        "number,title,url,labels,createdAt,updatedAt",
      ],
      { allowFailure: true }
    );

    for (const item of parseJson(out, [])) {
      const candidate = {
        repo,
        number: item.number,
        title: item.title || "",
        url: item.url || `https://github.com/${repo}/issues/${item.number}`,
        labels: (item.labels || []).map((label) => label.name || label).filter(Boolean),
        createdAt: item.createdAt || null,
        updatedAt: item.updatedAt || null,
      };
      if (!isRepoScopedDiscoveryCandidate(candidate)) continue;
      const key = `${candidate.repo}#${candidate.number}`;
      if (seen.has(key)) continue;
      seen.add(key);
      candidates.push(candidate);
      if (candidates.length >= limit) return candidates;
    }
  }

  return candidates;
}

function fetchIssue(repo, number) {
  const out = runText(
    "gh",
    [
      "api",
      `repos/${repo}/issues/${number}`,
      "--jq",
      "{repo:\"" + repo + "\",number:.number,title:.title,url:.html_url,labels:[.labels[].name]}",
    ],
    { allowFailure: true }
  );
  const parsed = parseJson(out, null);
  if (!parsed || !parsed.number) return null;
  return {
    repo,
    number: parsed.number,
    title: parsed.title || "",
    url: parsed.url || `https://github.com/${repo}/issues/${number}`,
    labels: parsed.labels || [],
  };
}

function filterCandidates(candidates, cycle) {
  const ledger = existsSync(join(MEMORY, "pr-ledger.md"))
    ? readFileSync(join(MEMORY, "pr-ledger.md"), "utf8")
    : "";
  const filtered = [];
  for (const candidate of candidates) {
    const reason = rejectCandidate(candidate, ledger);
    if (reason) {
      recordFailure("filter", reason, { cycle, ...candidateRef(candidate) });
      continue;
    }
    filtered.push(candidate);
  }
  return filtered;
}

function rejectCandidate(candidate, ledger) {
  const key = `${candidate.repo}#${candidate.number}`;
  if (!candidate.repo || !candidate.repo.includes("/")) return "invalid repository name";
  if (attemptedKeys.has(key)) return "duplicate: already attempted in this MVP run";
  if (ledger.includes(candidate.url) || ledger.includes(key)) {
    return "duplicate: issue already appears in pr-ledger";
  }
  if (dashboardPolicy.avoidRepos?.includes(candidate.repo)) {
    return "dashboard avoidRepos policy";
  }

  const title = (candidate.title || "").toLowerCase();
  if (/\b(add|extend|enable|improve|enhance|feature|request|implement|support|introduce|create|propose|migrate|upgrade|refactor|redesign|optimize|allow|provide)\b/.test(title)) {
    return "title suggests feature/refactor scope";
  }

  const labelText = (candidate.labels || []).join(" ").toLowerCase();
  if (/\b(enhancement|feature|feature-request|improvement|refactor|discussion|question|proposal|rfc|design|meta|chore|performance|optimization)\b/.test(labelText)) {
    return "labels indicate non-MVP-safe scope";
  }

  const block = runJson("bash", [join(ROOT, "scripts/check-blocklist.sh"), candidate.repo]);
  if (block?.blocked) return `blocklisted: ${block.reason || "repo blocked"}`;

  const contributing = runJson("bash", [join(ROOT, "scripts/check-contributing-guide.sh"), candidate.repo]);
  if (contributing?.anti_bot) return "contribution guide rejects bot/AI submissions";
  if (contributing?.has_cla && contributing?.cla_type !== "dco") {
    return `CLA required: ${contributing.cla_type || "unknown"}`;
  }

  const supersession = runJson("bash", [
    join(ROOT, "scripts/check-supersession.sh"),
    candidate.repo,
    String(candidate.number),
  ]);
  if (supersession?.superseded) {
    return `superseded: ${supersession.reason || "already claimed"}`;
  }

  const fixed = runJson("bash", [
    join(ROOT, "scripts/check-already-fixed.sh"),
    candidate.repo,
    String(candidate.number),
  ]);
  if (fixed?.fixed) return `already fixed: ${fixed.reason || "upstream resolved"}`;

  const openByUser = runText(
    "gh",
    [
      "search",
      "prs",
      "--author",
      githubUser,
      "--repo",
      candidate.repo,
      "--state",
      "open",
      "--json",
      "number",
      "--jq",
      "length",
    ],
    { allowFailure: true }
  ).trim();
  if (Number(openByUser) > 0) {
    return `duplicate risk: ${githubUser} already has an open PR in ${candidate.repo}`;
  }

  return null;
}

function createPrPreflight(candidate, cycle) {
  const branch = `clawoss-${candidate.repo.replace("/", "-")}-${candidate.number}`;
  const titlePrefix = inferTitlePrefix(candidate);
  const prTitle = `${titlePrefix}: ${candidate.title}`.slice(0, 120);
  const prBody = [
    `Fixes ${candidate.url}`,
    "",
    "Summary:",
    "- prepared a scoped ClawOSS MVP dry-run contribution plan for the selected issue",
    "- completed duplicate, CLA, already-fixed, blocklist, and dashboard avoidRepos checks",
    "",
    "Verification:",
    "- ClawOSS MVP dry-run preflight completed",
    "",
    "Dry-run note:",
    "- stopped before branch push and `gh pr create` because this run is configured as dry-run",
  ].join("\n");

  return {
    cycle,
    repo: candidate.repo,
    issue: candidate.number,
    issueUrl: candidate.url,
    branch,
    prTitle,
    prBody,
    readyToCreatePr: true,
    dryRun,
    stoppedBefore: "gh pr create",
    blockedReason: dryRun
      ? "controlled dry-run mode; no real PR created"
      : "implementation patch must be verified before real PR creation",
    createCommand: `gh pr create --repo ${candidate.repo} --head ${githubUser}:${branch} --title ${JSON.stringify(prTitle)} --body-file <generated-body.md>`,
    at: new Date().toISOString(),
  };
}

function inferTitlePrefix(candidate) {
  const labels = (candidate.labels || []).join(" ").toLowerCase();
  const title = (candidate.title || "").toLowerCase();
  if (labels.includes("documentation") || title.includes("doc")) return "docs";
  if (labels.includes("test") || title.includes("test")) return "test";
  return "fix";
}

function isRepoScopedDiscoveryCandidate(candidate) {
  const title = (candidate.title || "").toLowerCase();
  const labels = (candidate.labels || []).join(" ").toLowerCase();

  if (labels.includes("good first issue")) return true;
  if (labels.includes("help wanted")) return true;
  if (labels.includes("bug")) return true;
  if (labels.includes("documentation")) return true;
  if (labels.includes("docs")) return true;
  if (labels.includes("test")) return true;
  if (labels.includes("tests")) return true;

  return /\b(bug|error|fail|failing|broken|typo|docs?|documentation|test|tests)\b/.test(
    title
  );
}

async function getPauseState() {
  if (!dashboardUrl) return { paused: false, source: "no-dashboard-url" };
  const data = await requestDashboard("/api/agent/health-check", "GET");
  if (!data) return { paused: false, source: "dashboard-unreachable" };
  return {
    paused: Boolean(data.pauseAgent || data.budget?.paused),
    reason: data.pauseReason || data.budget?.pauseReason || null,
    source: "dashboard-health-check",
    budget: data.budget || null,
    policy: {
      avoidRepos: Array.isArray(data.avoidRepos) ? data.avoidRepos : [],
      reposWithOpenPRs: Array.isArray(data.reposWithOpenPRs)
        ? data.reposWithOpenPRs
        : [],
      directives: Array.isArray(data.directives) ? data.directives : [],
    },
  };
}

async function postHeartbeat(status, currentTask, metadata) {
  return requestDashboard("/api/ingest/heartbeat", "POST", {
    status,
    currentTask,
    metadata: {
      source: "mvp-runner",
      runId,
      model,
      modelName,
      provider,
      runtime: runtimeMetadata(),
      ...metadata,
    },
  });
}

async function postState(currentSkill, candidate, queue, metadata) {
  return requestDashboard("/api/ingest/state", "POST", {
    currentSkill,
    currentRepo: candidate?.repo || null,
    currentIssue: candidate ? String(candidate.number) : null,
    workQueue: queue.map(candidateRef),
    pipelineState: metadata,
    activeRepos: [...new Set(queue.map((item) => item.repo))],
    metadata: {
      source: "mvp-runner",
      runId,
      ...metadata,
    },
  });
}

async function postMetric(channel) {
  return requestDashboard("/api/ingest/metrics", "POST", {
    metrics: [
      {
        channel: `mvp-runner:${channel}`,
        provider,
        model,
        inputTokens: 0,
        outputTokens: 0,
        costUsd: 0,
      },
    ],
  });
}

async function postLog(level, message, metadata = {}) {
  return requestDashboard("/api/ingest/logs", "POST", {
    entries: [
      {
        level,
        source: "mvp-runner",
        message,
        metadata: { runId, ...metadata },
      },
    ],
  });
}

async function requestDashboard(path, method, body = null) {
  if (!dashboardKey && method !== "GET") return null;
  try {
    const response = await fetch(`${dashboardUrl}${path}`, {
      method,
      headers: {
        ...(dashboardKey ? { Authorization: `Bearer ${dashboardKey}` } : {}),
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return null;
    return response.json();
  } catch {
    return null;
  }
}

function runtimeMetadata() {
  return {
    primaryModel: model,
    primaryModelName: modelName,
    primaryProvider: provider,
    heartbeatIntervalMinutes: numberFrom(
      process.env.CLAWOSS_HEARTBEAT_INTERVAL_MINUTES,
      null,
      5
    ),
    pricing: {
      inputUsdPerMillionTokens: numberOrNull(process.env.CLAWOSS_MODEL_INPUT_COST),
      outputUsdPerMillionTokens: numberOrNull(process.env.CLAWOSS_MODEL_OUTPUT_COST),
    },
    budget: {
      tokenBudgetTotal: report.budget.tokenBudgetTotal,
      costBudgetUsdTotal: report.budget.costBudgetUsdTotal,
    },
  };
}

function recordFailure(stage, reason, metadata = {}) {
  const entry = {
    stage,
    reason,
    at: new Date().toISOString(),
    ...metadata,
  };
  report.failures.push(entry);
  postLog(stage === "filter" ? "info" : "warn", `${stage}: ${reason}`, entry).catch(() => {});
}

function log(level, message) {
  console.log(`[${new Date().toISOString()}] ${level.toUpperCase()} ${message}`);
  postLog(level, message).catch(() => {});
}

function finish(code) {
  report.finishedAt = new Date().toISOString();
  const jsonPath = join(REPORTS, `mvp-run-${runId}.json`);
  const mdPath = join(REPORTS, `mvp-run-${runId}.md`);
  writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  writeFileSync(mdPath, renderReport(report), "utf8");
  console.log(`MVP report: ${mdPath}`);
  process.exit(code);
}

function renderReport(data) {
  return `# ClawOSS Continuous Run MVP Report

- Run ID: ${data.runId}
- Mode: ${data.mode}
- Runtime: ${data.startedAt} to ${data.finishedAt}
- Heartbeat cycles: ${data.cyclesCompleted}/${data.cyclesRequested}
- Model / provider: ${data.model || "unknown"} / ${data.provider || "unknown"}
- GitHub account: ${data.githubAccount}
- Dashboard telemetry: ${data.dashboardTelemetry}
- Candidate issues discovered: ${data.candidatesDiscovered}
- Candidates after filters: ${data.candidatesAfterFilters}
- Attempted tasks: ${data.attemptedTasks}
- PRs created: ${data.createdPrs}
- Dry-run stage: ${data.dryRunStage || "not reached"}
- Token usage: ${data.tokenUsage.totalTokens} total (${data.tokenUsage.inputTokens} input, ${data.tokenUsage.outputTokens} output)
- Cost usage: $${data.tokenUsage.costUsd.toFixed(6)}
- Pause / budget guardrail triggered: ${data.pauseEvents.length > 0 ? "yes" : "no"}

## Attempts

${data.attempts.length === 0 ? "No PR attempts were made." : data.attempts.map((item) => `- ${item.repo}#${item.issue}: ready=${item.readyToCreatePr}, stoppedBefore=${item.stoppedBefore}, branch=${item.branch}`).join("\n")}

## Failures

${data.failures.length === 0 ? "No failures recorded." : data.failures.map((item) => `- ${item.stage}${item.repo ? ` ${item.repo}#${item.number || item.issue || ""}` : ""}: ${item.reason}`).join("\n")}
`;
}

function runJson(cmd, cmdArgs) {
  const out = runText(cmd, cmdArgs, { allowFailure: true }).trim();
  return out ? parseJson(out, null) : null;
}

function runText(cmd, cmdArgs, { allowFailure = false } = {}) {
  const result = spawnSync(cmd, cmdArgs, {
    cwd: ROOT,
    env: childEnv,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status !== 0 && !allowFailure) {
    throw new Error(`${cmd} ${cmdArgs.join(" ")} failed: ${result.stderr || result.stdout}`);
  }
  return result.stdout || "";
}

function parseIssueArg(value) {
  const match = String(value).match(/^([^/\s]+\/[^#\s]+)#(\d+)$/);
  if (!match) return null;
  return {
    repo: match[1],
    number: Number(match[2]),
    title: `${match[1]} issue ${match[2]}`,
    url: `https://github.com/${match[1]}/issues/${match[2]}`,
    labels: [],
  };
}

function candidateRef(candidate) {
  return {
    repo: candidate.repo,
    number: candidate.number,
    title: candidate.title,
    url: candidate.url,
  };
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith("--")) continue;
    const key = item.slice(2);
    if (index + 1 < argv.length && !argv[index + 1].startsWith("--")) {
      parsed[key] = argv[index + 1];
      index += 1;
    } else {
      parsed[key] = true;
    }
  }
  return parsed;
}

function parseJson(value, fallback) {
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

function parseCsv(value) {
  if (!value) return [];
  return String(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function loadEnv(path) {
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match || process.env[match[1]] != null) continue;
    process.env[match[1]] = match[2].replace(/^['"]|['"]$/g, "");
  }
}

function numberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function numberFrom(value, fallbackValue, defaultValue) {
  return numberOrNull(value) ?? numberOrNull(fallbackValue) ?? defaultValue;
}

function stripTrailingSlash(value) {
  return String(value || "").replace(/\/+$/, "");
}
