#!/bin/bash
# Runs at Claude Code session end via the SessionEnd hook.
# Commits and pushes any new raw/ captures so they are available on other machines.

if [ -z "$BRAIN_DIR" ]; then
  exit 0
fi

cd "$BRAIN_DIR" || exit 0

if [[ -n $(git status --porcelain raw/) ]]; then
  git add raw/
  git commit -m "chore(brain): session capture $(date -u +%Y-%m-%dT%H:%M:%SZ) [skip ci]"
  git push origin main
  echo "Brain captures committed."
fi
