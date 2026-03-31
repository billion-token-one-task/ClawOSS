#!/usr/bin/env bash

clawoss_resolve_project_dir() {
  if [ -n "${PROJECT_DIR:-}" ]; then
    printf '%s\n' "$PROJECT_DIR"
    return 0
  fi

  if [ -n "${CLAWOSS_ROOT:-}" ]; then
    printf '%s\n' "$CLAWOSS_ROOT"
    return 0
  fi

  local source_path="${1:-${BASH_SOURCE[1]}}"
  local source_dir
  source_dir="$(cd "$(dirname "$source_path")" && pwd)"

  case "$(basename "$source_dir")" in
    scripts)
      cd "$source_dir/.." && pwd
      ;;
    lib)
      cd "$source_dir/../.." && pwd
      ;;
    *)
      cd "$source_dir/.." && pwd
      ;;
  esac
}

clawoss_resolve_workspace_dir() {
  if [ -n "${WORKSPACE_DIR:-}" ]; then
    printf '%s\n' "$WORKSPACE_DIR"
    return 0
  fi

  printf '%s/workspace\n' "$(clawoss_resolve_project_dir "${1:-${BASH_SOURCE[1]}}")"
}

clawoss_is_macos() {
  [ "$(uname -s)" = "Darwin" ]
}

clawoss_temp_root() {
  if [ -d /private/tmp ]; then
    printf '/private/tmp\n'
  else
    printf '/tmp\n'
  fi
}
