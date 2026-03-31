import { access, copyFile, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { join } from "node:path";
import crypto from "node:crypto";

function parseTimestamp(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

async function fileExists(path) {
  try {
    await access(path, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function readJsonFiles(directory) {
  const files = (await readdir(directory, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => entry.name)
    .sort();

  const records = [];
  for (const file of files) {
    try {
      const payload = JSON.parse(await readFile(join(directory, file), "utf8"));
      records.push(payload);
    } catch (error) {
      console.error(`[reflection] failed to parse ${join(directory, file)}:`, error);
    }
  }
  return records;
}

function summarizeDecisions(decisions) {
  const stageCounts = {};
  let selectedCount = 0;
  let expectedMergeProbSum = 0;
  let expectedMergeProbCount = 0;
  let expectedTokenCostSum = 0;

  for (const decision of decisions) {
    const stage = decision.stage || decision.type || "unknown";
    stageCounts[stage] = (stageCounts[stage] || 0) + 1;
    if (decision.selected === true || decision.selected === 1) {
      selectedCount += 1;
    }
    if (typeof decision.expectedMergeProb === "number") {
      expectedMergeProbSum += decision.expectedMergeProb;
      expectedMergeProbCount += 1;
    }
    if (typeof decision.expectedTokenCost === "number") {
      expectedTokenCostSum += decision.expectedTokenCost;
    }
  }

  return {
    total: decisions.length,
    selected: selectedCount,
    stageCounts,
    avgExpectedMergeProb:
      expectedMergeProbCount > 0 ? Number((expectedMergeProbSum / expectedMergeProbCount).toFixed(3)) : null,
    totalExpectedTokenCost: expectedTokenCostSum,
  };
}

function summarizeOutcomes(outcomes) {
  const counts = {};
  let tokenCostSum = 0;
  let inputTokens = 0;
  let outputTokens = 0;
  const failureCounts = {};

  for (const outcome of outcomes) {
    const status = outcome.outcome || "unknown";
    counts[status] = (counts[status] || 0) + 1;
    if (typeof outcome.tokenCost === "number") tokenCostSum += outcome.tokenCost;
    if (typeof outcome.inputTokens === "number") inputTokens += outcome.inputTokens;
    if (typeof outcome.outputTokens === "number") outputTokens += outcome.outputTokens;
    if (outcome.failureCategory) {
      failureCounts[outcome.failureCategory] = (failureCounts[outcome.failureCategory] || 0) + 1;
    }
  }

  const topFailure = Object.entries(failureCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || null;

  return {
    total: outcomes.length,
    counts,
    tokenCost: Number(tokenCostSum.toFixed(3)),
    inputTokens,
    outputTokens,
    topFailure,
  };
}

function buildInsights(decisionsSummary, outcomesSummary) {
  const insights = [];
  const recommendedChanges = [];

  const merged = outcomesSummary.counts.merged || 0;
  const reviewed = outcomesSummary.counts.reviewed || 0;
  const rejected =
    (outcomesSummary.counts.rejected || 0) +
    (outcomesSummary.counts.failure || 0) +
    (outcomesSummary.counts.abandoned || 0) +
    (outcomesSummary.counts.closed_unreviewed || 0);

  if (decisionsSummary.avgExpectedMergeProb !== null) {
    insights.push({
      type: "merge_expectation",
      pattern: "recent average expected merge probability",
      value: decisionsSummary.avgExpectedMergeProb,
      confidence: 0.55,
    });
  }

  if (rejected > Math.max(merged, reviewed)) {
    insights.push({
      type: "waste_risk",
      pattern: "negative outcomes exceed reviewed-or-merged outcomes in the latest window",
      evidence_count: rejected,
      confidence: 0.68,
    });
    recommendedChanges.push({
      scope: "targeting",
      change: "raise the minimum expected merge probability before high-effort execution",
      rationale: "recent rejected or abandoned attempts outnumber reviewed-or-merged outcomes",
    });
  }

  if (outcomesSummary.topFailure) {
    insights.push({
      type: "top_failure_category",
      pattern: outcomesSummary.topFailure,
      confidence: 0.6,
    });
  }

  if ((decisionsSummary.stageCounts.queue_pick || 0) > 0 && merged === 0 && reviewed === 0) {
    recommendedChanges.push({
      scope: "followup",
      change: "prefer smaller or previously trusted tasks until review responsiveness improves",
      rationale: "selected work exists but the latest window produced no reviewed or merged outcomes",
    });
  }

  return { insights, recommendedChanges };
}

function stableReflectionId(windowKey, strategyVersion, decisionsSummary, outcomesSummary) {
  const fingerprint = crypto
    .createHash("sha1")
    .update(
      JSON.stringify({
        windowKey,
        strategyVersion,
        decisions: decisionsSummary,
        outcomes: outcomesSummary,
      })
    )
    .digest("hex")
    .slice(0, 12);
  return `reflection-${windowKey}-${fingerprint}`;
}

async function loadCurrentStrategyVersion(workspaceDir) {
  try {
    const current = JSON.parse(await readFile(join(workspaceDir, "strategy/current.json"), "utf8"));
    return typeof current.version === "string" ? current.version : null;
  } catch {
    return null;
  }
}

export async function generateReflection({
  workspaceDir = process.env.WORKSPACE_DIR || "/workspace",
  windowHours = Number(process.env.REFLECTION_WINDOW_HOURS || 24),
  now = new Date(),
} = {}) {
  const decisionsDir = join(workspaceDir, "runtime/processed/decisions");
  const outcomesDir = join(workspaceDir, "runtime/processed/outcomes");
  const dailyDir = join(workspaceDir, "reflections/daily");
  const outboxDir = join(workspaceDir, "reflections/outbox");
  const processedDir = join(workspaceDir, "reflections/processed");

  await mkdir(dailyDir, { recursive: true });
  await mkdir(outboxDir, { recursive: true });
  await mkdir(processedDir, { recursive: true });

  const [decisions, outcomes, strategyVersion] = await Promise.all([
    readJsonFiles(decisionsDir),
    readJsonFiles(outcomesDir),
    loadCurrentStrategyVersion(workspaceDir),
  ]);

  const windowStart = new Date(now.getTime() - windowHours * 60 * 60 * 1000);

  const recentDecisions = decisions.filter((record) => {
    const timestamp = parseTimestamp(record.timestamp);
    return timestamp && timestamp >= windowStart && timestamp <= now;
  });
  const recentOutcomes = outcomes.filter((record) => {
    const timestamp = parseTimestamp(record.timestamp);
    return timestamp && timestamp >= windowStart && timestamp <= now;
  });

  if (recentDecisions.length === 0 && recentOutcomes.length === 0) {
    return null;
  }

  const decisionsSummary = summarizeDecisions(recentDecisions);
  const outcomesSummary = summarizeOutcomes(recentOutcomes);
  const { insights, recommendedChanges } = buildInsights(decisionsSummary, outcomesSummary);

  const windowKey = now.toISOString().slice(0, 10);
  const reflectionId = stableReflectionId(windowKey, strategyVersion, decisionsSummary, outcomesSummary);
  const artifactName = `${reflectionId}.json`;
  const artifactPath = join(dailyDir, artifactName);
  const stagedPath = join(outboxDir, artifactName);
  const processedPath = join(processedDir, artifactName);

  const merged = outcomesSummary.counts.merged || 0;
  const reviewed = outcomesSummary.counts.reviewed || 0;
  const summary =
    `Window ${windowStart.toISOString()} to ${now.toISOString()}: ` +
    `${decisionsSummary.selected}/${decisionsSummary.total} decisions selected, ` +
    `${merged} merged, ${reviewed} reviewed, ${outcomesSummary.total} tracked outcomes.`;

  const reflection = {
    id: reflectionId,
    timestamp: now.toISOString(),
    scope: "daily",
    strategyVersion: strategyVersion || null,
    sourceWindowStart: windowStart.toISOString(),
    sourceWindowEnd: now.toISOString(),
    summary,
    insights,
    recommendedChanges,
    confidence: 0.61,
    applied: false,
    metadata: {
      generatedBy: "reflection_mvp",
      windowHours,
      decisionsSummary,
      outcomesSummary,
    },
  };

  if (!(await fileExists(artifactPath))) {
    await writeFile(artifactPath, `${JSON.stringify(reflection, null, 2)}\n`, "utf8");
  }

  if (!(await fileExists(stagedPath)) && !(await fileExists(processedPath))) {
    await copyFile(artifactPath, stagedPath);
  }

  return { reflection, artifactPath, stagedPath };
}

async function main() {
  const result = await generateReflection();
  if (result) {
    console.log(JSON.stringify(result.reflection));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error("[reflection] failed to generate reflection:", error);
    process.exit(1);
  });
}
