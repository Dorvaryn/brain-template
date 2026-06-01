#!/bin/bash
set -uo pipefail
# SessionEnd: commit any pending raw/ captures and push.
BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
cd "$BRAIN_DIR"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ -n $(git status --porcelain raw/) ]]; then
  git add raw/
  if git commit -m "chore(brain): session capture $TIMESTAMP [skip ci]"; then
    git push origin main \
      && echo '{"systemMessage":"Brain captures committed and pushed."}' \
      || echo '{"systemMessage":"BRAIN WARNING: committed locally, push failed — run /brain-sync."}'
  else
    echo '{"systemMessage":"BRAIN WARNING: commit failed — run /brain-sync manually."}'
  fi
else
  git push origin main 2>/dev/null \
    && echo '{}' \
    || echo '{}'
fi
