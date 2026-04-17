"use client";

import { useEffect, useState } from "react";

interface ExhaustedModel {
  model: string;
  used: number;
  cap: number;
}

interface HealthCheckResponse {
  modelBudgets?: {
    exhausted?: ExhaustedModel[];
  };
}

const POLL_INTERVAL_MS = 30_000;

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

export function ModelBudgetBanner() {
  const [exhausted, setExhausted] = useState<ExhaustedModel[]>([]);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    let cancelled = false;

    async function poll() {
      try {
        const res = await fetch("/api/agent/health-check", { cache: "no-store" });
        if (!res.ok) return;
        const data: HealthCheckResponse = await res.json();
        if (cancelled) return;
        setExhausted(data.modelBudgets?.exhausted ?? []);
      } catch {
        // non-critical — banner stays in last known state
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
  if (exhausted.length === 0) return null;

  return (
    <div className="flex items-start gap-3 px-4 py-2 text-xs font-mono border-b bg-red-500/10 border-red-500/30 text-red-300">
      <span className="font-bold shrink-0 pt-0.5">!! MODEL BUDGET</span>
      <div className="flex-1 flex flex-wrap gap-x-4 gap-y-0.5">
        {exhausted.map((m) => (
          <span key={m.model} className="text-red-300">
            <span className="font-semibold">{m.model}</span>: {formatTokens(m.used)} / {formatTokens(m.cap)} tokens — STOPPED
          </span>
        ))}
        <span className="text-red-300/70 shrink-0">
          raise via PUT /api/settings or MODEL_TOKEN_BUDGETS env var
        </span>
      </div>
    </div>
  );
}
