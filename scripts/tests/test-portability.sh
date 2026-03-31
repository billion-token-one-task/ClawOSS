#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGETS=(
  "$ROOT/scripts"
  "$ROOT/workspace"
  "$ROOT/README.md"
  "$ROOT/.env.example"
)

MATCHES=$(rg -n --fixed-strings "/Users/kevinlin/clawOSS" "${TARGETS[@]}" --glob '!scripts/tests/test-portability.sh' || true)

if [ -n "$MATCHES" ]; then
  echo "Found hardcoded workstation paths:"
  echo "$MATCHES"
  exit 1
fi

echo "No hardcoded workstation paths found in active runtime files."
