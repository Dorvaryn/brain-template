#!/bin/bash
# Gemini CLI SessionEnd hook — outputs JSON as required by Gemini hook spec
# Commits any pending raw/ captures (best-effort: CLI may not wait for completion)
cd "$BRAIN_DIR" || exit 0
if [[ -n $(git status --porcelain raw/) ]]; then
  git add raw/ 2>&1 >/dev/null
  git commit -m "chore(brain): session capture $(date -u +%Y-%m-%dT%H:%M:%SZ) [skip ci]" 2>&1 >/dev/null
  git push origin main 2>&1 >/dev/null
  echo '{"systemMessage": "Brain captures committed."}'
else
  echo '{"systemMessage": "No brain captures pending."}'
fi
