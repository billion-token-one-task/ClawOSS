import { mkdir, readdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { generateReflection } from "./generate-reflection.mjs";
import { generateStrategyProposal } from "./generate-strategy-proposal.mjs";

const workspaceDir = process.env.WORKSPACE_DIR || "/workspace";
const apiBaseUrl = process.env.API_BASE_URL || "http://api:3000";
const apiKey = process.env.CLAW_API_KEY || "";
const pollMs = Number(process.env.POLL_INTERVAL_MS || 30000);
const runOnce = process.env.RUN_ONCE === "1";
const generateReflections = process.env.GENERATE_REFLECTIONS !== "0";
const generateStrategyProposals = process.env.GENERATE_STRATEGY_PROPOSALS !== "0";
const mockSinkDir = process.env.MOCK_API_SINK_DIR || "";

const channels = [
  {
    inputDir: join(workspaceDir, "reflections/outbox"),
    processedDir: join(workspaceDir, "reflections/processed"),
    endpoint: "/api/ingest/reflection",
  },
  {
    inputDir: join(workspaceDir, "strategy/outbox"),
    processedDir: join(workspaceDir, "strategy/processed"),
    endpoint: "/api/ingest/strategy-version",
  },
];

async function ensureDirs() {
  for (const channel of channels) {
    await mkdir(channel.inputDir, { recursive: true });
    await mkdir(channel.processedDir, { recursive: true });
  }
}

async function postJson(endpoint, payload) {
  if (mockSinkDir) {
    await mkdir(mockSinkDir, { recursive: true });
    const sinkName = endpoint.replaceAll("/", "_").replace(/^_+/, "");
    const sinkPath = join(mockSinkDir, `${Date.now()}-${sinkName}.json`);
    await writeFile(sinkPath, payload, "utf8");
    return true;
  }
  if (!apiKey) return false;

  const response = await fetch(`${apiBaseUrl}${endpoint}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: payload,
  });
  return response.ok;
}

async function processChannel(channel) {
  const files = (await readdir(channel.inputDir)).filter((file) => file.endsWith(".json"));
  for (const file of files) {
    const source = join(channel.inputDir, file);
    try {
      const payload = await readFile(source, "utf8");
      const ok = await postJson(channel.endpoint, payload);
      if (!ok) continue;
      await rename(source, join(channel.processedDir, file));
    } catch (error) {
      console.error(`[reflection] failed to process ${source}:`, error);
    }
  }
}

async function loop() {
  await ensureDirs();
  do {
    if (generateReflections) {
      await generateReflection({ workspaceDir });
    }
    if (generateStrategyProposals) {
      await generateStrategyProposal({ workspaceDir });
    }
    for (const channel of channels) {
      await processChannel(channel);
    }
    if (!runOnce) {
      await new Promise((resolve) => setTimeout(resolve, pollMs));
    }
  } while (!runOnce);
}

loop().catch((error) => {
  console.error("[reflection] fatal error:", error);
  process.exit(1);
});
