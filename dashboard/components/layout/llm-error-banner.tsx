"use client";

import { useEffect, useState } from "react";

interface LlmState {
  state: "ok" | "errored" | "unknown";
  message?: string;
  lastError?: string | null;
  lastErrorAt?: string | null;
  lastSuccessAt?: string | null;
}

const POLL_INTERVAL_MS = 30_000;

function formatRelative(iso: string | null | undefined): string {
  if (!iso) return "";
  const diffMs = Date.now() - new Date(iso).getTime();
  if (diffMs < 60_000) return `${Math.floor(diffMs / 1000)}s ago`;
  if (diffMs < 3600_000) return `${Math.floor(diffMs / 60_000)}m ago`;
  return `${Math.floor(diffMs / 3600_000)}h ago`;
}

export function LlmErrorBanner() {
  const [llm, setLlm] = useState<LlmState | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    let cancelled = false;

    async function poll() {
      try {
        const res = await fetch("/api/connection-status", { cache: "no-store" });
        if (!res.ok) return;
        const data = await res.json();
        if (cancelled) return;
        setLlm(data.llm ?? null);
      } catch {
        // silent — banner stays in last known state
      }
    }

    poll();
    const interval = setInterval(poll, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  if (!mounted) return null;
  if (!llm || llm.state !== "errored") return null;

  return (
    <div className="flex items-start gap-3 px-4 py-2 text-xs font-mono border-b bg-amber-500/10 border-amber-500/30 text-amber-300">
      <span className="font-bold shrink-0 pt-0.5">!! LLM ERROR</span>
      <div className="flex-1 flex flex-wrap gap-x-4 gap-y-0.5">
        <span className="text-amber-300">
          Agent is alive but LLM calls are failing — upstream provider rejecting requests.
        </span>
        {llm.lastError && (
          <span className="text-amber-300/80 font-semibold truncate max-w-[50vw]">
            {llm.lastError}
          </span>
        )}
        {llm.lastErrorAt && (
          <span className="text-amber-300/60 shrink-0">
            last fail {formatRelative(llm.lastErrorAt)}
          </span>
        )}
        {llm.lastSuccessAt && (
          <span className="text-amber-300/60 shrink-0">
            last ok {formatRelative(llm.lastSuccessAt)}
          </span>
        )}
      </div>
    </div>
  );
}
