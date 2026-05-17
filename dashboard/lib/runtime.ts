export interface RuntimeSnapshot {
  primaryModel: string | null;
  primaryModelName: string | null;
  primaryProvider: string | null;
  fallbackModels: string[];
  heartbeatIntervalMinutes: number;
  pricing: {
    inputUsdPerMillionTokens: number | null;
    outputUsdPerMillionTokens: number | null;
  };
  budget: {
    tokenBudgetTotal: number | null;
    costBudgetUsdTotal: number | null;
  };
}

export interface BudgetStatus {
  tokenBudgetTotal: number | null;
  costBudgetUsdTotal: number | null;
  usedTokensTotal: number;
  usedCostTotalUsd: number;
  remainingTokens: number | null;
  remainingCostUsd: number | null;
  tokenUsagePercent: number | null;
  costUsagePercent: number | null;
  exhausted: boolean;
  paused: boolean;
  pauseReason: string | null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

function asStringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .map((item) => asString(item))
      .filter((item): item is string => Boolean(item));
  }
  if (typeof value === "string") {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }
  return [];
}

export function extractRuntimeSnapshot(metadata: unknown): RuntimeSnapshot {
  const root = asRecord(metadata);
  const runtime = asRecord(root.runtime);
  const pricing = asRecord(runtime.pricing);
  const budget = asRecord(runtime.budget);

  return {
    primaryModel: asString(runtime.primaryModel) ?? asString(root.model),
    primaryModelName:
      asString(runtime.primaryModelName) ?? asString(root.modelName),
    primaryProvider:
      asString(runtime.primaryProvider) ?? asString(root.provider),
    fallbackModels:
      asStringArray(runtime.fallbackModels).length > 0
        ? asStringArray(runtime.fallbackModels)
        : asStringArray(root.fallbackModels),
    heartbeatIntervalMinutes:
      asNumber(runtime.heartbeatIntervalMinutes) ??
      asNumber(root.heartbeatIntervalMinutes) ??
      5,
    pricing: {
      inputUsdPerMillionTokens:
        asNumber(pricing.inputUsdPerMillionTokens) ??
        asNumber(root.inputUsdPerMillionTokens),
      outputUsdPerMillionTokens:
        asNumber(pricing.outputUsdPerMillionTokens) ??
        asNumber(root.outputUsdPerMillionTokens),
    },
    budget: {
      tokenBudgetTotal:
        asNumber(budget.tokenBudgetTotal) ?? asNumber(root.tokenBudgetTotal),
      costBudgetUsdTotal:
        asNumber(budget.costBudgetUsdTotal) ??
        asNumber(root.costBudgetUsdTotal),
    },
  };
}

function percent(used: number, total: number | null): number | null {
  if (total == null || total <= 0) return null;
  return Math.min(100, Math.round((used / total) * 1000) / 10);
}

export function computeBudgetStatus(
  runtime: RuntimeSnapshot,
  totals: {
    inputTokens: number;
    outputTokens: number;
    costUsd: number;
  },
  manuallyPaused = false
): BudgetStatus {
  const usedTokensTotal = (totals.inputTokens || 0) + (totals.outputTokens || 0);
  const usedCostTotalUsd = Math.round((totals.costUsd || 0) * 1_000_000) / 1_000_000;
  const tokenBudgetTotal = runtime.budget.tokenBudgetTotal;
  const costBudgetUsdTotal = runtime.budget.costBudgetUsdTotal;

  const tokenExceeded =
    tokenBudgetTotal != null && tokenBudgetTotal > 0
      ? usedTokensTotal > tokenBudgetTotal
      : false;
  const costExceeded =
    costBudgetUsdTotal != null && costBudgetUsdTotal > 0
      ? usedCostTotalUsd > costBudgetUsdTotal
      : false;

  let pauseReason: string | null = null;
  if (manuallyPaused) {
    pauseReason = "已手动暂停";
  } else if (tokenExceeded) {
    pauseReason = `累计 token 已达到预算上限 (${usedTokensTotal}/${tokenBudgetTotal})`;
  } else if (costExceeded) {
    pauseReason = `累计成本已达到预算上限 ($${usedCostTotalUsd.toFixed(2)}/$${costBudgetUsdTotal?.toFixed(2)})`;
  }

  return {
    tokenBudgetTotal,
    costBudgetUsdTotal,
    usedTokensTotal,
    usedCostTotalUsd,
    remainingTokens:
      tokenBudgetTotal != null ? Math.max(tokenBudgetTotal - usedTokensTotal, 0) : null,
    remainingCostUsd:
      costBudgetUsdTotal != null
        ? Math.max(
            Math.round((costBudgetUsdTotal - usedCostTotalUsd) * 1_000_000) / 1_000_000,
            0
          )
        : null,
    tokenUsagePercent: percent(usedTokensTotal, tokenBudgetTotal),
    costUsagePercent: percent(usedCostTotalUsd, costBudgetUsdTotal),
    exhausted: tokenExceeded || costExceeded,
    paused: manuallyPaused || tokenExceeded || costExceeded,
    pauseReason,
  };
}

export function formatPricingLabel(runtime: RuntimeSnapshot): string | null {
  const input = runtime.pricing.inputUsdPerMillionTokens;
  const output = runtime.pricing.outputUsdPerMillionTokens;
  if (input == null && output == null) return null;
  return `$${(input ?? 0).toFixed(2)}/$${(output ?? 0).toFixed(2)}/M`;
}
