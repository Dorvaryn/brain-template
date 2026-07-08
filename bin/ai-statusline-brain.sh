#!/bin/bash
# ai-statusline-brain.sh — Extremely fast wiki documentation metrics
# Counts pending captures via git, and open questions/decisions via awk frontmatter parsing.

BRAIN_DIR="${BRAIN_DIR:-$HOME/brain}"
cd "$BRAIN_DIR" 2>/dev/null || exit 0

# 1. Count all pending raw files (un-dreamed) since last dream cycle
last_commit=$(git log --format="%H %s" 2>/dev/null | grep -m1 "chore(brain): local dream cycle" | awk '{print $1}' || true)
fast=0
if [[ -n "$last_commit" ]]; then
  all=$(git log --name-only --diff-filter=A --pretty=format: "${last_commit}..HEAD" -- raw/ 2>/dev/null | { grep -E "\.md$" || true; })
  if [[ -n "$all" ]]; then
    fast=$(echo "$all" | wc -l | tr -d ' ')
  fi
fi

# 2. Count open questions and unresolved decisions — single awk pass over frontmatter
METRICS=$(awk '
FNR == 1 { in_front = 0; found_start = 0; type = ""; status = "" }
/^---/ {
  if (!found_start) { found_start = 1; in_front = 1; next }
  if (in_front) {
    if (type == "question" && status == "open") q++
    else if (type == "decision" && status == "open") d++
    nextfile
  }
}
in_front && /^type:/   { type   = $2 }
in_front && /^status:/ { status = $2 }
END { print q+0, d+0 }
' "$BRAIN_DIR/wiki/decisions/"*.md 2>/dev/null)
METRICS=${METRICS:-0 0}
open_q=$(echo "$METRICS" | awk '{print $1}')
open_d=$(echo "$METRICS" | awk '{print $2}')

# Format output nicely: captures, questions, decisions
# Example: 2 📥 | ❓ 4 | ⚡ 1
printf "%d 📥 | ❓ %d | ⚡ %d" "$fast" "$open_q" "$open_d"
