#!/bin/bash
# Gemini CLI SessionStart hook — outputs JSON as required by Gemini hook spec
# Syncs the brain repo and injects status as a systemMessage

# Detect session by parent process ID (PPID) to run only once per CLI session
SESSION_TMP_DIR="$HOME/.gemini/tmp"
mkdir -p "$SESSION_TMP_DIR"
SESSION_LOCK="$SESSION_TMP_DIR/brain-sync-$PPID.lock"

# Cleanup stale lock files from inactive processes
for f in "$SESSION_TMP_DIR"/brain-sync-*.lock; do
  [[ -e "$f" ]] || continue
  pid=$(basename "$f" | cut -d'-' -f3 | cut -d'.' -f1)
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$f"
  fi
done

if [[ -f "$SESSION_LOCK" ]]; then
  # Already run in this session — exit quickly with empty JSON
  echo '{}'
  exit 0
fi

# Touch the lock file so we don't run again in this session
touch "$SESSION_LOCK"

cd "$BRAIN_DIR" || exit 0
git pull --rebase origin main 2>&1 | tail -5
echo '{}'
