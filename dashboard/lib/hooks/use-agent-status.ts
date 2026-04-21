import useSWR from "swr";
import type { DashboardOverview } from "@/lib/types";
import { fetcher } from "@/lib/fetcher";

export function useAgentStatus() {
  const { data, error, isLoading, mutate } = useSWR<DashboardOverview>(
    "/api/metrics/overview",
    fetcher,
    { refreshInterval: 10000, keepPreviousData: true }
  );

  return { data, error, isLoading, mutate };
}
