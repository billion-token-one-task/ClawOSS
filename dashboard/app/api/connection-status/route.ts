export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { db, ensureDb } from "@/lib/db";
import { heartbeats, metricsTokens, agentLogs } from "@/lib/schema";
import { desc, gte, sql, eq, and } from "drizzle-orm";
import { preferAccurateMetrics } from "@/lib/metrics-source";
import { computeBudgetStatus, extractRuntimeSnapshot } from "@/lib/runtime";

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

    const allMetrics = preferAccurateMetrics(
      await db.select().from(metricsTokens)
    );
    const totals = allMetrics.reduce(
      (acc, metric) => {
        acc.inputTokens += metric.inputTokens || 0;
        acc.outputTokens += metric.outputTokens || 0;
        acc.costUsd += metric.costUsd || 0;
        return acc;
      },
      { inputTokens: 0, outputTokens: 0, costUsd: 0 }
    );
    const runtime = extractRuntimeSnapshot(hb?.metadata);
    const budget = computeBudgetStatus(runtime, totals);
    if (budget.paused) {
      connectionMessage = budget.pauseReason || "Agent paused by budget guardrail";
    }

    // Data pipeline status
    const hasHeartbeats = (recentHeartbeats[0]?.count || 0) > 0;
    const hasMetrics = !!lastMetric[0];
    const hasRecentMetrics = lastMetric[0]
      ? lastMetric[0].timestamp.getTime() > oneHourAgo.getTime()
      : false;

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
      runtime,
      budget,
      hasAnyData: hasHeartbeats || hasMetrics,
    });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to check connection", details: String(error) },
      { status: 500 }
    );
  }
}
