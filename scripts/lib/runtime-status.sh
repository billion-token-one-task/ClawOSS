#!/usr/bin/env bash

clawoss_runtime_status_file() {
    local workspace_dir="$1"
    echo "$workspace_dir/runtime/service-status.json"
}

clawoss_write_runtime_status() {
    local workspace_dir="$1"
    local overall="$2"
    local gateway="$3"
    local dashboard_sync="$4"
    local run_cycle="$5"
    local agent_registered="$6"
    local workspace_linked="$7"
    local health="$8"
    local note="${9:-}"
    local source="${10:-unknown}"
    local status_file

    status_file="$(clawoss_runtime_status_file "$workspace_dir")"
    mkdir -p "$(dirname "$status_file")"

    STATUS_FILE="$status_file" \
    STATUS_OVERALL="$overall" \
    STATUS_GATEWAY="$gateway" \
    STATUS_DASHBOARD_SYNC="$dashboard_sync" \
    STATUS_RUN_CYCLE="$run_cycle" \
    STATUS_AGENT_REGISTERED="$agent_registered" \
    STATUS_WORKSPACE_LINKED="$workspace_linked" \
    STATUS_HEALTH="$health" \
    STATUS_NOTE="$note" \
    STATUS_SOURCE="$source" \
    python3 -c "
import json, os
from datetime import datetime, timezone

def as_bool(value):
    return str(value).lower() in ('1', 'true', 'yes', 'on')

existing = {}
try:
    with open(os.environ['STATUS_FILE'], 'r', encoding='utf-8') as fh:
        existing = json.load(fh)
except (FileNotFoundError, json.JSONDecodeError, OSError):
    existing = {}

gateway = os.environ['STATUS_GATEWAY']
if gateway == 'unknown' and existing.get('gateway'):
    gateway = existing['gateway']

dashboard_sync = os.environ['STATUS_DASHBOARD_SYNC']
if dashboard_sync == 'unknown' and existing.get('dashboardSync'):
    dashboard_sync = existing['dashboardSync']

run_cycle = os.environ['STATUS_RUN_CYCLE']
if run_cycle == 'unknown' and existing.get('runCycle'):
    run_cycle = existing['runCycle']

health = os.environ['STATUS_HEALTH']
if health == 'unknown' and existing.get('health'):
    health = existing['health']

payload = {
    'updatedAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    'source': os.environ['STATUS_SOURCE'],
    'overall': os.environ['STATUS_OVERALL'],
    'gateway': gateway,
    'dashboardSync': dashboard_sync,
    'runCycle': run_cycle,
    'agentRegistered': as_bool(os.environ['STATUS_AGENT_REGISTERED']),
    'workspaceLinked': as_bool(os.environ['STATUS_WORKSPACE_LINKED']),
    'health': health,
    'note': os.environ.get('STATUS_NOTE', ''),
}

with open(os.environ['STATUS_FILE'], 'w', encoding='utf-8') as fh:
    json.dump(payload, fh, indent=2)
    fh.write('\n')
"
}
