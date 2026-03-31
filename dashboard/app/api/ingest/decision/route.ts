export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { validateApiKey, unauthorizedResponse } from "@/lib/auth-api";
import { db, ensureDb } from "@/lib/db";
import { decisionEvents } from "@/lib/schema";
import { nanoid } from "nanoid";

type DecisionBody = Record<string, unknown>;

export async function POST(request: Request) {
  if (!validateApiKey(request)) return unauthorizedResponse();

  try {
    await ensureDb();
    const body = (await request.json()) as DecisionBody;
    const events = Array.isArray(body.events)
      ? (body.events as DecisionBody[])
      : [body];

    for (const event of events) {
      await db.insert(decisionEvents).values({
        id: (event.id as string) || nanoid(),
        timestamp: event.timestamp ? new Date(event.timestamp as string) : new Date(),
        sessionId: (event.sessionId as string) || (event.session_id as string) || null,
        stage: (event.stage as string) || "unknown",
        strategyVersion:
          (event.strategyVersion as string) ||
          (event.strategy_version as string) ||
          null,
        repo: (event.repo as string) || null,
        issueNumber:
          (event.issueNumber as number) ||
          (event.issue_number as number) ||
          null,
        prNumber:
          (event.prNumber as number) ||
          (event.pr_number as number) ||
          null,
        selected: Boolean(event.selected),
        score: (event.score as number) || null,
        confidence: (event.confidence as number) || null,
        expectedMergeProb:
          (event.expectedMergeProb as number) ||
          (event.expected_merge_prob as number) ||
          null,
        expectedTokenCost:
          (event.expectedTokenCost as number) ||
          (event.expected_token_cost as number) ||
          null,
        reasoningSummary:
          (event.reasoningSummary as string) ||
          (event.reasoning_summary as string) ||
          null,
        candidateSet:
          event.candidateSet || event.candidate_set || null,
        metadata: event.metadata || null,
      });
    }

    return NextResponse.json({ ok: true, count: events.length });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to ingest decision events", details: String(error) },
      { status: 500 }
    );
  }
}
