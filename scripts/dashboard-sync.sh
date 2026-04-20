#!/bin/bash
# dashboard-sync.sh — Polls local session files every 10 seconds
# and POSTs heartbeat + latest conversation messages to the dashboard.
# Reads sessions.json to identify subagent sessions and their labels.
# Bypasses OpenClaw hooks entirely — pure filesystem polling.
#
# Features:
#   - PID lock file prevents duplicate instances
#   - Self-updates: watches its own script file and restarts on change
#   - Stale lock cleanup on startup
#
# Usage: nohup bash scripts/dashboard-sync.sh > /tmp/dashboard-sync.log 2>&1 &

URL="${DASHBOARD_URL:-https://clawoss-dashboard.vercel.app}"
KEY="${CLAW_API_KEY:?Set CLAW_API_KEY env var}"
# Sessions dir: check for the clawoss agent sessions, with fallback
if [ -d "$HOME/.openclaw/agents/clawoss/sessions" ]; then
  DIR="$HOME/.openclaw/agents/clawoss/sessions"
else
  # Fallback: scan for any agent dir that has session files
  DIR="$HOME/.openclaw/agents/clawoss/sessions"
  mkdir -p "$DIR" 2>/dev/null || true
fi
INTERVAL=10
# Use persistent offset dir under workspace to survive reboots (not /tmp)
SYNC_STATE_DIR="${CLAWOSS_WORKSPACE:-$HOME/clawOSS/workspace}/.sync-state"
OFFSET_DIR="${SYNC_STATE_DIR}/offsets"
SESSION_MAP="${SYNC_STATE_DIR}/session-map.json"
LOCK_FILE="${SYNC_STATE_DIR}/dashboard-sync.pid"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
mkdir -p "$OFFSET_DIR" "$SYNC_STATE_DIR"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# --- PID lock: prevent duplicate instances ---
if [ -f "$LOCK_FILE" ]; then
  OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    # Another instance is genuinely running — check if it's actually this script
    OLD_CMD=$(ps -p "$OLD_PID" -o command= 2>/dev/null)
    if echo "$OLD_CMD" | grep -q "dashboard-sync"; then
      log "Another instance running (PID $OLD_PID). Exiting."
      exit 0
    fi
  fi
  log "Stale lock file found (PID $OLD_PID). Cleaning up."
  rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; exit' EXIT INT TERM

# --- Self-update: record script checksum at startup ---
script_checksum() { md5 -q "$SCRIPT_PATH" 2>/dev/null || md5sum "$SCRIPT_PATH" 2>/dev/null | cut -d' ' -f1; }
STARTUP_CHECKSUM=$(script_checksum)

# Build session metadata map from sessions.json
# Maps sessionId -> {isSubagent, label, spawnedBy}
build_session_map() {
  local sessions_file="$DIR/sessions.json"
  [ ! -f "$sessions_file" ] && echo '{}' > "$SESSION_MAP" && return

  _SESSIONS_FILE="$sessions_file" python3 -c "
import json, sys, os
try:
    data = json.load(open(os.environ['_SESSIONS_FILE']))
    result = {}
    for key, meta in data.items():
        sid = meta.get('sessionId', '')
        if not sid:
            continue
        is_sub = 'subagent' in key
        result[sid] = {
            'isSubagent': is_sub,
            'label': meta.get('label', ''),
            'spawnedBy': meta.get('spawnedBy', ''),
            'spawnDepth': meta.get('spawnDepth', 0),
            'subagentRole': meta.get('subagentRole', ''),
            'sessionKey': key
        }
    json.dump(result, sys.stdout)
except (json.JSONDecodeError, ValueError, AttributeError, TypeError, FileNotFoundError):
    print('{}', file=sys.stdout)
" > "$SESSION_MAP" 2>/dev/null
}

log "dashboard-sync started (interval=${INTERVAL}s)"
log "Watching: ${DIR}"
log "Posting to: ${URL}"

# Build initial session map
build_session_map
log "Session map built: $(_SESSION_MAP="$SESSION_MAP" python3 -c "import json, os; d=json.load(open(os.environ['_SESSION_MAP'])); subs=[v for v in d.values() if v['isSubagent']]; print(f'{len(d)} sessions, {len(subs)} subagents')" 2>/dev/null || echo 'error')"

CYCLE=0

while true; do

  # --- Budget guard ---
  if [ -n "${TOKEN_BUDGET_USD:-}" ] && [ "${TOKEN_BUDGET_USD}" != "0" ]; then
    TOTAL_COST=$(curl -s -m 5 \
      -H "Authorization: Bearer $KEY" \
      "$URL/api/metrics/overview" 2>/dev/null | \
      python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('stats',{}).get('totalCostAllTime',0))
except:
    print(0)
" 2>/dev/null || echo "0")

    OVER_BUDGET=$(python3 -c "
try:
    over = float('$TOTAL_COST') >= float('$TOKEN_BUDGET_USD')
    print('yes' if over else 'no')
except:
    print('no')
" 2>/dev/null || echo "no")

    if [ "$OVER_BUDGET" = "yes" ]; then
      log "BUDGET EXCEEDED: spent=\$$TOTAL_COST budget=\$$TOKEN_BUDGET_USD — stopping gateway"
      curl -s -m 5 -X POST "$URL/api/ingest/heartbeat" \
        -H "Authorization: Bearer $KEY" \
        -H "Content-Type: application/json" \
        -d "{\"status\":\"offline\",\"currentTask\":\"BUDGET EXCEEDED: spent \$$TOTAL_COST of \$$TOKEN_BUDGET_USD\"}" \
        >/dev/null 2>&1
      openclaw gateway stop 2>/dev/null || true
      sleep "${BUDGET_CHECK_INTERVAL:-60}"
      continue
    fi
  fi

  CYCLE=$((CYCLE + 1))

  # --- Self-update check every 6 cycles (60 seconds) ---
  if [ $((CYCLE % 6)) -eq 0 ]; then
    CURRENT_CHECKSUM=$(script_checksum)
    if [ -n "$CURRENT_CHECKSUM" ] && [ "$CURRENT_CHECKSUM" != "$STARTUP_CHECKSUM" ]; then
      log "Script changed on disk (was $STARTUP_CHECKSUM, now $CURRENT_CHECKSUM). Restarting..."
      rm -f "$LOCK_FILE"
      exec bash "$SCRIPT_PATH"
    fi
  fi

  # Rebuild session map every 6 cycles (60 seconds) to pick up new sessions
  if [ $((CYCLE % 6)) -eq 1 ]; then
    build_session_map
  fi

  # PR Ledger sync handled by launchd (com.clawoss.pr-ledger-sync) every 60s

  # --- Heartbeat ---
  LOCKS=$(ls "$DIR"/*.lock 2>/dev/null | wc -l | tr -d ' ')
  SESSIONS=$(ls "$DIR"/*.jsonl 2>/dev/null | grep -v '.reset.' | wc -l | tr -d ' ')
  BYTES=$(cat "$DIR"/*.jsonl 2>/dev/null | wc -c | tr -d ' ')

  if [ "$LOCKS" -gt 0 ]; then
    ST="alive"
  elif [ "$SESSIONS" -gt 0 ]; then
    ST="degraded"
  else
    ST="offline"
  fi

  METADATA=$(jq -n \
    --argjson sessions "$SESSIONS" \
    --argjson active "$LOCKS" \
    --argjson totalBytes "${BYTES:-0}" \
    --arg source "dashboard-sync.sh" \
    '{sessionCount:$sessions, activeCount:$active, totalBytes:$totalBytes, source:$source}' 2>/dev/null || echo '{}')

  curl -s -m 8 -X POST "$URL/api/ingest/heartbeat" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg status "$ST" \
      --arg currentTask "${SESSIONS} sessions, ${LOCKS} active, ${BYTES}B total" \
      --argjson metadata "$METADATA" \
      '{status:$status, currentTask:$currentTask, metadata:$metadata}')" > /dev/null 2>&1

  log "heartbeat: status=$ST sessions=$SESSIONS active=$LOCKS bytes=$BYTES"

  # --- State sync every 6 cycles (60 seconds) ---
  if [ $((CYCLE % 6)) -eq 0 ]; then
    STATE_PAYLOAD=$(jq -n \
      --argjson sessions "$SESSIONS" \
      --argjson active "$LOCKS" \
      --arg status "$ST" \
      '{
        workQueue: [],
        pipelineState: {status: $status, activeSessions: $active, totalSessions: $sessions},
        activeRepos: [],
        metadata: {source: "dashboard-sync.sh"}
      }')
    curl -s -m 8 -X POST "$URL/api/ingest/state" \
      -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d "$STATE_PAYLOAD" > /dev/null 2>&1
    log "state-sync: posted"
  fi

  # --- Token metrics: extract usage data from JSONL and POST to /api/ingest/metrics ---
  for f in "$DIR"/*.jsonl; do
    [ ! -f "$f" ] && continue
    bn=$(basename "$f")
    echo "$bn" | grep -q '\.reset\.' && continue
    [ "$bn" = "sessions.json" ] && continue

    SID=$(basename "$f" .jsonl)
    TOKEN_OFFSET_FILE="$OFFSET_DIR/${SID}.token-offset"

    TOTAL_LINES=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ -z "$TOTAL_LINES" ] && continue

    TOKEN_PREV=0
    [ -f "$TOKEN_OFFSET_FILE" ] && TOKEN_PREV=$(cat "$TOKEN_OFFSET_FILE" 2>/dev/null | tr -d ' ')
    [ -z "$TOKEN_PREV" ] && TOKEN_PREV=0

    [ "$TOTAL_LINES" -le "$TOKEN_PREV" ] && { echo "$TOTAL_LINES" > "$TOKEN_OFFSET_FILE"; continue; }

    NEW_COUNT=$((TOTAL_LINES - TOKEN_PREV))
    [ "$NEW_COUNT" -gt 200 ] && NEW_COUNT=200 && TOKEN_PREV=$((TOTAL_LINES - 200))

    METRICS_PAYLOAD=$(tail -n "$NEW_COUNT" "$f" 2>/dev/null | _SID="$SID" python3 -c "
import json, sys, os
sid = os.environ['_SID']
metrics = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except (json.JSONDecodeError, ValueError):
        continue
    if e.get('type') != 'message':
        continue
    m = e.get('message', {})
    usage = m.get('usage', e.get('usage', {}))
    if not usage:
        continue
    # OpenClaw JSONL format uses 'input'/'output' (short names)
    # Also support 'input_tokens'/'inputTokens' for other formats
    inp = usage.get('input', 0) or usage.get('input_tokens', 0) or usage.get('inputTokens', 0) or 0
    out = usage.get('output', 0) or usage.get('output_tokens', 0) or usage.get('outputTokens', 0) or 0
    if inp == 0 and out == 0:
        continue
    model = m.get('model', e.get('model', ''))
    metrics.append({
        'inputTokens': inp,
        'outputTokens': out,
        'model': model or os.environ.get('LLM_MODEL', 'unknown'),
        'channel': sid
    })
if metrics:
    print(json.dumps({'metrics': metrics}))
" 2>/dev/null)

    if [ -n "$METRICS_PAYLOAD" ]; then
      RESULT=$(curl -s -m 8 -X POST "$URL/api/ingest/metrics" \
        -H "Authorization: Bearer $KEY" \
        -H "Content-Type: application/json" \
        -d "$METRICS_PAYLOAD" 2>/dev/null)
      log "token-metrics: session=$SID result=$RESULT"
    fi

    echo "$TOTAL_LINES" > "$TOKEN_OFFSET_FILE"
  done

  # --- Conversation sync: tail new lines from each session file ---
  for f in "$DIR"/*.jsonl; do
    [ ! -f "$f" ] && continue
    bn=$(basename "$f")
    echo "$bn" | grep -q '\.reset\.' && continue
    [ "$bn" = "sessions.json" ] && continue

    SID=$(basename "$f" .jsonl)
    OFFSET_FILE="$OFFSET_DIR/$SID.offset"

    TOTAL_LINES=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ -z "$TOTAL_LINES" ] && continue

    PREV=0
    [ -f "$OFFSET_FILE" ] && PREV=$(cat "$OFFSET_FILE" 2>/dev/null | tr -d ' ')
    [ -z "$PREV" ] && PREV=0

    [ "$TOTAL_LINES" -le "$PREV" ] && { echo "$TOTAL_LINES" > "$OFFSET_FILE"; continue; }

    NEW_COUNT=$((TOTAL_LINES - PREV))
    [ "$NEW_COUNT" -gt 50 ] && NEW_COUNT=50 && PREV=$((TOTAL_LINES - 50))

    tail -n "$NEW_COUNT" "$f" 2>/dev/null | _SESSION_MAP="$SESSION_MAP" _SID="$SID" python3 -c "
import json, sys, os

# Load session metadata map
try:
    session_map = json.load(open(os.environ['_SESSION_MAP']))
except (json.JSONDecodeError, FileNotFoundError, KeyError):
    session_map = {}

sid = os.environ['_SID']
meta_info = session_map.get(sid, {})
is_subagent = meta_info.get('isSubagent', False)
label = meta_info.get('label', '')
spawned_by = meta_info.get('spawnedBy', '')

# Role mapping: OpenClaw JSONL uses camelCase, dashboard expects snake_case
ROLE_MAP = {
    'user': 'user',
    'assistant': 'assistant',
    'system': 'system',
    'toolResult': 'tool_result',
    'tool_result': 'tool_result',
    'tool_call': 'tool_call',
}

def parse_content_blocks(blocks):
    \"\"\"Parse OpenClaw content block array into text + tool info.

    Block types in OpenClaw JSONL:
    - {type: 'text', text: '...'}
    - {type: 'thinking', thinking: '...', thinkingSignature: '...'}
    - {type: 'toolCall', id: '...', name: '...', arguments: {...}}
    - {type: 'tool_use', name: '...', input: {...}}  (alternate format)
    - {type: 'tool_result', content: '...' or [...]}
    \"\"\"
    text_parts = []
    tool_names = []
    has_thinking = False
    duration_ms = None

    for b in blocks:
        bt = b.get('type', '')

        if bt == 'text':
            t = b.get('text', '')
            if t:
                text_parts.append(t[:600])

        elif bt == 'thinking':
            has_thinking = True
            # Don't include thinking content (too long, private)

        elif bt in ('toolCall', 'tool_use'):
            name = b.get('name', '') or b.get('tool', '')
            tool_names.append(name)
            # Include tool name and brief args summary
            args = b.get('arguments', b.get('input', {}))
            if isinstance(args, dict):
                # Show just the first key-value for context
                for k, v in list(args.items())[:1]:
                    sv = str(v)[:200]
                    text_parts.append(f'[TOOL:{name}] {k}={sv}')
                    break
                else:
                    text_parts.append(f'[TOOL:{name}]')
            elif isinstance(args, str):
                text_parts.append(f'[TOOL:{name}] {args[:200]}')
            else:
                text_parts.append(f'[TOOL:{name}]')

        elif bt == 'tool_result':
            inner = b.get('content', '')
            if isinstance(inner, list):
                for ib in inner:
                    if ib.get('type') == 'text':
                        text_parts.append(ib.get('text', '')[:400])
            elif isinstance(inner, str):
                text_parts.append(inner[:400])

    return text_parts, tool_names, has_thinking

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except (json.JSONDecodeError, ValueError):
        continue
    if e.get('type') != 'message':
        continue
    m = e.get('message', {})
    raw_role = m.get('role', '')
    role = ROLE_MAP.get(raw_role, raw_role)
    c = m.get('content', '')
    tool_name = None
    duration_ms = None

    if isinstance(c, list):
        text_parts, tool_names, has_thinking = parse_content_blocks(c)
        c = '\\n'.join(text_parts) if text_parts else ''
        if tool_names:
            tool_name = tool_names[0]

        # If assistant message has toolCall blocks but no text, it's a tool_call
        if role == 'assistant' and tool_names and not any(
            b.get('type') == 'text' and b.get('text', '').strip()
            for b in m.get('content', [])
        ):
            role = 'tool_call'

        # If assistant has only thinking + toolCalls, still tool_call
        if role == 'assistant' and tool_names and has_thinking and not text_parts:
            role = 'tool_call'
            c = ', '.join(f'[TOOL:{n}]' for n in tool_names)

    if isinstance(c, str):
        c = c[:1000]

    # Skip empty messages
    if not c.strip() and role != 'system':
        continue

    # Build metadata with subagent info
    msg_metadata = {}
    if is_subagent:
        msg_metadata['isSubagent'] = True
        if label:
            msg_metadata['label'] = label
            if '#' in label:
                parts = label.split('#', 1)
                msg_metadata['repo'] = parts[0]
                msg_metadata['issue'] = '#' + parts[1].split('-')[0]
        if spawned_by:
            msg_metadata['spawnedBy'] = spawned_by

    payload = {
        'sessionId': sid,
        'role': role,
        'content': c
    }
    if tool_name:
        payload['toolName'] = tool_name
    if msg_metadata:
        payload['metadata'] = msg_metadata
    print(json.dumps(payload))
" 2>/dev/null | while read -r MSG; do
      [ -z "$MSG" ] && continue
      curl -s -m 5 -X POST "$URL/api/ingest/conversation" \
        -H "Authorization: Bearer $KEY" \
        -H "Content-Type: application/json" \
        -d "$MSG" > /dev/null 2>&1
    done

    echo "$TOTAL_LINES" > "$OFFSET_FILE"
  done

  sleep "$INTERVAL"
done
