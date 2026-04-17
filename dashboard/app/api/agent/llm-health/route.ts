export const dynamic = "force-dynamic";

import { NextResponse } from "next/server";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";

/**
 * Scans the latest openclaw session jsonl for the most recent LLM call
 * outcome. Separates "agent alive but LLM is erroring" (e.g. upstream 401 /
 * quota exhausted) from the existing heartbeat-based connection state, which
 * only reflects whether the dashboard-reporter hook has fired — and the hook
 * only fires on `agent_end`, which never happens if the very first LLM call
 * fails.
 *
 * Returns ok=true only when the latest LLM call in the session succeeded.
 */
export async function GET() {
  const sessionsRoot =
    process.env.OPENCLAW_SESSIONS_DIR ||
    path.join(os.homedir(), ".openclaw", "agents", "clawoss", "sessions");

  try {
    const entries = await fs.readdir(sessionsRoot, { withFileTypes: true });
    const jsonlFiles = entries
      .filter((e) => e.isFile() && e.name.endsWith(".jsonl"))
      .map((e) => path.join(sessionsRoot, e.name));

    if (jsonlFiles.length === 0) {
      return NextResponse.json({
        state: "unknown",
        message: "No session file found",
        lastCallAt: null,
        lastError: null,
        lastErrorAt: null,
      });
    }

    // Pick the most recently modified session file
    const stats = await Promise.all(
      jsonlFiles.map(async (f) => ({ f, mtime: (await fs.stat(f)).mtimeMs }))
    );
    stats.sort((a, b) => b.mtime - a.mtime);
    const latest = stats[0].f;

    const content = await fs.readFile(latest, "utf8");
    const lines = content.split("\n").filter(Boolean);

    // Walk backwards — the first assistant message we hit decides state.
    let lastCallAt: string | null = null;
    let lastError: string | null = null;
    let lastErrorAt: string | null = null;
    let lastSuccessAt: string | null = null;
    let state: "ok" | "errored" | "unknown" = "unknown";

    for (let i = lines.length - 1; i >= 0; i--) {
      let evt: Record<string, unknown>;
      try {
        evt = JSON.parse(lines[i]);
      } catch {
        continue;
      }
      const msg = (evt as { message?: { role?: string; errorMessage?: string; usage?: { totalTokens?: number } } }).message;
      if (!msg || msg.role !== "assistant") continue;

      const ts = (evt as { timestamp?: string }).timestamp ?? null;

      if (msg.errorMessage) {
        if (!lastError) {
          lastError = msg.errorMessage;
          lastErrorAt = ts;
        }
        // Keep walking — maybe an earlier successful call exists
        continue;
      }

      if ((msg.usage?.totalTokens ?? 0) > 0) {
        lastSuccessAt = ts;
        break;
      }
    }

    // Decide state from the TAIL of the file (most recent assistant event)
    // re-walk once more from the end until the first assistant we find.
    for (let i = lines.length - 1; i >= 0; i--) {
      let evt: Record<string, unknown>;
      try { evt = JSON.parse(lines[i]); } catch { continue; }
      const msg = (evt as { message?: { role?: string; errorMessage?: string; usage?: { totalTokens?: number } } }).message;
      if (!msg || msg.role !== "assistant") continue;
      const ts = (evt as { timestamp?: string }).timestamp ?? null;
      lastCallAt = ts;
      if (msg.errorMessage) {
        state = "errored";
      } else if ((msg.usage?.totalTokens ?? 0) > 0) {
        state = "ok";
      } else {
        // assistant with no error and no usage (e.g. toolUse-only) — treat as ok
        state = "ok";
      }
      break;
    }

    return NextResponse.json({
      state,
      session: path.basename(latest),
      lastCallAt,
      lastSuccessAt,
      lastError,
      lastErrorAt,
      message:
        state === "errored"
          ? `LLM call failing: ${lastError}`
          : state === "ok"
            ? "LLM calls succeeding"
            : "No LLM calls recorded yet",
    });
  } catch (error) {
    // Sessions dir missing (dashboard running outside openclaw container) —
    // report unknown rather than 500 so the existing UI keeps working.
    return NextResponse.json({
      state: "unknown",
      message: `Sessions unavailable: ${String((error as Error).message || error)}`,
      lastCallAt: null,
      lastError: null,
      lastErrorAt: null,
    });
  }
}
