#!/bin/bash
# Runs at Claude Code session start via the SessionStart hook.
# Syncs the brain repo so the session starts with current context.

if [ -z "$BRAIN_DIR" ]; then
  echo "BRAIN_DIR not set — skipping brain sync. Set it in ~/.claude/settings.json."
  exit 0
fi

cd "$BRAIN_DIR" || exit 0

if git pull --rebase origin main 2>&1 | tail -5; then
  echo "Brain synced."
else
  echo "Brain sync failed (no network or remote not configured). Continuing with local state."
fi
