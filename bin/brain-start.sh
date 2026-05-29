#!/bin/bash
set -uo pipefail
cd "$BRAIN_DIR"

if ! git pull --rebase origin main 2>/dev/null; then
  echo "BRAIN WARNING: git pull failed — working offline."
fi

last_commit=$(git log --format="%H %s" | grep -m1 "chore(brain): local dream cycle" | awk '{print $1}' || true)

if [[ -z "$last_commit" ]]; then
  echo "BRAIN: No dream cycle on record. Run /brain-dream before starting work."
else
  all=$(git log --name-only --diff-filter=A --pretty=format: "${last_commit}..HEAD" -- \
    raw/ 2>/dev/null | { grep -E "\.md$" || true; })

  fast=0; heavy=0
  if [[ -n "$all" ]]; then
    fast=$(echo "$all" | { grep -E "^raw/(captures|sessions)/" || true; } | wc -l | tr -d ' ')
    heavy=$(echo "$all" | { grep -vE "^raw/(captures|sessions)/" || true; } | wc -l | tr -d ' ')
  fi

  if [[ "$fast" -gt 0 ]]; then echo "BRAIN: $fast capture/session files pending — run /brain-dream."; fi
  if [[ "$heavy" -gt 0 ]]; then echo "BRAIN: $heavy ingest files pending — run /brain-dream."; fi
fi
