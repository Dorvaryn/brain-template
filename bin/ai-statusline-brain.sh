#!/bin/bash
# gemini-statusline-brain.sh — Extremely fast wiki documentation metrics
# Counts pending captures via git, and open questions/decisions via Python frontmatter parsing.

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

# 2. Count open questions and unresolved decisions using a fast Python parser
METRICS_RAW=$(python3 - <<'PYEOF'
import os
decisions_dir = os.path.expanduser("~/brain/wiki/decisions")
open_q = 0
open_d = 0

if os.path.exists(decisions_dir):
    for filename in os.listdir(decisions_dir):
        if filename.endswith(".md"):
            filepath = os.path.join(decisions_dir, filename)
            try:
                with open(filepath, errors='ignore') as f:
                    content = f.read()
                parts = content.split("---")
                if len(parts) >= 3:
                    frontmatter = parts[1]
                    metadata = {}
                    for line in frontmatter.splitlines():
                        if ":" in line:
                            k, v = line.split(":", 1)
                            metadata[k.strip()] = v.strip()
                    doc_type = metadata.get("type")
                    status = metadata.get("status", "open")
                    if doc_type == "question" and status == "open":
                        open_q += 1
                    elif doc_type == "decision" and status == "open":
                        open_d += 1
            except Exception:
                continue

print(f"{open_q} {open_d}")
PYEOF
)

# If the Python command failed or was empty, default to "0 0"
METRICS=${METRICS_RAW:-0 0}

# Extract counts
open_q=$(echo "$METRICS" | awk '{print $1}')
open_d=$(echo "$METRICS" | awk '{print $2}')

# Format output nicely: captures, questions, decisions
# Example: 2 📥 | ❓ 4 | ⚡ 1
printf "%d 📥 | ❓ %d | ⚡ %d" "$fast" "$open_q" "$open_d"
