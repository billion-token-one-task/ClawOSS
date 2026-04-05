#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TMP_REPO="$TMP_ROOT/repo"
TMP_HOME="$TMP_ROOT/home"
TMP_BIN="$TMP_ROOT/bin"
mkdir -p "$TMP_REPO" "$TMP_HOME" "$TMP_BIN"
cp -a "$ROOT/." "$TMP_REPO"/

cat > "$TMP_REPO/.env" <<'EOF'
GITHUB_TOKEN=test-gh-token
MINIMAX_API_KEY=test-minimax-key
CLAW_API_KEY=test-claw-key
GITHUB_USERNAME=SmokeUser
GITHUB_EMAIL=smoke@example.com
EOF

cat > "$TMP_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ] && [ "${2:-}" = "user" ]; then
  printf 'SmokeUser\n'
  exit 0
fi
exit 0
EOF

cat > "$TMP_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"synced":0}\n'
EOF

cat > "$TMP_BIN/openclaw" <<'EOF'
#!/usr/bin/env bash
set -e
LOG_FILE="${OPENCLAW_LOG_FILE:-/tmp/openclaw-restart-smoke.log}"
printf '%s\n' "$*" >> "$LOG_FILE"
case "$1 $2" in
  "gateway status")
    printf 'ok\n'
    exit 0
    ;;
  "gateway install"|"gateway stop"|"gateway run"|"system event"|"sessions cleanup")
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_BIN/gh" "$TMP_BIN/openclaw" "$TMP_BIN/curl"

mkdir -p "$TMP_HOME/.openclaw/agents/clawoss/sessions"
mkdir -p "$TMP_HOME/.openclaw/cron"
cat > "$TMP_HOME/.openclaw/agents/clawoss/sessions/stale.jsonl" <<'EOF'
{}
EOF
cat > "$TMP_HOME/.openclaw/cron/jobs.json" <<'EOF'
{"jobs":[{"name":"old-job","enabled":true}]}
EOF
PATH="$TMP_BIN:$PATH" HOME="$TMP_HOME" OPENCLAW_LOG_FILE="$TMP_ROOT/openclaw.log" bash "$TMP_REPO/scripts/setup.sh" >/dev/null
PATH="$TMP_BIN:$PATH" HOME="$TMP_HOME" CLAWOSS_SMOKE_MODE=1 OPENCLAW_LOG_FILE="$TMP_ROOT/openclaw.log" bash "$TMP_REPO/scripts/restart.sh" >/dev/null

test -f "$TMP_HOME/.openclaw/openclaw.json"
test -f "$TMP_REPO/workspace/memory/impl-spawn-state.md"
grep -q 'gateway install' "$TMP_ROOT/openclaw.log"
if grep -q '/subagents kill all' "$TMP_ROOT/openclaw.log"; then
  echo "smoke mode should not emit live subagent kill event" >&2
  exit 1
fi

echo "Restart smoke mode is runnable."
