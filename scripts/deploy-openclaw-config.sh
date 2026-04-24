#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYED_CONFIG="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
    set +a
    echo "[ClawOSS配置] 已加载 .env"
else
    echo "[ClawOSS配置] 未找到 .env，继续使用当前环境变量"
fi

mkdir -p "$(dirname "$DEPLOYED_CONFIG")"

REPO_CONFIG_RESOLVED="$(node "$PROJECT_DIR/scripts/render-openclaw-config.mjs")"

_REPO_CONFIG="$REPO_CONFIG_RESOLVED" \
_DEPLOYED="$DEPLOYED_CONFIG" \
python3 - <<'PY'
import json
import os
from pathlib import Path


def deep_merge(base, override):
    result = dict(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value
    return result


repo_config = json.loads(os.environ["_REPO_CONFIG"])
deployed_path = Path(os.environ["_DEPLOYED"])

try:
    deployed = json.loads(deployed_path.read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    deployed = {}

merged = deep_merge(deployed, repo_config)
deployed_path.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
PY

echo "[ClawOSS配置] 已深度合并到 $DEPLOYED_CONFIG"
