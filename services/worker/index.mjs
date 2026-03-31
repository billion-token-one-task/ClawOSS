import { mkdir, readdir, readFile, rename } from "node:fs/promises";
import { join } from "node:path";

const workspaceDir = process.env.WORKSPACE_DIR || "/workspace";
const apiBaseUrl = process.env.API_BASE_URL || "http://api:3000";
const apiKey = process.env.CLAW_API_KEY || "";
const pollMs = Number(process.env.POLL_INTERVAL_MS || 10000);
const runOnce = process.env.RUN_ONCE === "1";

const channels = [
  {
    inputDir: join(workspaceDir, "runtime/decisions"),
    processedDir: join(workspaceDir, "runtime/processed/decisions"),
    endpoint: "/api/ingest/decision",
  },
  {
    inputDir: join(workspaceDir, "runtime/outcomes"),
    processedDir: join(workspaceDir, "runtime/processed/outcomes"),
    endpoint: "/api/ingest/execution-outcome",
  },
];

async function ensureDirs() {
  for (const channel of channels) {
    await mkdir(channel.inputDir, { recursive: true });
    await mkdir(channel.processedDir, { recursive: true });
  }
}

async function postJson(endpoint, payload) {
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
      console.error(`[worker] failed to process ${source}:`, error);
    }
  }
}

async function loop() {
  await ensureDirs();
  do {
    for (const channel of channels) {
      await processChannel(channel);
    }
    if (!runOnce) {
      await new Promise((resolve) => setTimeout(resolve, pollMs));
    }
  } while (!runOnce);
}

loop().catch((error) => {
  console.error("[worker] fatal error:", error);
  process.exit(1);
});
