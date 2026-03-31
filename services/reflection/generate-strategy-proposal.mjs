import { access, copyFile, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { join } from "node:path";

async function fileExists(path) {
  try {
    await access(path, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function listJsonFiles(directory) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => join(directory, entry.name))
    .sort();
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function applyRecommendedChanges(strategy, reflection) {
  const next = clone(strategy);
  const appliedChanges = [];
  const recommendations = Array.isArray(reflection.recommendedChanges)
    ? reflection.recommendedChanges
    : [];

  for (const recommendation of recommendations) {
    const changeText = String(recommendation.change || "").toLowerCase();
    const rationale = String(recommendation.rationale || "").toLowerCase();

    if (changeText.includes("raise the minimum expected merge probability")) {
      const current = Number(next.budget?.min_expected_merge_prob || 0.3);
      const updated = Number(Math.min(current + 0.05, 0.8).toFixed(2));
      next.budget = {
        ...(next.budget || {}),
        min_expected_merge_prob: updated,
      };
      next.rollout = {
        ...(next.rollout || {}),
        mode: "canary",
        traffic_share: 0.2,
      };
      appliedChanges.push({
        path: "budget.min_expected_merge_prob",
        from: current,
        to: updated,
        rationale: recommendation.rationale || recommendation.change,
      });
      continue;
    }

    if (changeText.includes("prefer smaller") || rationale.includes("review responsiveness improves")) {
      const soft = Number(next.execution?.max_diff_lines_soft || 120);
      const hard = Number(next.execution?.max_diff_lines_hard || 200);
      const nextSoft = Math.max(40, Math.round(soft * 0.85));
      const nextHard = Math.max(nextSoft, Math.round(hard * 0.9));
      next.execution = {
        ...(next.execution || {}),
        max_diff_lines_soft: nextSoft,
        max_diff_lines_hard: nextHard,
      };
      next.targeting = {
        ...(next.targeting || {}),
        prefer_trusted_repos: true,
      };
      next.rollout = {
        ...(next.rollout || {}),
        mode: "canary",
        traffic_share: 0.2,
      };
      appliedChanges.push({
        path: "execution.max_diff_lines_soft",
        from: soft,
        to: nextSoft,
        rationale: recommendation.rationale || recommendation.change,
      });
      appliedChanges.push({
        path: "execution.max_diff_lines_hard",
        from: hard,
        to: nextHard,
        rationale: recommendation.rationale || recommendation.change,
      });
    }
  }

  return { nextStrategy: next, appliedChanges };
}

async function latestReflection(reflectionDir) {
  const files = await listJsonFiles(reflectionDir);
  if (files.length === 0) return null;

  let latest = null;
  for (const file of files) {
    try {
      const payload = await readJson(file);
      const timestamp = new Date(payload.timestamp || payload.sourceWindowEnd || 0).getTime();
      if (!latest || timestamp > latest.timestamp) {
        latest = { timestamp, payload };
      }
    } catch (error) {
      console.error(`[strategy] failed to parse reflection ${file}:`, error);
    }
  }

  return latest?.payload || null;
}

export async function generateStrategyProposal({
  workspaceDir = process.env.WORKSPACE_DIR || "/workspace",
} = {}) {
  const currentPath = join(workspaceDir, "strategy/current.json");
  const reflectionDir = join(workspaceDir, "reflections/daily");
  const historyDir = join(workspaceDir, "strategy/history");
  const outboxDir = join(workspaceDir, "strategy/outbox");
  const processedDir = join(workspaceDir, "strategy/processed");

  await mkdir(historyDir, { recursive: true });
  await mkdir(outboxDir, { recursive: true });
  await mkdir(processedDir, { recursive: true });

  const [currentStrategy, reflection] = await Promise.all([
    readJson(currentPath).catch(() => null),
    latestReflection(reflectionDir),
  ]);

  if (
    !currentStrategy ||
    !reflection ||
    !Array.isArray(reflection.recommendedChanges) ||
    reflection.recommendedChanges.length === 0
  ) {
    return null;
  }

  const reflectionId = String(reflection.id || "unknown-reflection");
  const parentVersion = String(currentStrategy.version || "bootstrap-v1");
  const proposalId = `${parentVersion}-proposal-from-${reflectionId}`;
  const artifactName = `${proposalId}.json`;
  const historyPath = join(historyDir, artifactName);
  const outboxPath = join(outboxDir, artifactName);
  const processedPath = join(processedDir, artifactName);

  if ((await fileExists(historyPath)) || (await fileExists(outboxPath)) || (await fileExists(processedPath))) {
    return null;
  }

  const { nextStrategy, appliedChanges } = applyRecommendedChanges(currentStrategy, reflection);
  if (appliedChanges.length === 0) {
    return null;
  }

  const proposal = {
    id: proposalId,
    createdAt: new Date().toISOString(),
    parentVersion,
    status: "draft",
    authorType: "reflection_agent",
    config: {
      ...nextStrategy,
      version: proposalId,
      status: "draft",
    },
    evaluation: {
      sourceReflectionId: reflectionId,
      rolloutCandidate: {
        mode: "canary",
        trafficShare: 0.2,
      },
      appliedChanges,
    },
    metadata: {
      generatedBy: "strategy_rollout_mvp",
      sourceReflectionId: reflectionId,
      sourceStrategyVersion: parentVersion,
    },
  };

  await writeFile(historyPath, `${JSON.stringify(proposal, null, 2)}\n`, "utf8");
  await copyFile(historyPath, outboxPath);

  return { proposal, historyPath, outboxPath };
}

async function main() {
  const result = await generateStrategyProposal();
  if (result) {
    console.log(JSON.stringify(result.proposal));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error("[strategy] failed to generate proposal:", error);
    process.exit(1);
  });
}
