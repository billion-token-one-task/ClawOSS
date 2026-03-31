export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { validateApiKey, unauthorizedResponse } from "@/lib/auth-api";
import { db, ensureDb } from "@/lib/db";
import { executionOutcomes } from "@/lib/schema";
import { nanoid } from "nanoid";

type OutcomeBody = Record<string, unknown>;

export async function POST(request: Request) {
  if (!validateApiKey(request)) return unauthorizedResponse();

  try {
    await ensureDb();
    const body = (await request.json()) as OutcomeBody;
    const events = Array.isArray(body.events)
      ? (body.events as OutcomeBody[])
      : [body];

    for (const event of events) {
      await db.insert(executionOutcomes).values({
        id: (event.id as string) || nanoid(),
        timestamp: event.timestamp ? new Date(event.timestamp as string) : new Date(),
        decisionId:
          (event.decisionId as string) ||
          (event.decision_id as string) ||
          null,
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
        outcome: (event.outcome as string) || "unknown",
        timeToFirstReviewHours:
          (event.timeToFirstReviewHours as number) ||
          (event.time_to_first_review_hours as number) ||
          null,
        timeToMergeHours:
          (event.timeToMergeHours as number) ||
          (event.time_to_merge_hours as number) ||
          null,
        tokenCost:
          (event.tokenCost as number) ||
          (event.token_cost as number) ||
          null,
        inputTokens:
          (event.inputTokens as number) ||
          (event.input_tokens as number) ||
          null,
        outputTokens:
          (event.outputTokens as number) ||
          (event.output_tokens as number) ||
          null,
        failureCategory:
          (event.failureCategory as string) ||
          (event.failure_category as string) ||
          null,
        metadata: event.metadata || null,
      });
    }

    return NextResponse.json({ ok: true, count: events.length });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to ingest execution outcomes", details: String(error) },
      { status: 500 }
    );
  }
}
