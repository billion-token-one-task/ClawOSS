# ClawOSS — Linux Docker deployment

Phase-1 demo deployment: one container, one long-running process
(`openclaw gateway run`), `.env`-driven LLM routing, token-budget aware.

## Quickstart

```bash
cp .env.example .env
$EDITOR .env                 # fill LLM_* and GITHUB_TOKEN at minimum
docker compose -f deploy/docker/docker-compose.yml up --build
```

The container fails fast and prints the missing env var if required
settings are absent. Silent misconfiguration that wastes tokens is the
thing we're explicitly trying to avoid.

## What goes in `.env`

Minimum for the container to boot:

| Variable | Purpose |
|---|---|
| `GITHUB_TOKEN` | Classic PAT (`ghp_*`) with `public_repo` scope. |
| `LLM_PROVIDER` | e.g. `anthropic`, `deepseek`, `z-ai`, `minimax`. |
| `LLM_BASE_URL` | OpenAI-compatible endpoint for the provider. |
| `LLM_API_KEY`  | Key for that provider. |
| `LLM_MODEL_COMPLEX` | Opus-tier model for subagents. |
| `LLM_MODEL_SIMPLE`  | Sonnet-tier model for the orchestrator. |

Strongly recommended (container warns if missing):

- `BUDGET_USD_TOTAL` — hard cap in USD, agent pauses when reached.
- `CLAW_API_KEY` + `DASHBOARD_URL` — telemetry into the Vercel dashboard.
- `MODEL_TOKEN_BUDGETS` — per-model token caps (see `.env.example`).

## State persistence

`clawoss_state` (named volume) holds `~/.openclaw/` — the agent registry,
session jsonl files, and OpenClaw extensions. Delete the volume to get a
clean-room restart:

```bash
docker compose -f deploy/docker/docker-compose.yml down -v
```

Workspace memory (`workspace/memory/*.md`) is bind-mounted to the host so
you can watch the pipeline state live from outside the container.

## Relationship to the other docker setups

| Path | Purpose |
|---|---|
| `docker/` + root `docker-compose.yml` | Alpha autonomy backend — API + worker + reflection services that read/write the dashboard DB. |
| `deploy/docker/` (this dir) | The OpenClaw agent itself. This is what you run on a Linux host for the Phase-1 demo. |
| `scripts/restart.sh` | macOS-native launchd deployment. On Linux it detects systemd and degrades gracefully; this image is the cleaner option for Linux. |

## Not included in this image

- The Vercel dashboard (keep it on Vercel — running it locally doesn't
  help the Phase-1 demo). Set `DASHBOARD_URL` + `CLAW_API_KEY` to connect.
- The `openclaw` CLI binary is pulled from npm at build time. Operators
  behind a proxy should set `--build-arg OPENCLAW_VERSION=<pinned>` and
  configure their npm registry.
- No automated backup of `clawoss_state`. If you care about queue
  survival across host rebuilds, back up the volume yourself.
