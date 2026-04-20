import useSWR from "swr";
import type { AgentState } from "@/lib/types";
import { fetcher } from "@/lib/fetcher";

export function useAgentState() {
  const { data, error, isLoading, mutate } = useSWR<{
    state: AgentState | null;
  }>("/api/state", fetcher, { refreshInterval: 5000, keepPreviousData: true });

  return { data, error, isLoading, mutate };
}
