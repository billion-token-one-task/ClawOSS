export const DASHBOARD_DEMO_SEED_ENABLED =
  process.env.CLAWOSS_DASHBOARD_DEMO_SEED !== "0";

export const DASHBOARD_DEMO_SEED = {
  account: "BillionClaw",
  submitted: 200,
  reviewed: 58,
  merged: 8,
  rejected: 92,
  open: 100,
  mergeRate: 4.0,
  benchmarks: {
    aiAvg: 35,
    copilot: 35,
    devin: 49,
    codex: 64,
  },
  autonomyScore: 46,
  inputTokensToday: 116600,
  outputTokensToday: 3900,
  costToday: 0.04,
  costPerMerge: 0.01,
  tokensPerMerge: 17200,
  avgHoursToReview: 14.2,
} as const;

export function demoNowIso() {
  return new Date().toISOString();
}

export function demoIsoMinutesAgo(minutesAgo: number) {
  return new Date(Date.now() - minutesAgo * 60 * 1000).toISOString();
}

export function getDemoRecentActivity() {
  return [
    {
      id: "demo-activity-1",
      type: "pr_created",
      description:
        "Opened mem0ai/mem0#4374 to add the missing psycopg-pool dependency for the server package.",
      timestamp: "2026-03-17T06:58:51Z",
      metadata: { repo: "mem0ai/mem0", pr: 4374, url: "https://github.com/mem0ai/mem0/pull/4374" },
    },
    {
      id: "demo-activity-2",
      type: "pr_merged",
      description:
        "Merged manaflow-ai/cmux#2053 after cleaning up outdated notifications docs.",
      timestamp: "2026-03-25T03:54:52Z",
      metadata: { repo: "manaflow-ai/cmux", pr: 2053, url: "https://github.com/manaflow-ai/cmux/pull/2053" },
    },
    {
      id: "demo-activity-3",
      type: "pr_merged",
      description:
        "Merged khoj-ai/khoj#1292 to fix PdfToEntries failure handling on invalid PDFs.",
      timestamp: "2026-03-25T12:17:51Z",
      metadata: { repo: "khoj-ai/khoj", pr: 1292, url: "https://github.com/khoj-ai/khoj/pull/1292" },
    },
    {
      id: "demo-activity-4",
      type: "pr_created",
      description:
        "Opened openai/openai-python#3016 to document the reasoning+message pairing constraint in the Responses API.",
      timestamp: "2026-03-26T04:31:16Z",
      metadata: { repo: "openai/openai-python", pr: 3016, url: "https://github.com/openai/openai-python/pull/3016" },
    },
    {
      id: "demo-activity-5",
      type: "pr_created",
      description:
        "Opened lobehub/lobehub#13324 to preserve image resolution when changing aspect ratio.",
      timestamp: "2026-03-26T22:09:33Z",
      metadata: { repo: "lobehub/lobehub", pr: 13324, url: "https://github.com/lobehub/lobehub/pull/13324" },
    },
    {
      id: "demo-activity-6",
      type: "pr_merged",
      description:
        "Merged AstrBotDevs/AstrBot#6584 after removing disabled websearch tools from the active toolset.",
      timestamp: "2026-03-20T17:18:47Z",
      metadata: { repo: "AstrBotDevs/AstrBot", pr: 6584, url: "https://github.com/AstrBotDevs/AstrBot/pull/6584" },
    },
    {
      id: "demo-activity-7",
      type: "task_started",
      description:
        "Triaged recent bugfix candidates across mem0, openai-python, litellm, cmux, and browser-use for merge-friendly submissions.",
      timestamp: demoIsoMinutesAgo(12),
      metadata: { topic: "triage", account: DASHBOARD_DEMO_SEED.account },
    },
    {
      id: "demo-activity-8",
      type: "heartbeat",
      description:
        "Demo snapshot refreshed from BillionClaw's recent GitHub pull request activity.",
      timestamp: demoIsoMinutesAgo(3),
      metadata: { topic: "news", account: DASHBOARD_DEMO_SEED.account },
    },
  ];
}

export function getDemoRecentPRs() {
  return [
    {
      id: "demo-pr-mem0-4374",
      number: 4374,
      title: "fix(server): add missing psycopg-pool dependency",
      repo: "mem0ai/mem0",
      status: "open",
      qualityScore: 88,
      mergeProbability: 72,
      createdAt: new Date("2026-03-17T06:58:51Z"),
    },
    {
      id: "demo-pr-lobehub-13324",
      number: 13324,
      title: "fix(image): preserve resolution when changing aspect ratio",
      repo: "lobehub/lobehub",
      status: "open",
      qualityScore: 84,
      mergeProbability: 66,
      createdAt: new Date("2026-03-26T22:09:33Z"),
    },
    {
      id: "demo-pr-openai-3016",
      number: 3016,
      title: "Fix undocumented reasoning+message pairing constraint in Responses API",
      repo: "openai/openai-python",
      status: "open",
      qualityScore: 91,
      mergeProbability: 78,
      createdAt: new Date("2026-03-26T04:31:16Z"),
    },
    {
      id: "demo-pr-cmux-2053",
      number: 2053,
      title: "docs: remove outdated Claude Code hooks section from notifications",
      repo: "manaflow-ai/cmux",
      status: "merged",
      qualityScore: 82,
      mergeProbability: 81,
      createdAt: new Date("2026-03-24T14:14:38Z"),
    },
    {
      id: "demo-pr-khoj-1292",
      number: 1292,
      title: "Fix UnboundLocalError in PdfToEntries.extract_text when PDF processing fails",
      repo: "khoj-ai/khoj",
      status: "merged",
      qualityScore: 86,
      mergeProbability: 76,
      createdAt: new Date("2026-03-23T23:10:44Z"),
    },
  ] as const;
}

export function getDemoPullRequests() {
  return [
    {
      id: "demo-pr-mem0-4374",
      githubId: 4374,
      repo: "mem0ai/mem0",
      number: 4374,
      title: "fix(server): add missing psycopg-pool dependency",
      body: "Adds the missing psycopg-pool dependency to the server requirements so Docker compose server installs succeed.",
      status: "open" as const,
      qualityScore: 88,
      createdAt: new Date("2026-03-17T06:58:51Z"),
      mergedAt: null,
      closedAt: null,
      additions: 9,
      deletions: 0,
      filesChanged: 1,
      reviewCount: 1,
      prType: "bugfix",
      mergeProbability: 72,
      htmlUrl: "https://github.com/mem0ai/mem0/pull/4374",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-lobehub-13324",
      githubId: 13324,
      repo: "lobehub/lobehub",
      number: 13324,
      title: "fix(image): preserve resolution when changing aspect ratio",
      body: "Keeps image output resolution stable when the requested aspect ratio changes in the editor flow.",
      status: "open" as const,
      qualityScore: 84,
      createdAt: new Date("2026-03-26T22:09:33Z"),
      mergedAt: null,
      closedAt: null,
      additions: 41,
      deletions: 12,
      filesChanged: 3,
      reviewCount: 0,
      prType: "bugfix",
      mergeProbability: 66,
      htmlUrl: "https://github.com/lobehub/lobehub/pull/13324",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-openai-3016",
      githubId: 3016,
      repo: "openai/openai-python",
      number: 3016,
      title: "Fix undocumented reasoning+message pairing constraint in Responses API",
      body: "Documents the reasoning-plus-message pairing requirement so manual conversation state management no longer triggers confusing 400 errors.",
      status: "open" as const,
      qualityScore: 91,
      createdAt: new Date("2026-03-26T04:31:16Z"),
      mergedAt: null,
      closedAt: null,
      additions: 188,
      deletions: 26,
      filesChanged: 6,
      reviewCount: 2,
      prType: "docs",
      mergeProbability: 78,
      htmlUrl: "https://github.com/openai/openai-python/pull/3016",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-litellm-24539",
      githubId: 24539,
      repo: "BerriAI/litellm",
      number: 24539,
      title: "fix(proxy): remove x-api-key when OAuth Authorization header is present",
      body: "Avoids conflicting auth headers in OAuth-backed proxy requests.",
      status: "open" as const,
      qualityScore: 83,
      createdAt: new Date("2026-03-25T00:25:02Z"),
      mergedAt: null,
      closedAt: null,
      additions: 22,
      deletions: 8,
      filesChanged: 2,
      reviewCount: 0,
      prType: "bugfix",
      mergeProbability: 64,
      htmlUrl: "https://github.com/BerriAI/litellm/pull/24539",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-cmux-2053",
      githubId: 2053,
      repo: "manaflow-ai/cmux",
      number: 2053,
      title: "docs: remove outdated Claude Code hooks section from notifications",
      body: "Removes obsolete pre-0.60 notification hook setup from the docs.",
      status: "merged" as const,
      qualityScore: 82,
      createdAt: new Date("2026-03-24T14:14:38Z"),
      mergedAt: new Date("2026-03-25T03:54:52Z"),
      closedAt: new Date("2026-03-25T03:54:52Z"),
      additions: 4,
      deletions: 29,
      filesChanged: 1,
      reviewCount: 1,
      prType: "docs",
      mergeProbability: 81,
      htmlUrl: "https://github.com/manaflow-ai/cmux/pull/2053",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-khoj-1292",
      githubId: 1292,
      repo: "khoj-ai/khoj",
      number: 1292,
      title: "Fix UnboundLocalError in PdfToEntries.extract_text when PDF processing fails",
      body: "Initializes the page accumulator before the try block so invalid PDFs return cleanly.",
      status: "merged" as const,
      qualityScore: 86,
      createdAt: new Date("2026-03-23T23:10:44Z"),
      mergedAt: new Date("2026-03-25T12:17:51Z"),
      closedAt: new Date("2026-03-25T12:17:51Z"),
      additions: 5,
      deletions: 1,
      filesChanged: 1,
      reviewCount: 1,
      prType: "bugfix",
      mergeProbability: 76,
      htmlUrl: "https://github.com/khoj-ai/khoj/pull/1292",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-astrbot-6584",
      githubId: 6584,
      repo: "AstrBotDevs/AstrBot",
      number: 6584,
      title: "fix(websearch): prevent disabled websearch tools from being added to the toolset",
      body: "Stops disabled websearch tools from leaking into the active tool registry.",
      status: "merged" as const,
      qualityScore: 85,
      createdAt: new Date("2026-03-18T17:00:03Z"),
      mergedAt: new Date("2026-03-20T17:18:47Z"),
      closedAt: new Date("2026-03-20T17:18:47Z"),
      additions: 17,
      deletions: 6,
      filesChanged: 2,
      reviewCount: 1,
      prType: "bugfix",
      mergeProbability: 74,
      htmlUrl: "https://github.com/AstrBotDevs/AstrBot/pull/6584",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-dioxus-5414",
      githubId: 5414,
      repo: "DioxusLabs/dioxus",
      number: 5414,
      title: "fix(fullstack-server): emit hydration scripts when custom index.html lacks them",
      body: "Attempts to restore hydration script injection for custom fullstack index templates.",
      status: "closed" as const,
      qualityScore: 61,
      createdAt: new Date("2026-03-26T13:16:08Z"),
      mergedAt: null,
      closedAt: new Date("2026-03-26T17:52:12Z"),
      additions: 52,
      deletions: 12,
      filesChanged: 2,
      reviewCount: 0,
      prType: "bugfix",
      mergeProbability: 28,
      htmlUrl: "https://github.com/DioxusLabs/dioxus/pull/5414",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-marimo-8879",
      githubId: 8879,
      repo: "marimo-team/marimo",
      number: 8879,
      title: "fix: support CloudPath subclasses in normalize_path and file_browser",
      body: "Switches CloudPath detection from module-name checks to isinstance so custom providers behave correctly.",
      status: "closed" as const,
      qualityScore: 73,
      createdAt: new Date("2026-03-26T04:46:51Z"),
      mergedAt: null,
      closedAt: new Date("2026-03-30T17:43:31Z"),
      additions: 31,
      deletions: 9,
      filesChanged: 3,
      reviewCount: 0,
      prType: "bugfix",
      mergeProbability: 42,
      htmlUrl: "https://github.com/marimo-team/marimo/pull/8879",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
    {
      id: "demo-pr-browser-use-4412",
      githubId: 4412,
      repo: "browser-use/browser-use",
      number: 4412,
      title: "fix: allow opting out of SignalHandler to prevent host app conflicts",
      body: "Adds a flag to disable internal signal handling for embedded server deployments.",
      status: "closed" as const,
      qualityScore: 69,
      createdAt: new Date("2026-03-18T12:02:53Z"),
      mergedAt: null,
      closedAt: new Date("2026-03-25T20:21:59Z"),
      additions: 27,
      deletions: 5,
      filesChanged: 2,
      reviewCount: 0,
      prType: "bugfix",
      mergeProbability: 39,
      htmlUrl: "https://github.com/browser-use/browser-use/pull/4412",
      bodyVectorId: null,
      metadata: {},
      decisions: null,
    },
  ];
}

export function getDemoPRDetail(id: string) {
  const pr = getDemoPullRequests().find((entry) => entry.id === id);
  if (!pr) return null;

  return {
    ...pr,
    reviews:
      pr.reviewCount > 0
        ? [
            {
              id: `${pr.id}-review-1`,
              reviewer: "maintainer",
              state: pr.status === "merged" ? "approved" as const : "commented" as const,
              body:
                pr.status === "merged"
                  ? "Looks good. Thanks for the focused fix."
                  : "Initial pass completed. Waiting on broader maintainer review.",
              submittedAt: pr.closedAt || pr.createdAt,
            },
          ]
        : [],
    qualityBreakdown: {
      overallScore: pr.qualityScore ?? 0,
      scopeCheck: 82,
      codeQuality: 84,
      testCoverage: 73,
      security: 86,
      antiSlop: 88,
      gitHygiene: 81,
      prTemplate: 79,
    },
  };
}

export function getDemoAgentStatus() {
  return {
    isOnline: true,
    lastHeartbeat: demoNowIso(),
    currentTask: "3 sessions, 3 active, BillionClaw portfolio loaded",
    uptimeSeconds: 6360,
    heartbeatStreak: 12,
  };
}

export function getDemoCurrentTask() {
  return {
    title: "Triaging BillionClaw pull request portfolio for showcase mode",
    status: "coding" as const,
    progress: 68,
  };
}

export function getDemoThroughput() {
  return {
    slotsUsed: 3,
    totalSlots: 10,
    prsToday: 2,
    mergedToday: 0,
    avgSpawnToSubmit: 18,
    idleCycles: 0,
    hourlyPRs: [0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0],
  };
}

export function getDemoSubagentHealth() {
  return {
    alwaysOn: [
      { label: "scout", status: "ACTIVE", contextPct: 21, ageMinutes: 2 },
      { label: "pr-monitor", status: "ACTIVE", contextPct: 18, ageMinutes: 3 },
      { label: "pr-analyst", status: "IDLE", contextPct: 12, ageMinutes: 6 },
    ],
    implSlots: [
      { label: "impl-1", status: "ACTIVE", contextPct: 34, ageMinutes: 9, repo: "mem0ai/mem0", issue: "missing psycopg-pool dependency" },
      { label: "impl-2", status: "ACTIVE", contextPct: 27, ageMinutes: 11, repo: "openai/openai-python", issue: "Responses API reasoning docs" },
      { label: "followup-1", status: "IDLE", contextPct: 14, ageMinutes: 5, repo: "manaflow-ai/cmux", issue: "post-merge docs follow-up" },
      null,
      null,
      null,
      null,
    ],
    totalActive: 6,
    totalSlots: 10,
    lastUpdated: demoNowIso(),
  };
}

export function getDemoConnectionStatus() {
  const nowIso = demoNowIso();
  return {
    connection: {
      state: "connected" as const,
      message: "Demo mode: seeded from BillionClaw pull request activity",
      lastHeartbeat: nowIso,
      heartbeatStatus: "alive",
    },
    pipeline: {
      heartbeats: true,
      metrics: true,
      heartbeatsLastHour: 12,
      errorsLastHour: 0,
      lastMetricAt: nowIso,
    },
    hasAnyData: true,
  };
}

export function getDemoAlerts() {
  return {
    alerts: [
      {
        id: "demo-merge-benchmark",
        severity: "warning" as const,
        title: "Merge rate below benchmark",
        detail: "Recent BillionClaw snapshot is at 4.0% merge rate versus the 35% AI baseline.",
        metric: "merge_rate",
        value: "4.0",
        threshold: "35%",
        timestamp: demoNowIso(),
      },
    ],
    summary: {
      total: 1,
      critical: 0,
      warning: 1,
      info: 0,
    },
  };
}

export function getDemoState() {
  return {
    state: {
      id: "demo-agent-state",
      timestamp: demoNowIso(),
      currentSkill: "parallel-agents",
      currentRepo: "mem0ai/mem0",
      currentIssue: "4374",
      workQueue: [
        {
          priority: "HIGH",
          repo: "mem0ai/mem0",
          issue: "4374",
          title: "Missing psycopg-pool dependency blocks server startup",
          solvabilityScore: 8,
        },
        {
          priority: "MEDIUM",
          repo: "openai/openai-python",
          issue: "3016",
          title: "Document Responses API reasoning/message pairing constraint",
          solvabilityScore: 7,
        },
        {
          priority: "MEDIUM",
          repo: "lobehub/lobehub",
          issue: "13324",
          title: "Preserve output resolution when aspect ratio changes",
          solvabilityScore: 6,
        },
      ],
      pipelineState: {
        activePRs: [
          {
            repo: "mem0ai/mem0",
            number: 4374,
            title: "fix(server): add missing psycopg-pool dependency",
            status: "open",
          },
          {
            repo: "openai/openai-python",
            number: 3016,
            title: "Fix undocumented reasoning+message pairing constraint in Responses API",
            status: "open",
          },
        ],
        statsToday: {
          submitted: 2,
          merged: 0,
          rejected: 0,
          abandoned: 0,
        },
      },
      activeRepos: [
        "mem0ai/mem0",
        "openai/openai-python",
        "lobehub/lobehub",
      ],
      metadata: {
        agent: {
          status: "online",
          uptimeMinutes: 106,
          heartbeatStreak: 12,
        },
        currentTask: "Refreshing BillionClaw PR showcase dataset",
      },
    },
  };
}

export function addDemoSeedCounts(counts: {
  submitted: number;
  reviewed: number;
  merged: number;
  rejected: number;
  open: number;
}) {
  if (!DASHBOARD_DEMO_SEED_ENABLED) {
    return counts;
  }

  return {
    submitted: DASHBOARD_DEMO_SEED.submitted,
    reviewed: DASHBOARD_DEMO_SEED.reviewed,
    merged: DASHBOARD_DEMO_SEED.merged,
    rejected: DASHBOARD_DEMO_SEED.rejected,
    open: DASHBOARD_DEMO_SEED.open,
  };
}

export function addDemoSeedPortfolio(counts: {
  open: number;
  merged: number;
  closed: number;
}) {
  if (!DASHBOARD_DEMO_SEED_ENABLED) {
    return counts;
  }

  return {
    open: DASHBOARD_DEMO_SEED.open,
    merged: DASHBOARD_DEMO_SEED.merged,
    closed: DASHBOARD_DEMO_SEED.rejected,
  };
}
