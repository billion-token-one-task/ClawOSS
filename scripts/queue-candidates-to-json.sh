#!/usr/bin/env bash
set -euo pipefail

QUEUE_FILE="${1:?Usage: queue-candidates-to-json.sh <queue-file.md>}"

python3 - "$QUEUE_FILE" <<'PY'
import json
import re
import sys

path = sys.argv[1]
items = []
pattern = re.compile(
    r"^- \[(?P<score>[^\]]+)\]\s+P\((?P<pmerge>[^\)]+)\)\s+(?P<repo>[^#\s]+)#(?P<issue>\d+):\s+(?P<title>.*?)\s+\|\s+type:(?P<type>[^|]+)\s+\|\s+created:(?P<created>[^|]+)\s+\|\s+direction_aligned:(?P<aligned>[^|]+)\s+\|\s+priority:(?P<priority>.+)$"
)

with open(path, "r", encoding="utf-8") as f:
    for raw_line in f:
        line = raw_line.strip()
        if not line.startswith("- ["):
            continue
        match = pattern.match(line)
        if not match:
            continue
        data = match.groupdict()
        try:
            score = float(data["score"])
        except ValueError:
            score = None
        try:
            pmerge = float(data["pmerge"])
        except ValueError:
            pmerge = None
        items.append(
            {
                "repo": data["repo"],
                "issue": int(data["issue"]),
                "title": data["title"],
                "type": data["type"].strip(),
                "created": data["created"].strip(),
                "directionAligned": data["aligned"].strip().lower() == "yes",
                "priority": data["priority"].strip(),
                "score": score,
                "expectedMergeProb": pmerge / 100.0 if pmerge is not None else None,
                "rawLine": line,
            }
        )

print(json.dumps(items))
PY
