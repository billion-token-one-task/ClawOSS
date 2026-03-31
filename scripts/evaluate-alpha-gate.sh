#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
if [ -z "$ACTION" ]; then
  echo "Usage: evaluate-alpha-gate.sh <pr_submit|followup_push|strategy_promotion> [options]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"
CONFIG_PATH="$PROJECT_DIR/config/alpha-gates.json"
TRUST_FILE="$WORKSPACE_DIR/memory/trust-repos.md"
QUEUE_FILE="$WORKSPACE_DIR/memory/human-review-queue.md"

REPO=""
PR_TYPE=""
DIFF_LINES=""
FOLLOWUP_ROUND=""
STRATEGY_VERSION=""
REASONING_SUMMARY=""
RECORD=0

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr-type) PR_TYPE="${2:-}"; shift 2 ;;
    --diff-lines) DIFF_LINES="${2:-}"; shift 2 ;;
    --followup-round) FOLLOWUP_ROUND="${2:-}"; shift 2 ;;
    --strategy-version) STRATEGY_VERSION="${2:-}"; shift 2 ;;
    --reasoning-summary) REASONING_SUMMARY="${2:-}"; shift 2 ;;
    --record) RECORD=1; shift ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$QUEUE_FILE")"
if [ ! -f "$QUEUE_FILE" ]; then
  cat > "$QUEUE_FILE" <<'EOF'
# Human Review Queue

| created_at | action | repo | decision | reasons | context |
|------------|--------|------|----------|---------|---------|
EOF
fi

JSON_OUTPUT=$(
python3 - "$ACTION" "$CONFIG_PATH" "$TRUST_FILE" "$REPO" "$PR_TYPE" "$DIFF_LINES" "$FOLLOWUP_ROUND" "$STRATEGY_VERSION" "$REASONING_SUMMARY" <<'PY'
import json, sys, re
from pathlib import Path

action, config_path, trust_path, repo, pr_type, diff_lines, followup_round, strategy_version, reasoning = sys.argv[1:]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

active_scores = {}
deprioritized = set()
trust_file = Path(trust_path)
if trust_file.exists():
    section = None
    for raw_line in trust_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        lower = line.lower()
        if lower.startswith("## active"):
            section = "active"
            continue
        if lower.startswith("## deprioritized"):
            section = "deprioritized"
            continue
        if not line.startswith("| `"):
            continue
        parts = [p.strip() for p in line.strip("|").split("|")]
        if len(parts) < 2:
            continue
        repo_name = parts[0].strip("` ")
        if section == "active":
            try:
                active_scores[repo_name] = int(parts[1])
            except ValueError:
                active_scores[repo_name] = 0
        elif section == "deprioritized":
            deprioritized.add(repo_name)

reasons = []
decision = "auto"
trust_score = active_scores.get(repo)
is_trusted = trust_score is not None and trust_score >= int(config["submit"]["min_trust_score_auto"])
is_deprioritized = repo in deprioritized

if action == "strategy_promotion":
    if config.get("strategy", {}).get("promotion_requires_human", True):
        decision = "review"
        reasons.append("strategy promotion requires human approval in alpha mode")
elif action == "pr_submit":
    ptype = pr_type or "unknown"
    diff = int(diff_lines or "0")
    submit_cfg = config["submit"]
    auto_types = set(submit_cfg.get("auto_pr_types", []))
    if is_deprioritized:
      decision = "review"
      reasons.append("repo is deprioritized")
    if ptype == "bugfix" and submit_cfg.get("require_trusted_repo_for_bugfix", True) and not is_trusted:
        decision = "review"
        reasons.append("bugfix auto-submit requires a trusted repo")
    if ptype in auto_types and diff > int(submit_cfg.get("max_diff_lines_auto", 80)):
        decision = "review"
        reasons.append("diff is larger than alpha auto-submit threshold")
    if ptype == "bugfix" and diff > int(submit_cfg.get("max_diff_lines_bugfix_auto", 40)):
        decision = "review"
        reasons.append("bugfix diff is larger than alpha auto-submit threshold")
    if ptype not in auto_types and ptype != "bugfix":
        decision = "review"
        reasons.append("PR type is outside the alpha auto-submit set")
elif action == "followup_push":
    diff = int(diff_lines or "0")
    round_num = int(followup_round or "1")
    follow_cfg = config["followup"]
    if is_deprioritized:
      decision = "review"
      reasons.append("repo is deprioritized")
    if round_num > int(follow_cfg.get("max_round_auto", 2)):
        decision = "review"
        reasons.append("follow-up round exceeds alpha auto-push threshold")
    if diff > int(follow_cfg.get("max_diff_lines_auto", 120)):
        decision = "review"
        reasons.append("follow-up diff exceeds alpha auto-push threshold")
else:
    raise SystemExit(f"Unsupported action: {action}")

result = {
    "action": action,
    "decision": decision,
    "repo": repo or None,
    "pr_type": pr_type or None,
    "diff_lines": int(diff_lines) if diff_lines else None,
    "followup_round": int(followup_round) if followup_round else None,
    "strategy_version": strategy_version or None,
    "trust_score": trust_score,
    "is_trusted": bool(is_trusted),
    "is_deprioritized": bool(is_deprioritized),
    "reasons": reasons,
    "reasoning_summary": reasoning or None,
}
print(json.dumps(result))
PY
)

if [ "$RECORD" -eq 1 ]; then
  _PAYLOAD="$JSON_OUTPUT" python3 - "$QUEUE_FILE" <<'PY'
import json, sys, datetime, os

queue_file = sys.argv[1]
payload = json.loads(os.environ["_PAYLOAD"])
if payload.get("decision") != "review":
    raise SystemExit(0)

created_at = datetime.datetime.now(datetime.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
reasons = "; ".join(payload.get("reasons") or []) or "manual review requested"
context_bits = []
if payload.get("pr_type"):
    context_bits.append(f"type={payload['pr_type']}")
if payload.get("diff_lines") is not None:
    context_bits.append(f"diff={payload['diff_lines']}")
if payload.get("followup_round") is not None:
    context_bits.append(f"round={payload['followup_round']}")
if payload.get("strategy_version"):
    context_bits.append(f"strategy={payload['strategy_version']}")
if payload.get("reasoning_summary"):
    context_bits.append(payload["reasoning_summary"])
context = " | ".join(context_bits) if context_bits else "n/a"

with open(queue_file, "a", encoding="utf-8") as f:
    f.write(f"| {created_at} | {payload['action']} | {payload.get('repo') or '-'} | review | {reasons} | {context} |\n")
PY
fi

printf '%s\n' "$JSON_OUTPUT"
