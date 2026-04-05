import { readFile } from "node:fs/promises";
import path from "node:path";

export type RuntimeOverallStatus = "running" | "degraded" | "stopped" | "restarting" | "error";
export type RuntimeComponentStatus = "running" | "stopped" | "unknown";
export type RuntimeHealthStatus = "pass" | "fail" | "unknown";

export interface RuntimeStatus {
  updatedAt: string;
  source: string;
  overall: RuntimeOverallStatus;
  gateway: RuntimeComponentStatus;
  dashboardSync: RuntimeComponentStatus;
  runCycle: RuntimeComponentStatus;
  agentRegistered: boolean;
  workspaceLinked: boolean;
  health: RuntimeHealthStatus;
  note: string;
}

function candidateRuntimeStatusPaths() {
  const explicitWorkspace = process.env.CLAWOSS_WORKSPACE_DIR;
  const cwd = process.cwd();

  return [
    explicitWorkspace ? path.join(explicitWorkspace, "runtime", "service-status.json") : null,
    process.env.CLAWOSS_ROOT ? path.join(process.env.CLAWOSS_ROOT, "workspace", "runtime", "service-status.json") : null,
    path.join(cwd, "workspace", "runtime", "service-status.json"),
    path.join(cwd, "..", "workspace", "runtime", "service-status.json"),
    "/workspace/runtime/service-status.json",
  ].filter((value): value is string => Boolean(value));
}

export async function readRuntimeStatus(): Promise<RuntimeStatus | null> {
  for (const filePath of candidateRuntimeStatusPaths()) {
    try {
      const raw = await readFile(filePath, "utf8");
      const parsed = JSON.parse(raw) as RuntimeStatus;
      if (parsed && parsed.updatedAt && parsed.overall) {
        return parsed;
      }
    } catch {
      continue;
    }
  }

  return null;
}

export function resolveConnectionFromRuntime(runtime: RuntimeStatus | null) {
  if (!runtime) {
    return null;
  }

  switch (runtime.overall) {
    case "running":
      return {
        state: "connected" as const,
        message: runtime.note || "ClawOSS runtime active",
      };
    case "degraded":
    case "restarting":
      return {
        state: "degraded" as const,
        message: runtime.note || "ClawOSS runtime is recovering",
      };
    case "stopped":
    case "error":
      return {
        state: "disconnected" as const,
        message: runtime.note || "ClawOSS runtime is not active",
      };
    default:
      return {
        state: "unknown" as const,
        message: runtime.note || "ClawOSS runtime status is unknown",
      };
  }
}
