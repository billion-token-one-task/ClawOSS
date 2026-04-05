#!/usr/bin/env bash
set -euo pipefail

GH_RATE_DIR_DEFAULT="${CLAWOSS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/workspace/.github-rate-limit"
GH_RATE_DIR="${CLAWOSS_GH_RATE_DIR:-$GH_RATE_DIR_DEFAULT}"
GH_RATE_CACHE_DIR="$GH_RATE_DIR/cache"
GH_RATE_STATE_DIR="$GH_RATE_DIR/state"
mkdir -p "$GH_RATE_CACHE_DIR" "$GH_RATE_STATE_DIR"

GH_MIN_INTERVAL_GENERAL_MS="${GH_MIN_INTERVAL_GENERAL_MS:-1200}"
GH_MIN_INTERVAL_SEARCH_MS="${GH_MIN_INTERVAL_SEARCH_MS:-2500}"
GH_WRITE_INTERVAL_MS="${GH_WRITE_INTERVAL_MS:-1200}"
GH_BACKOFF_INITIAL_SECONDS="${GH_BACKOFF_INITIAL_SECONDS:-60}"
GH_MAX_RETRIES="${GH_MAX_RETRIES:-3}"

_gh_rl_now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

_gh_rl_sleep_jitter() {
  python3 - <<'PY'
import random, time
time.sleep(random.uniform(0.5, 1.5))
PY
}

_gh_rl_wait_slot() {
  local lane="$1"
  local min_interval_ms="$2"
  local state_file="$GH_RATE_STATE_DIR/${lane}.ts"
  local now_ms last_ms wait_ms
  now_ms="$(_gh_rl_now_ms)"
  last_ms=0
  if [ -f "$state_file" ]; then
    last_ms=$(cat "$state_file" 2>/dev/null || echo 0)
  fi
  if [[ "$last_ms" =~ ^[0-9]+$ ]]; then
    wait_ms=$(( last_ms + min_interval_ms - now_ms ))
    if [ "$wait_ms" -gt 0 ]; then
      python3 - "$wait_ms" <<'PY'
import sys, time
time.sleep(max(0, int(sys.argv[1])) / 1000.0)
PY
    fi
  fi
  _gh_rl_sleep_jitter
  _gh_rl_now_ms > "$state_file"
}

_gh_rl_hash() {
  python3 - "$@" <<'PY'
import hashlib, sys
print(hashlib.sha256("\n".join(sys.argv[1:]).encode()).hexdigest())
PY
}

_gh_rl_cache_get() {
  local cache_key="$1"
  local ttl_seconds="$2"
  local cache_file="$GH_RATE_CACHE_DIR/${cache_key}.json"
  [ -f "$cache_file" ] || return 1
  python3 - "$cache_file" "$ttl_seconds" <<'PY'
import json, os, sys, time
path = sys.argv[1]
ttl = int(sys.argv[2])
if ttl <= 0:
    raise SystemExit(1)
if time.time() - os.path.getmtime(path) > ttl:
    raise SystemExit(1)
with open(path, "r", encoding="utf-8") as f:
    print(f.read(), end="")
PY
}

_gh_rl_cache_put() {
  local cache_key="$1"
  local payload="$2"
  local cache_file="$GH_RATE_CACHE_DIR/${cache_key}.json"
  printf '%s' "$payload" > "$cache_file"
}

_gh_rl_is_rate_error() {
  local stderr_text="$1"
  grep -Eqi 'secondary rate limit|rate limit|too many requests|http 403|http 429|abuse detection' <<<"$stderr_text"
}

_gh_rl_run_with_backoff() {
  local lane="$1"
  local min_interval_ms="$2"
  shift 2
  local attempt=1
  local backoff="$GH_BACKOFF_INITIAL_SECONDS"
  local stdout_file stderr_file exit_code stderr_text
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  while [ "$attempt" -le "$GH_MAX_RETRIES" ]; do
    _gh_rl_wait_slot "$lane" "$min_interval_ms"
    set +e
    "$@" >"$stdout_file" 2>"$stderr_file"
    exit_code=$?
    set -e
    if [ "$exit_code" -eq 0 ]; then
      cat "$stdout_file"
      rm -f "$stdout_file" "$stderr_file"
      return 0
    fi
    stderr_text="$(cat "$stderr_file" 2>/dev/null || true)"
    if ! _gh_rl_is_rate_error "$stderr_text"; then
      rm -f "$stdout_file" "$stderr_file"
      return "$exit_code"
    fi
    sleep "$backoff"
    backoff=$(( backoff * 2 ))
    attempt=$(( attempt + 1 ))
  done
  rm -f "$stdout_file" "$stderr_file"
  return 1
}

gh_cached_api() {
  local ttl_seconds="$1"
  shift
  local endpoint="$1"
  shift
  local cache_key
  cache_key="$(_gh_rl_hash api "$endpoint" "$*")"
  if _gh_rl_cache_get "$cache_key" "$ttl_seconds" 2>/dev/null; then
    return 0
  fi
  local payload
  if ! payload="$(_gh_rl_run_with_backoff general "$GH_MIN_INTERVAL_GENERAL_MS" gh api "$endpoint" "$@")"; then
    return 1
  fi
  _gh_rl_cache_put "$cache_key" "$payload"
  printf '%s' "$payload"
}

gh_cached_search_prs() {
  local ttl_seconds="$1"
  shift
  local cache_key
  cache_key="$(_gh_rl_hash search_prs "$*")"
  if _gh_rl_cache_get "$cache_key" "$ttl_seconds" 2>/dev/null; then
    return 0
  fi
  local payload
  if ! payload="$(_gh_rl_run_with_backoff search "$GH_MIN_INTERVAL_SEARCH_MS" gh search prs "$@")"; then
    return 1
  fi
  _gh_rl_cache_put "$cache_key" "$payload"
  printf '%s' "$payload"
}

gh_cached_pr_list() {
  local ttl_seconds="$1"
  shift
  local cache_key
  cache_key="$(_gh_rl_hash pr_list "$*")"
  if _gh_rl_cache_get "$cache_key" "$ttl_seconds" 2>/dev/null; then
    return 0
  fi
  local payload
  if ! payload="$(_gh_rl_run_with_backoff general "$GH_MIN_INTERVAL_GENERAL_MS" gh pr list "$@")"; then
    return 1
  fi
  _gh_rl_cache_put "$cache_key" "$payload"
  printf '%s' "$payload"
}

gh_write_with_backoff() {
  _gh_rl_run_with_backoff write "$GH_WRITE_INTERVAL_MS" "$@"
}
