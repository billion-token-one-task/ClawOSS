"use client";

import { Card, CardContent } from "@/components/ui/card";
import { formatDuration } from "@/lib/utils";
import type { AgentStatus } from "@/lib/types";

interface AgentStatusCardProps {
  status: AgentStatus;
}

export function AgentStatusCard({ status }: AgentStatusCardProps) {
  const tone = status.isPaused
    ? {
        dot: "bg-amber-500",
        ping: "bg-amber-500",
        text: "text-amber-400/80",
        label: "paused",
      }
    : status.isOnline
      ? {
          dot: "bg-emerald-500",
          ping: "bg-emerald-500",
          text: "text-emerald-400/80",
          label: "online",
        }
      : {
          dot: "bg-red-500",
          ping: "bg-red-500",
          text: "text-red-400/80",
          label: "offline",
        };

  return (
    <Card className="accent-top corner-brackets card-elevated">
      <CardContent className="p-5">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-2.5 font-mono text-xs">
            <span className="relative flex h-2.5 w-2.5">
              {(status.isOnline || status.isPaused) && (
                <span className={`absolute inline-flex h-full w-full animate-ping rounded-full ${tone.ping} opacity-50`} />
              )}
              <span className={`relative h-2.5 w-2.5 rounded-full ${tone.dot}`} />
            </span>
            <span className="stat-label">Agent</span>
            <span className={`font-medium ${tone.text}`}>
              {tone.label}
            </span>
          </div>
          {(status.isOnline || status.isPaused) && (
            <span className={`text-[9px] font-mono uppercase tracking-widest ${status.isPaused ? "text-amber-500/50" : "text-emerald-500/40"}`}>
              {status.isPaused ? "budget-stop" : "active"}
            </span>
          )}
        </div>
        {status.pauseReason && (
          <div className="mb-4 rounded-md border border-amber-500/20 bg-amber-500/5 px-3 py-2 text-[11px] font-mono text-amber-300/80">
            {status.pauseReason}
          </div>
        )}
        <div className="grid grid-cols-3 gap-6 font-mono">
          <div>
            <div className="stat-label">Uptime</div>
            <div className="text-xl font-bold mt-1 tracking-tight tabular-nums">{formatDuration(status.uptimeSeconds)}</div>
          </div>
          <div>
            <div className="stat-label">HB Streak</div>
            <div className="text-xl font-bold mt-1 tracking-tight tabular-nums">{status.heartbeatStreak.toLocaleString()}</div>
          </div>
          <div>
            <div className="stat-label">Current Task</div>
            <div className="text-xs mt-1.5 truncate">
              {status.currentTask || <span className="text-muted-foreground/40 italic">idle</span>}
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
