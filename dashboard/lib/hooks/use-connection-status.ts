import useSWR from "swr";

interface ConnectionStatus {
  connection: {
    state: "connected" | "degraded" | "disconnected" | "unknown";
    message: string;
    lastHeartbeat: string | null;
    heartbeatStatus: string | null;
  };
  pipeline: {
    heartbeats: boolean;
    metrics: boolean;
    heartbeatsLastHour: number;
    errorsLastHour: number;
    lastMetricAt: string | null;
  };
  runtime: {
    primaryModel: string | null;
    primaryModelName: string | null;
    primaryProvider: string | null;
    fallbackModels: string[];
    heartbeatIntervalMinutes: number;
    pricing: {
      inputUsdPerMillionTokens: number | null;
      outputUsdPerMillionTokens: number | null;
    };
  };
  budget: {
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
  };
  hasAnyData: boolean;
}

const fetcher = (url: string) => fetch(url).then((r) => r.json());

export function useConnectionStatus() {
  const { data, error, isLoading } = useSWR<ConnectionStatus>(
    "/api/connection-status",
    fetcher,
    { refreshInterval: 5000 }
  );

  return { data, error, isLoading };
}
