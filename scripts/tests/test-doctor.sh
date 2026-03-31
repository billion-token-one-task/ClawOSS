#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT=$(bash "$ROOT/scripts/doctor.sh" --json)

echo "$OUTPUT" | jq . >/dev/null
echo "$OUTPUT" | jq -e '
  .overall != null and
  .project_dir != null and
  .workspace_dir != null and
  .checks.files.alpha_gate_config != null and
  .checks.commands.openclaw != null and
  .checks.auth.github != null and
  .checks.workspace_bootstrap != null and
  .checks.validate != null and
  .checks.portability != null
' >/dev/null

echo "doctor.sh JSON output is valid."
