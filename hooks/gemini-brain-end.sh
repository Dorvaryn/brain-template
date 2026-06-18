#!/bin/bash
set -uo pipefail
# Stop hook (agy): commit any pending raw/ captures, push, then allow stop.
BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
cd "$BRAIN_DIR" || exit 0

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ -n $(git status --porcelain raw/) ]]; then
  git add raw/ 2>/dev/null
  if git commit -m "chore(brain): session capture $TIMESTAMP [skip ci]" 2>/dev/null; then
    git push origin main 2>/dev/null \
      || true  # push failure is recoverable via /brain-sync
  fi
fi

# Always allow stop regardless of git outcome
echo '{"decision":"allow"}'
