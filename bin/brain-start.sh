#!/bin/bash
set -uo pipefail
cd "$BRAIN_DIR"

# git pull
if git pull --rebase origin main 2>&1 | tail -5; then
  sync_status="Brain synced."
else
  sync_status="BRAIN WARNING: git pull failed — working offline."
fi

# pending check: raw files committed but not yet dream-cycled
last_commit=$(git log --format="%H %s" | grep -m1 "chore(brain): local dream cycle" | awk '{print $1}' || true)
pending_msg=""

if [[ -z "$last_commit" ]]; then
  pending_msg="No dream cycle on record — run /brain-dream before starting work."
else
  all=$(git log --name-only --diff-filter=A --pretty=format: "${last_commit}..HEAD" -- \
    raw/ 2>/dev/null | { grep -E "\.md$" || true; })
  fast=0; heavy=0
  if [[ -n "$all" ]]; then
    fast=$(echo "$all" | { grep -E "^raw/captures/" || true; } | wc -l | tr -d ' ')
    heavy=$(echo "$all" | { grep -vE "^raw/captures/" || true; } | wc -l | tr -d ' ')
  fi
  [[ "$fast" -gt 0 ]] && pending_msg="${pending_msg} ${fast} capture files pending — run /brain-dream."
  [[ "$heavy" -gt 0 ]] && pending_msg="${pending_msg} ${heavy} ingest files pending — run /brain-dream."
fi

# Output proper JSON: systemMessage for user display, additionalContext for Claude
python3 -c "
import json, sys
sync, pending = sys.argv[1], sys.argv[2].strip()
out = {'systemMessage': sync + (' ' + pending if pending else '')}
if pending:
    out['additionalContext'] = 'BRAIN: ' + pending
print(json.dumps(out))
" "$sync_status" "$pending_msg"
