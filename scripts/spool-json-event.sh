#!/usr/bin/env bash
set -euo pipefail

CHANNEL="${1:?Usage: spool-json-event.sh <runtime/decisions|runtime/outcomes|reflections/outbox|strategy/outbox>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
TARGET_DIR="$WORKSPACE_DIR/$CHANNEL"

mkdir -p "$TARGET_DIR"

PAYLOAD=$(cat)

echo "$PAYLOAD" | jq . >/dev/null

EVENT_ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex)
PY
)

STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUTFILE="$TARGET_DIR/${STAMP}-${EVENT_ID}.json"

printf '%s\n' "$PAYLOAD" > "$OUTFILE"
echo "$OUTFILE"
