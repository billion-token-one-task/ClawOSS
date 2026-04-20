/**
 * Cost models for different LLM providers.
 * Prices are in USD per token.
 */
export interface CostModel {
  name: string;
  provider: string;
  inputCostPerToken: number;
  outputCostPerToken: number;
}

export const COST_MODELS: Record<string, CostModel> = {
  "kimi-coding/k2p5": {
    name: "Kimi K2.5 (Kimi Code)",
    provider: "kimi-code",
    inputCostPerToken: 0.6 / 1_000_000,
    outputCostPerToken: 3.0 / 1_000_000,
  },
  "z-ai/glm-5": {
    name: "GLM-5",
    provider: "openrouter",
    inputCostPerToken: 0.72 / 1_000_000,
    outputCostPerToken: 2.3 / 1_000_000,
  },
  "moonshotai/kimi-k2.5": {
    name: "Kimi K2.5 (OpenRouter)",
    provider: "openrouter",
    inputCostPerToken: 0.45 / 1_000_000,
    outputCostPerToken: 2.2 / 1_000_000,
  },
  "minimax/MiniMax-M2.7": {
    name: "MiniMax M2.7",
    provider: "minimax",
    inputCostPerToken: 0.3 / 1_000_000,
    outputCostPerToken: 1.2 / 1_000_000,
  },
  "minimax/MiniMax-M1-80k": {
    name: "MiniMax M2.5 (legacy)",
    provider: "openrouter",
    inputCostPerToken: 0.25 / 1_000_000,
    outputCostPerToken: 1.2 / 1_000_000,
  },
  "minimax/MiniMax-M1": {
    name: "MiniMax M1",
    provider: "openrouter",
    inputCostPerToken: 0.25 / 1_000_000,
    outputCostPerToken: 1.2 / 1_000_000,
  },
  "anthropic/claude-sonnet-4-20250514": {
    name: "Claude Sonnet 4",
    provider: "openrouter",
    inputCostPerToken: 3.0 / 1_000_000,
    outputCostPerToken: 15.0 / 1_000_000,
  },
  "openai/gpt-4o": {
    name: "GPT-4o",
    provider: "openrouter",
    inputCostPerToken: 2.5 / 1_000_000,
    outputCostPerToken: 10.0 / 1_000_000,
  },
};

export const DEFAULT_MODEL = "minimax/MiniMax-M2.7";
export const DEFAULT_COST_MODEL = COST_MODELS[DEFAULT_MODEL];

/** Returns the active model from env (server-side only) or falls back to DEFAULT_MODEL. */
export function getActiveModel(): string {
  return process.env.LLM_MODEL || DEFAULT_MODEL;
}

/**
 * Compute the cost for a given token usage.
 * Looks up the model in COST_MODELS; if not found, reads pricing from
 * LLM_INPUT_COST_PER_MILLION / LLM_OUTPUT_COST_PER_MILLION env vars.
 */
export function computeTokenCost(
  inputTokens: number,
  outputTokens: number,
  model?: string
): number {
  const m = model || getActiveModel();
  if (COST_MODELS[m]) {
    const cm = COST_MODELS[m];
    return inputTokens * cm.inputCostPerToken + outputTokens * cm.outputCostPerToken;
  }
  const inputRate = parseFloat(process.env.LLM_INPUT_COST_PER_MILLION || "0.15") / 1_000_000;
  const outputRate = parseFloat(process.env.LLM_OUTPUT_COST_PER_MILLION || "0.60") / 1_000_000;
  return inputTokens * inputRate + outputTokens * outputRate;
}
