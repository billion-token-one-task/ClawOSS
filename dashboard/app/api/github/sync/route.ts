export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { syncPRsFromGitHub } from "@/lib/github";

const MANUAL_GITHUB_SYNC =
  process.env.CLAWOSS_DASHBOARD_MANUAL_GITHUB_SYNC === "true";

export async function GET() {
  if (!MANUAL_GITHUB_SYNC) {
    return NextResponse.json(
      {
        ok: false,
        disabled: true,
        reason:
          "GitHub PR backfill is disabled for this deployment. Set CLAWOSS_DASHBOARD_MANUAL_GITHUB_SYNC=true to re-enable.",
      },
      { status: 403 }
    );
  }

  try {
    const result = await syncPRsFromGitHub();
    return NextResponse.json(result);
  } catch (error) {
    return NextResponse.json(
      { error: "GitHub sync failed", details: String(error) },
      { status: 500 }
    );
  }
}
