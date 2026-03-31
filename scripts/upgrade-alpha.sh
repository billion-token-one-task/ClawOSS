#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/path-helpers.sh"

PROJECT_DIR="$(clawoss_resolve_project_dir "$0")"
DRY_RUN=0
SKIP_TESTS=0
BACKEND_MODE="docker"

usage() {
  cat <<'EOF'
Usage: bash scripts/upgrade-alpha.sh [--dry-run] [--skip-tests] [--no-backend]

Re-validate, refresh backend sidecars, and restart the local alpha deployment
after pulling new code into the repository.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --no-backend) BACKEND_MODE="none" ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

run_compose() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] docker compose %s\n' "$*"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "[INFO] docker not found; skipping backend sidecars"
    return 0
  fi
  docker compose "$@"
}

echo "=== ClawOSS Alpha Upgrade ==="
echo "Project: $PROJECT_DIR"
echo "Backend: $BACKEND_MODE"
echo "Skip tests: $SKIP_TESTS"
echo "Dry run: $DRY_RUN"
echo ""

run_cmd bash "$PROJECT_DIR/scripts/doctor.sh"
run_cmd node "$PROJECT_DIR/scripts/validate-config.mjs"

if [ "$SKIP_TESTS" -ne 1 ]; then
  run_cmd bash "$PROJECT_DIR/scripts/tests/run-all-tests.sh"
  run_cmd bash "$PROJECT_DIR/scripts/tests/test-all-scripts.sh"
  run_cmd bash "$PROJECT_DIR/scripts/tests/test-portability.sh"
  run_cmd bash "$PROJECT_DIR/scripts/tests/test-doctor.sh"
  run_cmd bash "$PROJECT_DIR/scripts/tests/test-autonomy-backend.sh"
fi

run_cmd bash "$PROJECT_DIR/scripts/setup.sh"

if [ "$BACKEND_MODE" = "docker" ]; then
  run_compose up -d --build api worker reflection
fi

run_cmd bash "$PROJECT_DIR/scripts/restart.sh"

echo ""
echo "=== Alpha Upgrade Complete ==="
echo "Health: bash scripts/health-check.sh"
