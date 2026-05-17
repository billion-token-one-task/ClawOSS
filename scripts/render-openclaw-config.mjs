#!/usr/bin/env node

import { readFileSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const TEMPLATE_PATH = join(ROOT, "config", "openclaw.json");

const argv = process.argv.slice(2);
const outputFlagIndex = argv.indexOf("--output");
const outputPath = outputFlagIndex >= 0 ? argv[outputFlagIndex + 1] : null;
const printPrimaryModelOnly = argv.includes("--print-primary-model");

function fail(message) {
  console.error(`[ClawOSS配置] ${message}`);
  process.exit(1);
}

function parseNumber(value, fieldName, fallback = null) {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    fail(`${fieldName} 必须是数字，当前值: ${value}`);
  }
  return parsed;
}

function parseBoolean(value, fallback = false) {
  if (value == null || value === "") return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  fail(`布尔值无效: ${value}`);
}

function parseCsv(value) {
  if (!value) return [];
  return String(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseJsonEnv(name) {
  const raw = process.env[name];
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (error) {
    fail(`${name} 不是合法 JSON: ${error.message}`);
  }
}

function substitutePlaceholders(value, replacements) {
  if (typeof value === "string") {
    let next = value;
    for (const [placeholder, replacement] of Object.entries(replacements)) {
      next = next.split(placeholder).join(replacement);
    }
    return next;
  }
  if (Array.isArray(value)) {
    return value.map((item) => substitutePlaceholders(item, replacements));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        substitutePlaceholders(item, replacements),
      ])
    );
  }
  return value;
}

function collectEnvPlaceholders(value, bucket = new Set()) {
  if (typeof value === "string") {
    for (const match of value.matchAll(/\$\{([A-Z0-9_]+)\}/g)) {
      bucket.add(match[1]);
    }
    return bucket;
  }
  if (Array.isArray(value)) {
    value.forEach((item) => collectEnvPlaceholders(item, bucket));
    return bucket;
  }
  if (value && typeof value === "object") {
    Object.values(value).forEach((item) => collectEnvPlaceholders(item, bucket));
  }
  return bucket;
}

function listProviderModels(providers) {
  return Object.entries(providers).flatMap(([providerId, provider]) => {
    const models = Array.isArray(provider?.models) ? provider.models : [];
    return models.map((model) => ({ providerId, model }));
  });
}

function findPrimaryModelDefinition(providers, primaryModel) {
  const [providerId, ...modelParts] = String(primaryModel).split("/");
  const modelId = modelParts.join("/");
  if (!providerId || !modelId) {
    fail(`CLAWOSS_PRIMARY_MODEL 格式必须是 provider/model，当前值: ${primaryModel}`);
  }

  const provider = providers[providerId];
  if (!provider) {
    fail(`找不到主模型 provider: ${providerId}`);
  }

  const model = (provider.models || []).find((item) => item?.id === modelId);
  if (!model) {
    fail(`找不到主模型定义: ${primaryModel}`);
  }

  return { providerId, modelId, provider, model };
}

function buildProvidersFromSimpleEnv() {
  const providerId = process.env.CLAWOSS_PROVIDER_ID || "custom";
  const modelId = process.env.CLAWOSS_MODEL_ID;
  const baseUrl = process.env.CLAWOSS_PROVIDER_BASE_URL;
  const apiFormat =
    process.env.CLAWOSS_PROVIDER_API_FORMAT || "openai-completions";
  const apiKeyEnv = process.env.CLAWOSS_PROVIDER_API_KEY_ENV;
  const apiKeyLiteral = process.env.CLAWOSS_PROVIDER_API_KEY;

  if (!modelId) {
    fail(
      "未配置模型。请设置 CLAWOSS_MODEL_PROVIDERS_JSON，或至少提供 CLAWOSS_MODEL_ID。"
    );
  }
  if (!baseUrl) {
    fail("未配置 CLAWOSS_PROVIDER_BASE_URL。");
  }

  let apiKey = apiKeyLiteral || "";
  if (apiKeyEnv) {
    apiKey = `\${${apiKeyEnv}}`;
  }
  if (!apiKey) {
    fail(
      "未配置模型 API Key。请设置 CLAWOSS_PROVIDER_API_KEY_ENV 或 CLAWOSS_PROVIDER_API_KEY。"
    );
  }

  const modelName = process.env.CLAWOSS_MODEL_NAME || modelId;
  const inputCost = parseNumber(
    process.env.CLAWOSS_MODEL_INPUT_COST,
    "CLAWOSS_MODEL_INPUT_COST",
    0
  );
  const outputCost = parseNumber(
    process.env.CLAWOSS_MODEL_OUTPUT_COST,
    "CLAWOSS_MODEL_OUTPUT_COST",
    0
  );
  const cacheRead = parseNumber(
    process.env.CLAWOSS_MODEL_CACHE_READ_COST,
    "CLAWOSS_MODEL_CACHE_READ_COST",
    0
  );
  const cacheWrite = parseNumber(
    process.env.CLAWOSS_MODEL_CACHE_WRITE_COST,
    "CLAWOSS_MODEL_CACHE_WRITE_COST",
    0
  );

  const model = {
    id: modelId,
    name: modelName,
    reasoning: parseBoolean(process.env.CLAWOSS_MODEL_REASONING, false),
    input: ["text"],
    cost: {
      input: inputCost,
      output: outputCost,
      cacheRead,
      cacheWrite,
    },
    contextWindow: parseNumber(
      process.env.CLAWOSS_MODEL_CONTEXT_WINDOW,
      "CLAWOSS_MODEL_CONTEXT_WINDOW",
      131072
    ),
    maxTokens: parseNumber(
      process.env.CLAWOSS_MODEL_MAX_TOKENS,
      "CLAWOSS_MODEL_MAX_TOKENS",
      16384
    ),
  };

  return {
    providers: {
      [providerId]: {
        baseUrl,
        apiKey,
        api: apiFormat,
        authHeader: parseBoolean(process.env.CLAWOSS_PROVIDER_AUTH_HEADER, true),
        models: [model],
      },
    },
    primaryModel: `${providerId}/${modelId}`,
  };
}

function resolveModelConfig() {
  const providersFromEnv = parseJsonEnv("CLAWOSS_MODEL_PROVIDERS_JSON");
  if (providersFromEnv) {
    if (
      typeof providersFromEnv !== "object" ||
      Array.isArray(providersFromEnv) ||
      Object.keys(providersFromEnv).length === 0
    ) {
      fail("CLAWOSS_MODEL_PROVIDERS_JSON 必须是非空对象。");
    }
    const models = listProviderModels(providersFromEnv);
    if (models.length === 0) {
      fail("CLAWOSS_MODEL_PROVIDERS_JSON 中至少要提供一个 models 条目。");
    }

    return {
      providers: providersFromEnv,
      primaryModel:
        process.env.CLAWOSS_PRIMARY_MODEL ||
        `${models[0].providerId}/${models[0].model.id}`,
    };
  }

  return buildProvidersFromSimpleEnv();
}

function parseHeartbeatMinutes(config) {
  const every = config?.agents?.list?.[0]?.heartbeat?.every || "5m";
  const match = String(every).match(/^(\d+)m$/i);
  return match ? Number(match[1]) : 5;
}

const template = JSON.parse(readFileSync(TEMPLATE_PATH, "utf8"));
const projectDir = ROOT;
const workspaceDir = join(ROOT, "workspace");
const homeDir = process.env.HOME || process.env.USERPROFILE || "";

const config = substitutePlaceholders(template, {
  "__PROJECT_DIR__": projectDir,
  "__WORKSPACE_PATH__": workspaceDir,
  "__HOME_DIR__": homeDir,
});

const heartbeatPrompt = config?.agents?.list?.[0]?.heartbeat?.prompt;
if (
  typeof heartbeatPrompt === "string" &&
  !heartbeatPrompt.includes("SUBAGENT SPAWN COMPATIBILITY:")
) {
  config.agents.list[0].heartbeat.prompt = `${heartbeatPrompt}\n\nSUBAGENT SPAWN COMPATIBILITY: For runtime=subagent, NEVER pass streamTo. Current OpenClaw rejects streamTo for subagent runtime. Use only runtime, mode, label, task, attachments, runTimeoutSeconds, timeoutSeconds, and lightContext.`;
}

const { providers, primaryModel } = resolveModelConfig();
const fallbackModels = parseCsv(process.env.CLAWOSS_FALLBACK_MODELS).filter(
  (model) => model !== primaryModel
);

const heartbeatIntervalMinutes = parseNumber(
  process.env.CLAWOSS_HEARTBEAT_INTERVAL_MINUTES,
  "CLAWOSS_HEARTBEAT_INTERVAL_MINUTES",
  parseHeartbeatMinutes(config)
);

const primaryDefinition = findPrimaryModelDefinition(providers, primaryModel);
const primaryModelName =
  primaryDefinition.model.name || primaryDefinition.model.id || primaryModel;
const inputCostPerMillionTokens =
  parseNumber(
    primaryDefinition.model?.cost?.input,
    "primaryDefinition.model.cost.input",
    0
  ) ?? 0;
const outputCostPerMillionTokens =
  parseNumber(
    primaryDefinition.model?.cost?.output,
    "primaryDefinition.model.cost.output",
    0
  ) ?? 0;

config.agents.defaults.model.primary = primaryModel;
config.agents.defaults.model.fallbacks = fallbackModels;
config.agents.defaults.subagents.model = primaryModel;
config.models.providers = providers;

config.agents.list = (config.agents.list || []).map((agent) => ({
  ...agent,
  model: primaryModel,
  heartbeat: {
    ...agent.heartbeat,
    model: primaryModel,
    every: `${heartbeatIntervalMinutes}m`,
  },
}));

const dashboardUrl =
  process.env.DASHBOARD_URL || "https://clawoss-dashboard.vercel.app";
const normalizedDashboardUrl = dashboardUrl.replace(/\/+$/, "");
const healthCheckUrl = `${normalizedDashboardUrl}/api/agent/health-check`;
const tokenBudgetTotal = parseNumber(
  process.env.CLAWOSS_TOKEN_BUDGET_TOTAL,
  "CLAWOSS_TOKEN_BUDGET_TOTAL",
  null
);
const costBudgetUsdTotal = parseNumber(
  process.env.CLAWOSS_COST_BUDGET_USD_TOTAL,
  "CLAWOSS_COST_BUDGET_USD_TOTAL",
  null
);

config.env = {
  ...(config.env || {}),
  DASHBOARD_URL: normalizedDashboardUrl,
  CLAWOSS_PROJECT_DIR: projectDir,
  CLAWOSS_WORKSPACE_DIR: workspaceDir,
  CLAWOSS_PRIMARY_MODEL: primaryModel,
  CLAWOSS_PRIMARY_MODEL_NAME: primaryModelName,
  CLAWOSS_PRIMARY_PROVIDER: primaryDefinition.providerId,
  CLAWOSS_PRIMARY_INPUT_COST_PER_MTOKENS: String(inputCostPerMillionTokens),
  CLAWOSS_PRIMARY_OUTPUT_COST_PER_MTOKENS: String(outputCostPerMillionTokens),
  CLAWOSS_HEARTBEAT_INTERVAL_MINUTES: String(heartbeatIntervalMinutes),
  CLAWOSS_HEALTHCHECK_URL: healthCheckUrl,
};

if (fallbackModels.length > 0) {
  config.env.CLAWOSS_FALLBACK_MODELS = fallbackModels.join(",");
}
if (tokenBudgetTotal != null) {
  config.env.CLAWOSS_TOKEN_BUDGET_TOTAL = String(tokenBudgetTotal);
}
if (costBudgetUsdTotal != null) {
  config.env.CLAWOSS_COST_BUDGET_USD_TOTAL = String(costBudgetUsdTotal);
}
if (process.env.CLAW_API_KEY) {
  config.env.CLAW_API_KEY = process.env.CLAW_API_KEY;
}
if (process.env.GITHUB_TOKEN) {
  config.env.GITHUB_TOKEN = process.env.GITHUB_TOKEN;
}
if (process.env.GITHUB_USERNAME) {
  config.env.GITHUB_USERNAME = process.env.GITHUB_USERNAME;
  config.env.CLAW_AGENT_USERNAME = process.env.GITHUB_USERNAME;
}
if (process.env.GITHUB_EMAIL) {
  config.env.GITHUB_EMAIL = process.env.GITHUB_EMAIL;
}

for (const envName of collectEnvPlaceholders(config)) {
  if (process.env[envName]) {
    config.env[envName] = process.env[envName];
  }
}

if (printPrimaryModelOnly) {
  process.stdout.write(primaryModel);
  process.exit(0);
}

const output = `${JSON.stringify(config, null, 2)}\n`;

if (outputPath) {
  writeFileSync(outputPath, output, "utf8");
} else {
  process.stdout.write(output);
}
