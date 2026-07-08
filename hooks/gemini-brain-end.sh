#!/bin/bash
# Stop hook (agy/Gemini): commit any pending raw/ captures in background; always allow stop.
# All git work is detached with nohup+disown — the hook exits immediately.
# Same intent as setsid on Linux; nohup+disown is the cross-platform equivalent.
BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"

nohup bash -c '
  set -uo pipefail
  cd "'"$BRAIN_DIR"'"
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ -n $(git status --porcelain raw/ bin/brain-mcp/logs/) ]]; then
    git add raw/ bin/brain-mcp/logs/
    git commit -m "chore(brain): session capture $TIMESTAMP [skip ci]" \
      && git push origin main \
      || true
  else
    git push origin main 2>/dev/null || true
  fi
' > /tmp/brain-gemini-end.log 2>&1 &
disown $!

echo '{"decision":"allow"}'
