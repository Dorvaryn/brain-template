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
  'reason': 'BRAIN: Before stopping, check this turn for anything worth capturing: decisions the user CONFIRMED (not plans you proposed), open questions identified, architectural positions the user agreed to, or evaluation findings accepted. Do NOT capture plans pending approval or options you presented but the user has not yet endorsed. Write captures now, or confirm nothing to capture.'
}))
"
else
  rm -f "$FLAG"
  echo '{}'
fi
