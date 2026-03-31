#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

DEPLOY_OUTPUT="$(bash "$ROOT/scripts/deploy-alpha.sh" --dry-run --skip-tests 2>&1)"
echo "$DEPLOY_OUTPUT" | grep -q '\[dry-run\] bash .*/scripts/doctor.sh'
echo "$DEPLOY_OUTPUT" | grep -q '\[dry-run\] node .*/scripts/validate-config.mjs'
echo "$DEPLOY_OUTPUT" | grep -q '\[dry-run\] bash .*/scripts/setup.sh'
echo "$DEPLOY_OUTPUT" | grep -q '\[dry-run\] docker compose up -d --build api worker reflection'
echo "$DEPLOY_OUTPUT" | grep -q '\[dry-run\] bash .*/scripts/start.sh'

UPGRADE_OUTPUT="$(bash "$ROOT/scripts/upgrade-alpha.sh" --dry-run --skip-tests --no-backend 2>&1)"
echo "$UPGRADE_OUTPUT" | grep -q '\[dry-run\] bash .*/scripts/doctor.sh'
echo "$UPGRADE_OUTPUT" | grep -q '\[dry-run\] node .*/scripts/validate-config.mjs'
echo "$UPGRADE_OUTPUT" | grep -q '\[dry-run\] bash .*/scripts/setup.sh'
echo "$UPGRADE_OUTPUT" | grep -q '\[dry-run\] bash .*/scripts/restart.sh'
if echo "$UPGRADE_OUTPUT" | grep -q 'docker compose'; then
  echo "upgrade-alpha should not invoke docker compose in --no-backend mode" >&2
  exit 1
fi

echo "Alpha deploy/upgrade wrappers are runnable."
