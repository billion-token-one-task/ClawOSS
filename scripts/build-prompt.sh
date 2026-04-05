#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
MEMORY_DIR="$WORKSPACE_DIR/memory"
MISSION_PATH="${MISSION_PATH:-$PROJECT_DIR/config/mission.json}"
WORK_UNIT="${1:-}"

if [ -z "$WORK_UNIT" ]; then
  echo "Usage: build-prompt.sh <work-unit>" >&2
  exit 1
fi

if [ ! -f "$MISSION_PATH" ]; then
  echo "mission file not found: $MISSION_PATH" >&2
  exit 1
fi

work_unit_exists="$(jq -r --arg unit "$WORK_UNIT" '.work_units[$unit] != null' "$MISSION_PATH")"
if [ "$work_unit_exists" != "true" ]; then
  echo "unknown work unit: $WORK_UNIT" >&2
  exit 1
fi

MAX_CHARS="$(jq -r '.situation_snapshot.max_chars // 12000' "$MISSION_PATH")"

truncate_text() {
  local limit="$1"
  python3 -c '
import sys
limit = int(sys.argv[1])
text = sys.stdin.read()
if len(text) <= limit:
    sys.stdout.write(text)
else:
    sys.stdout.write(text[:limit].rstrip() + "\n...[truncated]\n")
' "$limit"
}

print_autonomous_override() {
  cat <<'EOF'
## Autonomous Execution Override
- This run is controller-driven maintenance work, not interactive product design.
- Do not ask the user for approval, clarification, or a design sign-off.
- Ignore any globally loaded brainstorming or spec-writing skill that requires human approval before code changes.
- If a loaded skill conflicts with `AGENTS.md`, `HEARTBEAT.md`, or this prompt, follow `AGENTS.md`, `HEARTBEAT.md`, and this prompt.
- Complete the current work unit end-to-end or write the required failure/result file with concrete evidence.
EOF
}

print_work_unit_directives() {
  local unit="$1"
  case "$unit" in
    implement)
      local repo issue
      repo="$(jq -r '.repo // empty' "$MEMORY_DIR/task-envelope.json" 2>/dev/null || true)"
      issue="$(jq -r '.issue_number // empty' "$MEMORY_DIR/task-envelope.json" 2>/dev/null || true)"
      cat <<EOF
## Work Unit Directives
- You are implementing an already-selected OSS task for \`${repo:-unknown repo}\` issue \`#${issue:-unknown}\`.
- Prepare a disposable repo workspace under \`/tmp/clawoss-${issue:-issue}-<timestamp>\` and do all repo edits and tests there.
- Prefer single-purpose commands that fit the command allowlist. Use \`gh repo clone ${repo:-owner/repo} \$WORKDIR -- --depth=50\` instead of ad-hoc chained clone commands.
- If the cloned repo is a Python project with \`pyproject.toml\` and \`uv.lock\`, bootstrap the test environment before the first pytest run, preferring \`uv sync --group tests\`.
- Create or switch to a mission-compliant branch with prefix \`clawoss/\` in the cloned repo before concluding implementation, and record that branch in \`workspace/memory/last-result.json\`.
- Write the absolute clone path you actually used to \`repo_path\` in \`workspace/memory/last-result.json\`.
- Do not stop because a generic brainstorming skill asks for user approval. This task is already approved by the controller.
- If implementation is blocked, still write \`workspace/memory/last-result.json\` with \`status\` set to a failure value, a concrete \`diff_summary\`, empty or partial \`files_changed/tests_run\`, \`is_ready_to_submit: false\`, and the real blocker in \`risks\`.
- If you determine the issue is not actionable, already fixed, assigned, or superseded, record that conclusion in \`workspace/memory/last-result.json\` instead of asking the user what to do.
EOF
      ;;
    submit)
      cat <<'EOF'
## Work Unit Directives
- This task is already approved for submission if it passed controller gates.
- Do not ask for user approval before pushing or opening the PR.
- Use \`repo_path\` from \`workspace/memory/last-result.json\` as the repo you push from.
- Use the branch recorded in `workspace/memory/last-result.json` or create a mission-compliant `clawoss/*` branch if missing.
- Push without force and write `workspace/memory/pr-info.json` even if submission fails, including the concrete blocker in fields you can populate plus a failure note in available metadata.
EOF
      ;;
    followup)
      cat <<'EOF'
## Work Unit Directives
- This is an autonomous follow-up round on an existing PR.
- Do not ask the user whether to proceed; inspect the PR state, address review feedback if feasible, and write `workspace/memory/followup-result.json`.
EOF
      ;;
  esac
}

print_file_summary() {
  local path="$1"
  local strategy="$2"

  if [ ! -f "$path" ]; then
    printf '(missing) %s\n' "$path"
    return 0
  fi

  case "$strategy" in
    full)
      cat "$path"
      ;;
    tail_20)
      tail -n 20 "$path"
      ;;
    tail_10)
      tail -n 10 "$path"
      ;;
    recent_7d)
      python3 - "$path" <<'PY'
import sys
from datetime import datetime, timedelta, timezone

path = sys.argv[1]
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
lines = []
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        stripped = line.strip()
        if not stripped.startswith("|") or stripped.startswith("| timestamp ") or stripped.startswith("|-----------"):
            continue
        parts = [p.strip() for p in stripped.strip("|").split("|")]
        if not parts:
            continue
        try:
            when = datetime.fromisoformat(parts[0].replace("Z", "+00:00"))
        except ValueError:
            continue
        if when >= cutoff:
            lines.append(line)

if lines:
    print("\n".join(lines))
else:
    print("(no entries in the last 7 days)")
PY
      ;;
    *)
      head -n 40 "$path"
      ;;
  esac
}

printf '# Mission\n'
jq -r '.goal' "$MISSION_PATH"
printf '\n## Success Criteria\n'
jq -r '.success_criteria | to_entries[] | "- \(.key): \(.value)"' "$MISSION_PATH"
printf '\n## Constraints\n'
jq -r '
  .constraints as $c
  | "- scope: \($c.scope)"
  , ($c.safety[] | "- safety: \(.)")
  , "- max_pr_size_lines: \($c.resource_limits.max_pr_size_lines)"
  , "- max_followup_rounds: \($c.resource_limits.max_followup_rounds)"
' "$MISSION_PATH"

printf '\n## Current Lifecycle State\n'
if [ -f "$MEMORY_DIR/lifecycle-state.json" ]; then
  jq . "$MEMORY_DIR/lifecycle-state.json"
else
  printf '(missing) %s\n' "$MEMORY_DIR/lifecycle-state.json"
fi

printf '\n## Work Unit\n'
jq -r --arg unit "$WORK_UNIT" '
  .work_units[$unit] |
  "- name: \($unit)",
  "- maps_to_state: \(.maps_to_state)",
  "- goal: \(.goal_template)"
' "$MISSION_PATH"

printf '\n## Required Inputs\n'
mapfile -t inputs < <(jq -r --arg unit "$WORK_UNIT" '.work_units[$unit].inputs[]? // empty' "$MISSION_PATH")
if [ "${#inputs[@]}" -eq 0 ]; then
  printf '(none)\n'
else
  for input_rel in "${inputs[@]}"; do
    input_abs="$PROJECT_DIR/$input_rel"
    printf '\n### %s\n' "$input_rel"
    print_file_summary "$input_abs" "full" | truncate_text 2500
  done
fi

printf '\n## Situation Snapshot\n'
remaining="$MAX_CHARS"
while IFS=$'\t' read -r key file strategy; do
  [ -z "$key" ] && continue
  file_abs="$PROJECT_DIR/$file"
  printf '\n### %s\n' "$key"
  summary="$(print_file_summary "$file_abs" "$strategy" | truncate_text 2000)"
  printf '%s\n' "$summary"
  remaining=$((remaining - ${#summary}))
  if [ "$remaining" -le 0 ]; then
    printf '\n(snapshot budget exhausted)\n'
    break
  fi
done < <(jq -r '.situation_snapshot.sources[] | [.key, .file, .strategy] | @tsv' "$MISSION_PATH")

printf '\n## Output Contract\n'
jq -r --arg unit "$WORK_UNIT" '
  .work_units[$unit].output
  | "- write_file: \(.file)"
  , (.required_fields[] | "- required_field: \(.)")
' "$MISSION_PATH"

printf '\n## Execution Boundary\n'
printf '%s\n' '- Act on the goal and constraints above.'
printf '%s\n' '- Decide the implementation steps yourself.'
printf '%s\n' '- Persist results to the required output file.'
printf '\n'
print_autonomous_override
printf '\n'
print_work_unit_directives "$WORK_UNIT"
