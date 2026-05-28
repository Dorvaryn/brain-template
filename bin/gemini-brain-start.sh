#!/bin/bash
# Gemini CLI SessionStart hook — outputs JSON as required by Gemini hook spec
# Syncs the brain repo and injects status as a systemMessage
cd "$BRAIN_DIR" || exit 0
result=$(git pull --rebase origin main 2>&1 | tail -3)
python3 -c "
import json, sys
msg = 'Brain synced. ' + sys.argv[1].replace('\n', ' ').strip()
print(json.dumps({'systemMessage': msg}))
" "$result"
