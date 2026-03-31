#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
WORKSPACE_DIR="$(clawoss_resolve_workspace_dir "$0")"

OUTPUT_MODE="text"
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json) OUTPUT_MODE="json" ;;
    --strict) STRICT=1 ;;
    --help)
      cat <<'EOF'
Usage: bash scripts/doctor.sh [--json] [--strict]

Checks local reproducibility prerequisites and configuration health.
--json    Output machine-readable JSON
--strict  Exit non-zero if any critical check fails
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_DIR/.env"
  set +a
  ENV_FILE_PRESENT=true
else
  ENV_FILE_PRESENT=false
fi

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'true'
  else
    printf 'false'
  fi
}

run_check() {
  set +e
  local output
  output=$("$@" 2>&1)
  local exit_code=$?
  set -e

  printf '%s\n__EXIT__=%s\n' "$output" "$exit_code"
}

OPENCLAW_READY=$(check_cmd openclaw)
GH_READY=$(check_cmd gh)
NODE_READY=$(check_cmd node)
JQ_READY=$(check_cmd jq)
PYTHON_READY=$(check_cmd python3)
ALPHA_GATE_CONFIG_READY=$([ -f "$PROJECT_DIR/config/alpha-gates.json" ] && echo true || echo false)

if [ -n "${MINIMAX_API_KEY:-}" ] || [ -n "${KIMI_API_KEY:-}" ]; then
  MODEL_AUTH_READY=true
else
  MODEL_AUTH_READY=false
fi

if [ -n "${GITHUB_TOKEN:-}" ] || gh auth status >/dev/null 2>&1; then
  GITHUB_AUTH_READY=true
else
  GITHUB_AUTH_READY=false
fi

INIT_RESULT=$(run_check bash "$SCRIPT_DIR/init-workspace-state.sh")
INIT_OUTPUT=$(printf '%s\n' "$INIT_RESULT" | sed '$d')
INIT_EXIT=$(printf '%s\n' "$INIT_RESULT" | tail -n1 | cut -d= -f2)

VALIDATE_RESULT=$(run_check node "$SCRIPT_DIR/validate-config.mjs")
VALIDATE_OUTPUT=$(printf '%s\n' "$VALIDATE_RESULT" | sed '$d')
VALIDATE_EXIT=$(printf '%s\n' "$VALIDATE_RESULT" | tail -n1 | cut -d= -f2)

PORTABILITY_RESULT=$(run_check bash "$SCRIPT_DIR/tests/test-portability.sh")
PORTABILITY_OUTPUT=$(printf '%s\n' "$PORTABILITY_RESULT" | sed '$d')
PORTABILITY_EXIT=$(printf '%s\n' "$PORTABILITY_RESULT" | tail -n1 | cut -d= -f2)

OVERALL="healthy"
if [ "$OPENCLAW_READY" != true ] || [ "$GH_READY" != true ] || [ "$NODE_READY" != true ] || [ "$JQ_READY" != true ] || [ "$PYTHON_READY" != true ]; then
  OVERALL="degraded"
fi
if [ "$MODEL_AUTH_READY" != true ] || [ "$GITHUB_AUTH_READY" != true ]; then
  OVERALL="degraded"
fi
if [ "$INIT_EXIT" -ne 0 ] || [ "$VALIDATE_EXIT" -ne 0 ] || [ "$PORTABILITY_EXIT" -ne 0 ]; then
  OVERALL="degraded"
fi
if [ "$ALPHA_GATE_CONFIG_READY" != true ]; then
  OVERALL="degraded"
fi

if [ "$OUTPUT_MODE" = "json" ]; then
  jq -n \
    --arg overall "$OVERALL" \
    --arg projectDir "$PROJECT_DIR" \
    --arg workspaceDir "$WORKSPACE_DIR" \
    --argjson envFilePresent "$ENV_FILE_PRESENT" \
    --argjson openclaw "$OPENCLAW_READY" \
    --argjson gh "$GH_READY" \
    --argjson node "$NODE_READY" \
    --argjson jqok "$JQ_READY" \
    --argjson python "$PYTHON_READY" \
    --argjson modelAuth "$MODEL_AUTH_READY" \
    --argjson githubAuth "$GITHUB_AUTH_READY" \
    --argjson workspaceBootstrap "$([ "$INIT_EXIT" -eq 0 ] && echo true || echo false)" \
    --argjson validate "$([ "$VALIDATE_EXIT" -eq 0 ] && echo true || echo false)" \
    --argjson portability "$([ "$PORTABILITY_EXIT" -eq 0 ] && echo true || echo false)" \
    --argjson alphaGateConfig "$ALPHA_GATE_CONFIG_READY" \
    '{
      overall: $overall,
      project_dir: $projectDir,
      workspace_dir: $workspaceDir,
      env_file_present: $envFilePresent,
      checks: {
        commands: {
          openclaw: $openclaw,
          gh: $gh,
          node: $node,
          jq: $jqok,
          python3: $python
        },
        auth: {
          model_api: $modelAuth,
          github: $githubAuth
        },
        files: {
          alpha_gate_config: $alphaGateConfig
        },
        workspace_bootstrap: $workspaceBootstrap,
        validate: $validate,
        portability: $portability
      }
    }'
else
  echo "=== ClawOSS Doctor ==="
  echo "Project: $PROJECT_DIR"
  echo "Workspace: $WORKSPACE_DIR"
  echo "Env file: $ENV_FILE_PRESENT"
  echo ""
  echo "Commands:"
  echo "  openclaw: $OPENCLAW_READY"
  echo "  gh: $GH_READY"
  echo "  node: $NODE_READY"
  echo "  jq: $JQ_READY"
  echo "  python3: $PYTHON_READY"
  echo ""
  echo "Auth:"
  echo "  model_api: $MODEL_AUTH_READY"
  echo "  github: $GITHUB_AUTH_READY"
  echo ""
  echo "Checks:"
  echo "  alpha_gate_config: $ALPHA_GATE_CONFIG_READY"
  echo "  workspace_bootstrap: $([ "$INIT_EXIT" -eq 0 ] && echo true || echo false)"
  echo "  validate: $([ "$VALIDATE_EXIT" -eq 0 ] && echo true || echo false)"
  echo "  portability: $([ "$PORTABILITY_EXIT" -eq 0 ] && echo true || echo false)"
  echo ""
  echo "Overall: $OVERALL"
fi

if [ "$STRICT" -eq 1 ] && [ "$OVERALL" != "healthy" ]; then
  exit 1
fi
