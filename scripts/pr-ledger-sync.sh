#!/usr/bin/env bash
set -euo pipefail

# pr-ledger-sync.sh — Keeps workspace/memory/pr-ledger.md in sync with GitHub
#
# Two data sources:
#   1. GitHub API: all PRs authored by the configured GitHub account (authoritative for status)
#   2. Subagent result files: picks up PRs before GitHub search indexes them
#
# Can run standalone or be called from dashboard-sync.sh every ~60s.
# Idempotent — safe to run repeatedly.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"
. "$SCRIPT_DIR/lib/github-rate-limit.sh"
PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
LEDGER="$PROJECT_DIR/workspace/memory/pr-ledger.md"
RESULT_DIR="$PROJECT_DIR/workspace/memory"
AGENT_USER="${GITHUB_USERNAME:-${CLAW_AGENT_USERNAME:-clawoss-bot}}"
RECORD_OUTCOMES="${CLAWOSS_RECORD_OUTCOMES:-0}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] pr-ledger-sync: $*"; }

# Ensure gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
    log "ERROR: gh not authenticated, skipping sync"
    exit 1
fi

# --- Collect PRs from GitHub ---
# Search returns all PRs by the agent, sorted by most recent
GH_PRS=$(gh_cached_search_prs 600 --author "$AGENT_USER" --limit 200 \
    --json repository,number,url,state,createdAt 2>/dev/null || echo '[]')

# --- Collect PRs from unprocessed subagent result files ---
# Build result PRs JSON safely via Python (no shell interpolation into code)
RESULT_PRS="[]"
for f in "$RESULT_DIR"/subagent-result-*.md; do
    [ ! -f "$f" ] && continue
    # Extract PR URL from result file (looks for github.com/.../pull/NNN)
    PR_URL=$(grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' "$f" 2>/dev/null | head -1 || true)
    [ -z "$PR_URL" ] && continue

    # Extract repo and issue from the PR URL
    REPO=$(echo "$PR_URL" | sed -E 's|https://github\.com/([^/]+/[^/]+)/pull/.*|\1|')
    PR_NUM=$(echo "$PR_URL" | sed -E 's|.*/pull/([0-9]+)|\1|')

    # Extract issue number from filename (subagent-result-<repo>-<issue>.md)
    BASENAME=$(basename "$f" .md)
    ISSUE_NUM=$(echo "$BASENAME" | grep -oE '[0-9]+$' || echo "")

    # Pass variables via env vars to Python (safe — no interpolation into code)
    RESULT_PRS=$(echo "$RESULT_PRS" | \
        _REPO="$REPO" _ISSUE="$ISSUE_NUM" _PR_URL="$PR_URL" _PR_NUM="$PR_NUM" \
        python3 -c "
import json, sys, os
prs = json.load(sys.stdin)
prs.append({
    'repo': os.environ['_REPO'],
    'issue': os.environ['_ISSUE'],
    'pr_url': os.environ['_PR_URL'],
    'pr_num': os.environ['_PR_NUM'],
    'status': 'open',
    'source': 'result_file'
})
json.dump(prs, sys.stdout)
" 2>/dev/null)

    if [ "$RECORD_OUTCOMES" = "1" ]; then
        BASENAME=$(basename "$f" .md)
        RESULT_JSON=$(_RESULT_FILE="$f" python3 - <<'PY'
import json, os, re
path = os.environ['_RESULT_FILE']
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()
if not text.startswith('---'):
    print('{}')
    raise SystemExit(0)
parts = text.split('---', 2)
if len(parts) < 3:
    print('{}')
    raise SystemExit(0)
frontmatter = {}
for line in parts[1].splitlines():
    if ':' not in line:
        continue
    key, value = line.split(':', 1)
    frontmatter[key.strip()] = value.strip()
print(json.dumps(frontmatter))
PY
)
        STATUS=$(echo "$RESULT_JSON" | jq -r '.status // empty' 2>/dev/null || true)
        TYPE=$(echo "$RESULT_JSON" | jq -r '.type // "implementation"' 2>/dev/null || echo "implementation")
        FAILURE_REASON=$(echo "$RESULT_JSON" | jq -r '.failure_reason // empty' 2>/dev/null || true)
        FILES_CHANGED=$(echo "$RESULT_JSON" | jq -r '.files_changed // empty' 2>/dev/null || true)
        ADDITIONS=$(echo "$RESULT_JSON" | jq -r '.additions // empty' 2>/dev/null || true)
        DELETIONS=$(echo "$RESULT_JSON" | jq -r '.deletions // empty' 2>/dev/null || true)
        ISSUE_VAL=$(echo "$RESULT_JSON" | jq -r '.issue // empty' 2>/dev/null || true)
        if [ -z "$ISSUE_VAL" ]; then ISSUE_VAL="$ISSUE_NUM"; fi
        case "$STATUS" in
            success) OUTCOME_NAME=$([ "$TYPE" = "followup" ] && echo "followup_success" || echo "pr_submitted") ;;
            failure) OUTCOME_NAME=$([ "$TYPE" = "followup" ] && echo "followup_failure" || echo "implementation_failure") ;;
            already_fixed) OUTCOME_NAME="already_fixed_upstream" ;;
            abandoned) OUTCOME_NAME="implementation_abandoned" ;;
            *) OUTCOME_NAME="implementation_result" ;;
        esac
        cmd=(bash "$SCRIPT_DIR/record-outcome.sh" "$OUTCOME_NAME" --id "result-${BASENAME}" --repo "$REPO")
        [ -n "$ISSUE_VAL" ] && cmd+=(--issue "$ISSUE_VAL")
        [ -n "$PR_NUM" ] && cmd+=(--pr "$PR_NUM")
        [ -n "$FAILURE_REASON" ] && cmd+=(--failure-category "$FAILURE_REASON")
        cmd+=(--metadata-json "{\"source\": \"result_file\", \"type\": $(echo "$TYPE" | jq -R .), \"status\": $(echo "$STATUS" | jq -R .), \"files_changed\": ${FILES_CHANGED:-null}, \"additions\": ${ADDITIONS:-null}, \"deletions\": ${DELETIONS:-null}, \"path\": $(echo "$BASENAME" | jq -R .)}")
        "${cmd[@]}" >/dev/null 2>&1 || true
    fi
done

# --- Merge both sources and rebuild ledger ---
# Pass all data via env vars (safe — no shell interpolation into Python code)
_GH_PRS="$GH_PRS" _RESULT_PRS="$RESULT_PRS" _LEDGER="$LEDGER" \
python3 -c "
import json, sys, os
from datetime import datetime

gh_raw = os.environ.get('_GH_PRS', '[]')
result_raw = os.environ.get('_RESULT_PRS', '[]')
ledger_path = os.environ['_LEDGER']

try:
    gh_prs = json.loads(gh_raw)
except (json.JSONDecodeError, ValueError):
    gh_prs = []

try:
    result_prs = json.loads(result_raw)
except (json.JSONDecodeError, ValueError):
    result_prs = []

# Build map keyed by PR URL (authoritative)
pr_map = {}

# First, add GitHub PRs (these have accurate status)
for pr in gh_prs:
    repo = pr.get('repository', {})
    if isinstance(repo, dict):
        repo_name = repo.get('nameWithOwner', '')
    elif isinstance(repo, str):
        repo_name = repo
    else:
        continue

    url = pr.get('url', '')
    if not url:
        continue

    state = pr.get('state', 'OPEN').lower()
    if state == 'merged':
        status = 'merged'
    elif state == 'closed':
        status = 'closed'
    else:
        status = 'open'

    created = pr.get('createdAt', '')
    date = created[:10] if created else datetime.utcnow().strftime('%Y-%m-%d')

    number = pr.get('number', 0)

    pr_map[url] = {
        'repo': repo_name,
        'issue': '',  # populated from result files below
        'pr_url': url,
        'pr_num': number,
        'status': status,
        'date': date,
    }

# Then, merge result file PRs (these have issue numbers)
for rpr in result_prs:
    url = rpr.get('pr_url', '')
    if url in pr_map:
        # Update issue number from result file (GitHub doesn't give us this)
        if rpr.get('issue') and not pr_map[url]['issue']:
            pr_map[url]['issue'] = rpr['issue']
    else:
        # PR not yet in GitHub search -- add it from result file
        date = datetime.utcnow().strftime('%Y-%m-%d')
        pr_map[url] = {
            'repo': rpr.get('repo', ''),
            'issue': rpr.get('issue', ''),
            'pr_url': url,
            'pr_num': rpr.get('pr_num', ''),
            'status': rpr.get('status', 'open'),
            'date': date,
        }

# Also preserve issue numbers from existing ledger (if it exists)
if os.path.exists(ledger_path):
    with open(ledger_path) as f:
        for line in f:
            line = line.strip()
            if not line.startswith('|') or line.startswith('| repo') or line.startswith('|--'):
                continue
            parts = [p.strip() for p in line.split('|')[1:-1]]
            if len(parts) >= 3:
                old_repo, old_issue, old_url = parts[0], parts[1], parts[2]
                if old_url in pr_map and not pr_map[old_url]['issue']:
                    pr_map[old_url]['issue'] = old_issue

# Sort by date descending, then repo
entries = sorted(pr_map.values(), key=lambda x: (x['date'], x['repo']), reverse=True)

# Write ledger
lines = []
lines.append('# PR Ledger — DO NOT submit PRs for issues already in this list')
lines.append('')
lines.append('| repo | issue | pr_url | status | date |')
lines.append('|------|-------|--------|--------|------|')
for e in entries:
    lines.append(f\"| {e['repo']} | {e['issue']} | {e['pr_url']} | {e['status']} | {e['date']} |\")
lines.append('')

with open(ledger_path, 'w') as f:
    f.write('\n'.join(lines))

print(f'Synced {len(entries)} PRs ({sum(1 for e in entries if e[\"status\"]==\"open\")} open, {sum(1 for e in entries if e[\"status\"]==\"merged\")} merged, {sum(1 for e in entries if e[\"status\"]==\"closed\")} closed)')
"

log "$(_LEDGER="$LEDGER" python3 -c "
import os
ledger = os.environ['_LEDGER']
if os.path.exists(ledger):
    lines = [l for l in open(ledger) if l.startswith('|') and not l.startswith('| repo') and not l.startswith('|--')]
    print(f'{len(lines)} entries in ledger')
else:
    print('ledger not found')
" 2>/dev/null)"
