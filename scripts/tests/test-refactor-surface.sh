#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

AGENTS="$ROOT/workspace/AGENTS.md"
HEARTBEAT="$ROOT/workspace/HEARTBEAT.md"
OPENCLAW="$ROOT/config/openclaw.json"

grep -q 'config/mission.json' "$AGENTS"
grep -q 'The AI is not responsible for' "$AGENTS"
if grep -qi 'subagent' "$AGENTS"; then
  echo "AGENTS.md still references subagents" >&2
  exit 1
fi
if grep -qi 'heartbeat loop' "$AGENTS"; then
  echo "AGENTS.md still references the old heartbeat flow" >&2
  exit 1
fi

grep -q 'external controller' "$HEARTBEAT"
grep -q 'output contract' "$HEARTBEAT"
if grep -q 'sessions_spawn' "$HEARTBEAT"; then
  echo "HEARTBEAT.md still references session spawning" >&2
  exit 1
fi

jq -e '
  .agents.defaults.subagents.maxConcurrent == 1 and
  (.agents.list[0].heartbeat | has("every") | not)
' "$OPENCLAW" >/dev/null

echo "refactor surface files are aligned with the new architecture."
