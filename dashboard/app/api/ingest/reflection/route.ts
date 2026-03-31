export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { validateApiKey, unauthorizedResponse } from "@/lib/auth-api";
import { db, ensureDb } from "@/lib/db";
import { reflections } from "@/lib/schema";
import { nanoid } from "nanoid";

type ReflectionBody = Record<string, unknown>;

export async function POST(request: Request) {
  if (!validateApiKey(request)) return unauthorizedResponse();

  try {
    await ensureDb();
    const body = (await request.json()) as ReflectionBody;
    const events = Array.isArray(body.events)
      ? (body.events as ReflectionBody[])
      : [body];

    for (const event of events) {
      await db.insert(reflections).values({
        id: (event.id as string) || nanoid(),
        timestamp: event.timestamp ? new Date(event.timestamp as string) : new Date(),
        scope: (event.scope as string) || "daily",
        strategyVersion:
          (event.strategyVersion as string) ||
          (event.strategy_version as string) ||
          null,
        sourceWindowStart:
          event.sourceWindowStart || event.source_window_start
            ? new Date((event.sourceWindowStart as string) || (event.source_window_start as string))
            : null,
        sourceWindowEnd:
          event.sourceWindowEnd || event.source_window_end
            ? new Date((event.sourceWindowEnd as string) || (event.source_window_end as string))
            : null,
        summary: (event.summary as string) || "",
        insights: event.insights || null,
        recommendedChanges:
          event.recommendedChanges || event.recommended_changes || null,
        confidence: (event.confidence as number) || null,
        applied: Boolean(event.applied),
        metadata: event.metadata || null,
      });
    }

    return NextResponse.json({ ok: true, count: events.length });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to ingest reflections", details: String(error) },
      { status: 500 }
    );
  }
}
