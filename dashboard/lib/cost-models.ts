/**
 * Cost models for different LLM providers.
 * Prices are in USD per million tokens (stored here as per-token for computation).
 *
 * This is a reference registry — actual pricing used by the agent is driven by
 * INPUT_COST_PER_M_COMPLEX / OUTPUT_COST_PER_M_COMPLEX (and _SIMPLE) env vars.
 * Add entries here so the dashboard can display correct costs when the model ID
 * is known from telemetry.
 *
 * Prices last verified: April 2026. Always confirm at the provider's pricing page
 * before committing to a budget.
 */
export interface CostModel {
  name: string;
  provider: string;
  /** USD per token (divide the per-million price by 1_000_000) */
  inputCostPerToken: number;
  outputCostPerToken: number;
  /** Cache-hit input price, if provider supports prompt caching */
  cacheHitCostPerToken?: number;
  contextWindow?: number;
  notes?: string;
}

export const COST_MODELS: Record<string, CostModel> = {

  // ─── Anthropic Claude ──────────────────────────────────────────────────────
  // https://platform.claude.com/docs/en/about-claude/pricing
  // Opus 4.6/4.5 dropped to $5/$25 (from $15/$75). 1M context at standard rate.
  "anthropic/claude-opus-4-6": {
    name: "Claude Opus 4.6",
    provider: "anthropic",
    inputCostPerToken:  5.0 / 1_000_000,
    outputCostPerToken: 25.0 / 1_000_000,
    cacheHitCostPerToken: 0.50 / 1_000_000,  // 0.1x base input
    contextWindow: 1_000_000,
  },
  "anthropic/claude-sonnet-4-6": {
    name: "Claude Sonnet 4.6",
    provider: "anthropic",
    inputCostPerToken:  3.0 / 1_000_000,
    outputCostPerToken: 15.0 / 1_000_000,
    cacheHitCostPerToken: 0.30 / 1_000_000,
    contextWindow: 1_000_000,
  },
  "anthropic/claude-opus-4-5": {
    name: "Claude Opus 4.5",
    provider: "anthropic",
    inputCostPerToken:  5.0 / 1_000_000,
    outputCostPerToken: 25.0 / 1_000_000,
    cacheHitCostPerToken: 0.50 / 1_000_000,
    contextWindow: 1_000_000,
  },
  "anthropic/claude-sonnet-4-5": {
    name: "Claude Sonnet 4.5",
    provider: "anthropic",
    inputCostPerToken:  3.0 / 1_000_000,
    outputCostPerToken: 15.0 / 1_000_000,
    cacheHitCostPerToken: 0.30 / 1_000_000,
    contextWindow: 1_000_000,
  },
  "anthropic/claude-haiku-4-5": {
    name: "Claude Haiku 4.5",
    provider: "anthropic",
    inputCostPerToken:  1.0 / 1_000_000,
    outputCostPerToken: 5.0 / 1_000_000,
    cacheHitCostPerToken: 0.10 / 1_000_000,
    contextWindow: 200_000,
  },
  "anthropic/claude-haiku-3-5": {
    name: "Claude Haiku 3.5",
    provider: "anthropic",
    inputCostPerToken:  0.80 / 1_000_000,
    outputCostPerToken: 4.0 / 1_000_000,
    cacheHitCostPerToken: 0.08 / 1_000_000,
    contextWindow: 200_000,
  },

  // ─── OpenAI ────────────────────────────────────────────────────────────────
  // https://openai.com/api/pricing
  "openai/gpt-4o": {
    name: "GPT-4o",
    provider: "openai",
    inputCostPerToken:  2.5  / 1_000_000,
    outputCostPerToken: 10.0 / 1_000_000,
    cacheHitCostPerToken: 1.25 / 1_000_000,
    contextWindow: 128_000,
  },
  "openai/gpt-4o-mini": {
    name: "GPT-4o Mini",
    provider: "openai",
    inputCostPerToken:  0.15 / 1_000_000,
    outputCostPerToken: 0.6  / 1_000_000,
    cacheHitCostPerToken: 0.075 / 1_000_000,
    contextWindow: 128_000,
  },
  "openai/o3": {
    name: "OpenAI o3",
    provider: "openai",
    inputCostPerToken:  10.0 / 1_000_000,
    outputCostPerToken: 40.0 / 1_000_000,
    contextWindow: 200_000,
  },
  "openai/o4-mini": {
    name: "OpenAI o4-mini",
    provider: "openai",
    inputCostPerToken:  1.1 / 1_000_000,
    outputCostPerToken: 4.4 / 1_000_000,
    contextWindow: 200_000,
  },

  // ─── DeepSeek ──────────────────────────────────────────────────────────────
  // https://api-docs.deepseek.com/quick_start/pricing
  // Both deepseek-chat and deepseek-reasoner are now DeepSeek-V3.2
  "deepseek/deepseek-chat": {
    name: "DeepSeek Chat (V3.2)",
    provider: "deepseek",
    inputCostPerToken:  0.28  / 1_000_000,  // cache miss
    outputCostPerToken: 0.42  / 1_000_000,
    cacheHitCostPerToken: 0.028 / 1_000_000, // cache hit: 90% cheaper
    contextWindow: 128_000,
    notes: "Non-thinking mode. Cache miss $0.28/M, cache hit $0.028/M.",
  },
  "deepseek/deepseek-reasoner": {
    name: "DeepSeek Reasoner (V3.2 Thinking)",
    provider: "deepseek",
    inputCostPerToken:  0.28  / 1_000_000,
    outputCostPerToken: 0.42  / 1_000_000,
    cacheHitCostPerToken: 0.028 / 1_000_000,
    contextWindow: 128_000,
    notes: "Thinking mode. Max 32K output tokens (vs 8K for chat mode).",
  },

  // ─── MiniMax ───────────────────────────────────────────────────────────────
  // https://platform.minimax.io/docs/guides/pricing-paygo
  "minimax/MiniMax-M2.7": {
    name: "MiniMax M2.7",
    provider: "minimax",
    inputCostPerToken:  0.30 / 1_000_000,
    outputCostPerToken: 1.20 / 1_000_000,
    contextWindow: 204_800,
  },
  "minimax/MiniMax-M2.7-highspeed": {
    name: "MiniMax M2.7 (High Speed)",
    provider: "minimax",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 2.40 / 1_000_000,
    contextWindow: 204_800,
    notes: "Faster inference at 2× the price.",
  },
  "minimax/MiniMax-M2.5": {
    name: "MiniMax M2.5",
    provider: "minimax",
    inputCostPerToken:  0.30 / 1_000_000,
    outputCostPerToken: 1.20 / 1_000_000,
    contextWindow: 204_800,
  },
  "minimax/MiniMax-M2.5-highspeed": {
    name: "MiniMax M2.5 (High Speed)",
    provider: "minimax",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 2.40 / 1_000_000,
    contextWindow: 204_800,
  },
  "minimax/MiniMax-M2": {
    name: "MiniMax M2",
    provider: "minimax",
    inputCostPerToken:  0.30 / 1_000_000,
    outputCostPerToken: 1.20 / 1_000_000,
    contextWindow: 204_800,
  },
  "minimax/MiniMax-M1": {
    name: "MiniMax M1",
    provider: "minimax",
    inputCostPerToken:  0.25 / 1_000_000,
    outputCostPerToken: 1.20 / 1_000_000,
  },
  "minimax/MiniMax-M1-80k": {
    name: "MiniMax M1 (80k)",
    provider: "minimax",
    inputCostPerToken:  0.25 / 1_000_000,
    outputCostPerToken: 1.20 / 1_000_000,
    contextWindow: 80_000,
  },

  // ─── Kimi / Moonshot AI ────────────────────────────────────────────────────
  // Direct API: https://platform.kimi.ai  (endpoint: api.moonshot.cn/v1)
  // OpenRouter: moonshotai/*
  "moonshot/kimi-k2.5": {
    name: "Kimi K2.5",
    provider: "moonshot",
    inputCostPerToken:  0.60  / 1_000_000,  // cache miss
    outputCostPerToken: 3.00  / 1_000_000,
    cacheHitCostPerToken: 0.10 / 1_000_000, // cache hit
    contextWindow: 131_072,
    notes: "Latest Kimi coding model. Cache miss $0.60/M, cache hit $0.10/M.",
  },
  "moonshot/kimi-k2": {
    name: "Kimi K2",
    provider: "moonshot",
    inputCostPerToken:  0.55 / 1_000_000,
    outputCostPerToken: 2.20 / 1_000_000,
    contextWindow: 131_072,
  },
  "moonshot/moonshot-v1-8k": {
    name: "Moonshot V1 (8k)",
    provider: "moonshot",
    inputCostPerToken:  1.65 / 1_000_000,  // ≈ ¥12/M at 7.3 CNY/USD
    outputCostPerToken: 1.65 / 1_000_000,
    contextWindow: 8_000,
    notes: "Legacy general model. Uniform input/output pricing.",
  },
  "moonshot/moonshot-v1-32k": {
    name: "Moonshot V1 (32k)",
    provider: "moonshot",
    inputCostPerToken:  3.29 / 1_000_000,  // ≈ ¥24/M
    outputCostPerToken: 3.29 / 1_000_000,
    contextWindow: 32_000,
    notes: "Legacy general model. Uniform input/output pricing.",
  },
  "moonshot/moonshot-v1-128k": {
    name: "Moonshot V1 (128k)",
    provider: "moonshot",
    inputCostPerToken:  8.22 / 1_000_000,  // ≈ ¥60/M
    outputCostPerToken: 8.22 / 1_000_000,
    contextWindow: 128_000,
    notes: "Legacy general model. Uniform input/output pricing.",
  },
  // OpenRouter aliases
  "moonshotai/kimi-k2.5": {
    name: "Kimi K2.5 (OpenRouter)",
    provider: "openrouter",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 3.00 / 1_000_000,
  },
  "kimi-coding/k2p5": {
    name: "Kimi K2.5 (direct)",
    provider: "kimi-code",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 3.00 / 1_000_000,
  },

  // ─── GLM / Zhipu AI (Z.AI) ─────────────────────────────────────────────────
  // International API: https://api.z.ai/v1
  // China API: https://open.bigmodel.cn/api/paas/v4
  // https://docs.z.ai/guides/overview/pricing
  "z-ai/glm-5.1": {
    name: "GLM-5.1",
    provider: "z-ai",
    inputCostPerToken:  1.40 / 1_000_000,
    outputCostPerToken: 4.40 / 1_000_000,
  },
  "z-ai/glm-5": {
    name: "GLM-5",
    provider: "z-ai",
    inputCostPerToken:  1.00 / 1_000_000,
    outputCostPerToken: 3.20 / 1_000_000,
    notes: "China's first public AI company frontier model.",
  },
  "z-ai/glm-5-turbo": {
    name: "GLM-5 Turbo",
    provider: "z-ai",
    inputCostPerToken:  1.20 / 1_000_000,
    outputCostPerToken: 4.00 / 1_000_000,
  },
  "z-ai/glm-4.7": {
    name: "GLM-4.7",
    provider: "z-ai",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 2.20 / 1_000_000,
  },
  "z-ai/glm-4.7-flashx": {
    name: "GLM-4.7 FlashX",
    provider: "z-ai",
    inputCostPerToken:  0.07 / 1_000_000,
    outputCostPerToken: 0.40 / 1_000_000,
    notes: "Fast, cheap. Good for simple orchestration tasks.",
  },
  "z-ai/glm-4.7-flash": {
    name: "GLM-4.7 Flash",
    provider: "z-ai",
    inputCostPerToken:  0.0,
    outputCostPerToken: 0.0,
    notes: "Free tier.",
  },
  "z-ai/glm-4.6": {
    name: "GLM-4.6",
    provider: "z-ai",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 2.20 / 1_000_000,
  },
  "z-ai/glm-4.5": {
    name: "GLM-4.5",
    provider: "z-ai",
    inputCostPerToken:  0.60 / 1_000_000,
    outputCostPerToken: 2.20 / 1_000_000,
  },
  "z-ai/glm-4.5-x": {
    name: "GLM-4.5-X (32B MoE)",
    provider: "z-ai",
    inputCostPerToken:  2.20 / 1_000_000,
    outputCostPerToken: 8.90 / 1_000_000,
  },
  "z-ai/glm-4.5-air": {
    name: "GLM-4.5 Air",
    provider: "z-ai",
    inputCostPerToken:  0.20 / 1_000_000,
    outputCostPerToken: 1.10 / 1_000_000,
    notes: "Lightweight, good for orchestrator/simple tasks.",
  },
  "z-ai/glm-4.5-airx": {
    name: "GLM-4.5 AirX",
    provider: "z-ai",
    inputCostPerToken:  1.10 / 1_000_000,
    outputCostPerToken: 4.50 / 1_000_000,
  },
  "z-ai/glm-4.5-flash": {
    name: "GLM-4.5 Flash",
    provider: "z-ai",
    inputCostPerToken:  0.0,
    outputCostPerToken: 0.0,
    notes: "Free tier.",
  },
  "z-ai/glm-4-32b-0414-128k": {
    name: "GLM-4 32B (128k)",
    provider: "z-ai",
    inputCostPerToken:  0.10 / 1_000_000,
    outputCostPerToken: 0.10 / 1_000_000,
  },

  // ─── Google Gemini ────────────────────────────────────────────────────────
  // https://ai.google.dev/gemini-api/docs/pricing
  "google/gemini-2.5-pro": {
    name: "Gemini 2.5 Pro",
    provider: "google",
    inputCostPerToken:  1.25 / 1_000_000,  // ≤200k; >200k doubles to $2.50
    outputCostPerToken: 10.0 / 1_000_000,  // ≤200k; >200k $15.00
    cacheHitCostPerToken: 0.125 / 1_000_000,
    contextWindow: 1_000_000,
    notes: "Tiered: >200k context doubles input/output price.",
  },
  "google/gemini-2.5-flash": {
    name: "Gemini 2.5 Flash",
    provider: "google",
    inputCostPerToken:  0.30 / 1_000_000,
    outputCostPerToken: 2.50 / 1_000_000,
    cacheHitCostPerToken: 0.03 / 1_000_000,
    contextWindow: 1_000_000,
  },
  "google/gemini-2.5-flash-lite": {
    name: "Gemini 2.5 Flash-Lite",
    provider: "google",
    inputCostPerToken:  0.10 / 1_000_000,
    outputCostPerToken: 0.40 / 1_000_000,
    cacheHitCostPerToken: 0.01 / 1_000_000,
    contextWindow: 1_000_000,
    notes: "Cheapest Gemini model.",
  },
  "google/gemini-3-flash": {
    name: "Gemini 3 Flash (Preview)",
    provider: "google",
    inputCostPerToken:  0.50 / 1_000_000,
    outputCostPerToken: 3.00 / 1_000_000,
    cacheHitCostPerToken: 0.05 / 1_000_000,
    contextWindow: 1_000_000,
  },
  "google/gemini-3.1-pro": {
    name: "Gemini 3.1 Pro (Preview)",
    provider: "google",
    inputCostPerToken:  2.00 / 1_000_000,  // ≤200k; >200k doubles
    outputCostPerToken: 12.00 / 1_000_000,
    contextWindow: 1_000_000,
    notes: "Preview. Tiered: >200k context doubles price.",
  },

  // ─── Mistral AI ───────────────────────────────────────────────────────────
  // https://mistral.ai/pricing
  "mistral/mistral-large-3": {
    name: "Mistral Large 3",
    provider: "mistral",
    inputCostPerToken:  2.0 / 1_000_000,
    outputCostPerToken: 6.0 / 1_000_000,
    contextWindow: 128_000,
  },
  "mistral/mistral-medium-3": {
    name: "Mistral Medium 3",
    provider: "mistral",
    inputCostPerToken:  1.0 / 1_000_000,
    outputCostPerToken: 3.0 / 1_000_000,
    contextWindow: 128_000,
  },
  "mistral/mistral-small-3.1": {
    name: "Mistral Small 3.1",
    provider: "mistral",
    inputCostPerToken:  0.20 / 1_000_000,
    outputCostPerToken: 0.60 / 1_000_000,
    contextWindow: 128_000,
  },
  "mistral/mistral-nemo": {
    name: "Mistral Nemo",
    provider: "mistral",
    inputCostPerToken:  0.02 / 1_000_000,
    outputCostPerToken: 0.04 / 1_000_000,
    contextWindow: 128_000,
    notes: "Cheapest Mistral model.",
  },
};

/**
 * Build a fallback cost model from env vars when the active model is not in the registry.
 */
function envFallbackCostModel(): CostModel {
  const provider = process.env.LLM_PROVIDER || "unknown";
  const model = process.env.LLM_MODEL_COMPLEX || "unknown";
  return {
    name: `${provider}/${model}`,
    provider,
    inputCostPerToken:  parseFloat(process.env.INPUT_COST_PER_M  || "3.0") / 1_000_000,
    outputCostPerToken: parseFloat(process.env.OUTPUT_COST_PER_M || "15.0") / 1_000_000,
  };
}

/**
 * The active complex model ID, resolved from env vars at runtime.
 * Format: "{LLM_PROVIDER}/{LLM_MODEL_COMPLEX}"
 */
export function getActiveModel(): string {
  const provider = process.env.LLM_PROVIDER || "anthropic";
  const model = process.env.LLM_MODEL_COMPLEX || "claude-opus-4-6";
  return `${provider}/${model}`;
}

/**
 * Compute the cost for a given token usage.
 * Looks up the model in the registry; falls back to env-configured pricing.
 */
export function computeTokenCost(
  inputTokens: number,
  outputTokens: number,
  model?: string
): number {
  const activeModel = model || getActiveModel();
  const costModel = COST_MODELS[activeModel] || envFallbackCostModel();
  return (
    inputTokens  * costModel.inputCostPerToken +
    outputTokens * costModel.outputCostPerToken
  );
}

/** @deprecated Use getActiveModel() instead */
export const DEFAULT_MODEL = getActiveModel();
export const DEFAULT_COST_MODEL = COST_MODELS[DEFAULT_MODEL] || envFallbackCostModel();

/**
 * Normalize a model identifier to its bare model name — used for cross-provider
 * matching so that `z-ai/glm-4.6`, `openrouter/glm-4.6`, and `glm-4.6` all collapse
 * to the same key. The last path segment wins (handles nested prefixes like
 * `openrouter/anthropic/claude-opus-4-6`).
 */
export function bareModelName(model: string): string {
  if (!model) return "";
  const lastSlash = model.lastIndexOf("/");
  const tail = lastSlash >= 0 ? model.slice(lastSlash + 1) : model;
  return tail.toLowerCase().trim();
}
