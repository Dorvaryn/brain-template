#!/bin/bash
# Gemini CLI SessionStart hook — outputs JSON as required by Gemini hook spec
# Syncs the brain repo and injects status as a systemMessage
cd "$BRAIN_DIR" || exit 0

git_output=$(git pull --rebase origin main 2>&1)
git_exit=$?
git_tail=$(echo "$git_output" | tail -3 | tr '\n' ' ' | xargs)
if [[ $git_exit -eq 0 ]]; then
  sync_status="Brain synced. $git_tail"
else
  sync_status="BRAIN WARNING: git pull failed — working offline. $git_tail"
fi

pending_msg=""
last_commit=$(git log --format="%H %s" | grep -m1 "chore(brain): local dream cycle" | awk '{print $1}' || true)
if [[ -z "$last_commit" ]]; then
  pending_msg=" BRAIN: No dream cycle on record. Run /brain-dream before starting work."
else
  all=$(git log --name-only --diff-filter=A --pretty=format: "${last_commit}..HEAD" -- \
    raw/ 2>/dev/null | { grep -E "\.md$" || true; })
  fast=0; heavy=0
  if [[ -n "$all" ]]; then
    fast=$(echo "$all" | { grep -E "^raw/(captures|sessions)/" || true; } | wc -l | tr -d ' ')
    heavy=$(echo "$all" | { grep -vE "^raw/(captures|sessions)/" || true; } | wc -l | tr -d ' ')
  fi
  if [[ "$fast" -gt 0 ]]; then pending_msg="$pending_msg BRAIN: $fast capture/session files pending — run /brain-dream."; fi
  if [[ "$heavy" -gt 0 ]]; then pending_msg="$pending_msg BRAIN: $heavy ingest files pending — run /brain-dream."; fi
fi

python3 -c "
import json, sys
sync_status, pending = sys.argv[1], sys.argv[2]
print(json.dumps({'systemMessage': sync_status + pending}))
" "$sync_status" "$pending_msg"
