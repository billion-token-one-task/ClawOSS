import useSWR from "swr";
import { fetcher } from "@/lib/fetcher";

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
  hasAnyData: boolean;
}

export function useConnectionStatus() {
  const { data, error, isLoading } = useSWR<ConnectionStatus>(
    "/api/connection-status",
    fetcher,
    { refreshInterval: 5000, keepPreviousData: true }
  );

  return { data, error, isLoading };
}
