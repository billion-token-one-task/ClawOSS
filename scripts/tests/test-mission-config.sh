#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MISSION="$ROOT/config/mission.json"

jq -e '
  .mission_id != null and
  .goal != null and
  .success_criteria != null and
  .constraints != null and
  .work_units != null and
  .gates != null and
  .situation_snapshot != null and
  .session_strategy != null and
  (.work_units.discover.output.file == "workspace/memory/candidates.json") and
  (.work_units.select.output.file == "workspace/memory/task-envelope.json") and
  (.work_units.implement.output.file == "workspace/memory/last-result.json") and
  (.work_units.implement.output.required_fields | index("repo_path")) != null and
  (.work_units.submit.output.file == "workspace/memory/pr-info.json") and
  (.work_units.followup.output.file == "workspace/memory/followup-result.json") and
  (.work_units.reflect.output.file == "workspace/memory/reflection-result.json") and
  (.gates.task_admission.checks | index("dedup_ledger")) != null and
  (.gates.pre_submit.checks | index("diff_size")) != null and
  (.gates.post_submit.checks | index("pr_exists")) != null and
  (.constraints.resource_limits.max_pr_size_lines == 200) and
  (.session_strategy.default_timeout_seconds == 900)
' "$MISSION" >/dev/null

echo "mission.json contract is valid."
