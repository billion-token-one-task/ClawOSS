export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { db, ensureDb } from "@/lib/db";
import { heartbeats, metricsTokens, agentLogs } from "@/lib/schema";
import { desc, gte, sql, eq, and } from "drizzle-orm";

export async function GET() {
  try {
    await ensureDb();
    const now = new Date();
    const fiveMinutesAgo = new Date(now.getTime() - 5 * 60 * 1000);
    const fifteenMinutesAgo = new Date(now.getTime() - 15 * 60 * 1000);
    const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

    // Latest heartbeat
    const latestHeartbeat = await db
      .select()
      .from(heartbeats)
      .orderBy(desc(heartbeats.timestamp))
      .limit(1);

    const hb = latestHeartbeat[0];
    const lastBeatTime = hb?.timestamp?.getTime() || 0;

    // Determine connection state
    let connectionState: "connected" | "degraded" | "disconnected" | "unknown" = "unknown";
    let connectionMessage = "No heartbeat data available";

    if (hb) {
      if (lastBeatTime > fiveMinutesAgo.getTime()) {
        connectionState = "connected";
        connectionMessage = "Agent is actively reporting";
      } else if (lastBeatTime > fifteenMinutesAgo.getTime()) {
        connectionState = "degraded";
        connectionMessage = "Agent heartbeat delayed";
      } else {
        connectionState = "disconnected";
        connectionMessage = "Agent has not reported recently";
      }
    }

    // Recent heartbeat count (last hour)
    const recentHeartbeats = await db
      .select({ count: sql<number>`count(*)` })
      .from(heartbeats)
      .where(gte(heartbeats.timestamp, oneHourAgo));

    // Recent errors (last hour)
    const recentErrors = await db
      .select({ count: sql<number>`count(*)` })
      .from(agentLogs)
      .where(and(gte(agentLogs.timestamp, oneHourAgo), eq(agentLogs.level, "error")));

    // Last metric received
    const lastMetric = await db
      .select()
      .from(metricsTokens)
      .orderBy(desc(metricsTokens.timestamp))
      .limit(1);

    // Data pipeline status
    const hasHeartbeats = (recentHeartbeats[0]?.count || 0) > 0;
    const hasMetrics = !!lastMetric[0];
    const hasRecentMetrics = lastMetric[0]
      ? lastMetric[0].timestamp.getTime() > oneHourAgo.getTime()
      : false;

    // LLM health — probes the openclaw session jsonl directly so we can
    // surface "agent alive but LLM is 4xx/5xx" even when no heartbeat has
    // been ingested yet (the hook only fires on agent_end, which never
    // happens if the very first LLM call fails).
    let llm: {
      state: "ok" | "errored" | "unknown";
      message: string;
      lastError: string | null;
      lastErrorAt: string | null;
      lastSuccessAt: string | null;
    } = {
      state: "unknown",
      message: "LLM health probe unavailable",
      lastError: null,
      lastErrorAt: null,
      lastSuccessAt: null,
    };
    try {
      // Absolute URL because internal fetch in Next server runtime needs it.
      const origin = process.env.NEXT_PUBLIC_DASHBOARD_URL ||
        `http://127.0.0.1:${process.env.PORT || 3000}`;
      const res = await fetch(`${origin}/api/agent/llm-health`, { cache: "no-store" });
      if (res.ok) {
        const body = await res.json();
        llm = {
          state: body.state,
          message: body.message,
          lastError: body.lastError ?? null,
          lastErrorAt: body.lastErrorAt ?? null,
          lastSuccessAt: body.lastSuccessAt ?? null,
        };
      }
    } catch {
      // non-critical
    }

    return NextResponse.json({
      connection: {
        state: connectionState,
        message: connectionMessage,
        lastHeartbeat: hb?.timestamp || null,
        heartbeatStatus: hb?.status || null,
      },
      pipeline: {
        heartbeats: hasHeartbeats,
        metrics: hasRecentMetrics,
        heartbeatsLastHour: recentHeartbeats[0]?.count || 0,
        errorsLastHour: recentErrors[0]?.count || 0,
        lastMetricAt: lastMetric[0]?.timestamp || null,
      },
      llm,
      hasAnyData: hasHeartbeats || hasMetrics,
    });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to check connection", details: String(error) },
      { status: 500 }
    );
  }
}
