export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { db, ensureDb } from "@/lib/db";
import { reflections, settings, strategyVersions } from "@/lib/schema";
import { desc, eq, sql } from "drizzle-orm";

export async function GET() {
  try {
    await ensureDb();

    const [activeSetting, latestStrategies, reflectionSummary] = await Promise.all([
      db.query.settings.findFirst({
        where: eq(settings.key, "active_strategy_version"),
      }),
      db.select().from(strategyVersions).orderBy(desc(strategyVersions.createdAt)).limit(5),
      db
        .select({
          total: sql<number>`count(*)`,
          applied: sql<number>`sum(case when ${reflections.applied} = 1 then 1 else 0 end)`,
        })
        .from(reflections),
    ]);

    return NextResponse.json({
      activeStrategy: activeSetting?.value || null,
      recentStrategies: latestStrategies,
      reflections: reflectionSummary[0] || { total: 0, applied: 0 },
    });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to fetch strategy metrics", details: String(error) },
      { status: 500 }
    );
  }
}
