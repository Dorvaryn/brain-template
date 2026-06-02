#!/bin/bash
set -uo pipefail
# Stop hook: per-turn capture reminder with flag to prevent infinite loop.
# First fire: block with reminder. Second fire: allow stop.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','unknown'))" 2>/dev/null || echo "unknown")
FLAG="/tmp/brain-stop-$SESSION_ID"

if [[ ! -f "$FLAG" ]]; then
  touch "$FLAG"
  python3 -c "
import json
print(json.dumps({
  'decision': 'block',
  'reason': 'BRAIN: End-of-turn capture check — follow Brain Capture (always active) rules in CLAUDE.md. Write captures now, or confirm nothing to capture.',
  'suppressOutput': True
}))
"
else
  rm -f "$FLAG"
  echo '{}'
fi
