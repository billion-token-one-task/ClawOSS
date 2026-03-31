export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { validateApiKey, unauthorizedResponse } from "@/lib/auth-api";
import { db, ensureDb } from "@/lib/db";
import { strategyVersions, settings } from "@/lib/schema";
import { eq } from "drizzle-orm";
import { nanoid } from "nanoid";

type StrategyBody = Record<string, unknown>;

export async function POST(request: Request) {
  if (!validateApiKey(request)) return unauthorizedResponse();

  try {
    await ensureDb();
    const body = (await request.json()) as StrategyBody;
    const versionId = (body.id as string) || nanoid();
    const status = (body.status as string) || "draft";

    await db.insert(strategyVersions).values({
      id: versionId,
      createdAt: body.createdAt ? new Date(body.createdAt as string) : new Date(),
      parentVersion:
        (body.parentVersion as string) ||
        (body.parent_version as string) ||
        null,
      status,
      authorType:
        (body.authorType as string) ||
        (body.author_type as string) ||
        "reflection_agent",
      config: (body.config as Record<string, unknown>) || {},
      evaluation: body.evaluation || null,
      metadata: body.metadata || null,
    });

    if (status === "active") {
      await db
        .insert(settings)
        .values({
          key: "active_strategy_version",
          value: { id: versionId },
          updatedAt: new Date(),
        })
        .onConflictDoUpdate({
          target: settings.key,
          set: {
            value: { id: versionId },
            updatedAt: new Date(),
          },
        });
    }

    return NextResponse.json({ ok: true, id: versionId });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to ingest strategy version", details: String(error) },
      { status: 500 }
    );
  }
}
