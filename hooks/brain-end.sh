#!/bin/bash
# SessionEnd: run all git work in the background so the hook exits before
# Claude Code's session teardown can cancel it. Output goes to /tmp/brain-end.log.
BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"

nohup bash -c '
  set -uo pipefail
  cd "'"$BRAIN_DIR"'"
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ -n $(git status --porcelain raw/) ]]; then
    git add raw/
    git commit -m "chore(brain): session capture $TIMESTAMP [skip ci]" \
      && git push origin main \
      || true
  else
    git push origin main 2>/dev/null || true
  fi
' > /tmp/brain-end.log 2>&1 &
disown $!

echo '{}'
