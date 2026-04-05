export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { db, ensureDb } from "@/lib/db";
import { agentState } from "@/lib/schema";
import { DASHBOARD_DEMO_SEED_ENABLED, getDemoState } from "@/lib/demo-seed";
import { readRuntimeStatus } from "@/lib/runtime-status";
import { desc } from "drizzle-orm";

export async function GET() {
  try {
    await ensureDb();
    const runtime = await readRuntimeStatus();

    if (DASHBOARD_DEMO_SEED_ENABLED) {
      const demo = getDemoState();
      return NextResponse.json({
        ...demo,
        state: demo.state
          ? {
              ...demo.state,
              currentSkill: runtime?.note || demo.state.currentSkill,
              metadata: {
                ...(demo.state.metadata || {}),
                agent: {
                  ...(demo.state.metadata?.agent || {}),
                  status:
                    runtime?.overall === "running"
                      ? "online"
                      : runtime?.overall === "degraded" || runtime?.overall === "restarting"
                        ? "degraded"
                        : "offline",
                },
                runtime,
              },
            }
          : demo.state,
        runtime,
      });
    }

    const latest = await db
      .select()
      .from(agentState)
      .orderBy(desc(agentState.timestamp))
      .limit(1);

    if (latest.length === 0) {
      return NextResponse.json({
        state: null,
        message: "No agent state reported yet",
      });
    }

    const s = latest[0];
    return NextResponse.json({
      state: {
        id: s.id,
        timestamp: s.timestamp,
        currentSkill: s.currentSkill,
        currentRepo: s.currentRepo,
        currentIssue: s.currentIssue,
        workQueue: s.workQueue,
        pipelineState: s.pipelineState,
        activeRepos: s.activeRepos,
        metadata: s.metadata,
      },
      runtime,
    });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to fetch state", details: String(error) },
      { status: 500 }
    );
  }
}
