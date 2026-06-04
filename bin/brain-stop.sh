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
  'reason': 'BRAIN capture check. Write a capture file for: (1) A decision the USER confirmed — not a plan you proposed; only capture once endorsed. (2) An open question the USER raised or confirmed needs tracking. (3) An architectural position taken or challenged. (4) A vendor/SDK evaluation finding. Do NOT capture your own proposals — wait for the user to endorse them first. Full instructions and body structure: Brain Capture section in global-rules.md. Confirm clean if nothing applies.',
  'suppressOutput': True
}))
"
else
  rm -f "$FLAG"
  echo '{}'
fi
