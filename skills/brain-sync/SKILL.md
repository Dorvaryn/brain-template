---
name: brain-sync
description: Commit and push any pending raw/ captures to the remote brain repo. Use to make session captures available on other machines immediately.
---

1. Check for uncommitted changes: `git -C $BRAIN_DIR status --porcelain`
2. If changes exist:
   - `git -C $BRAIN_DIR add -A`
   - `git -C $BRAIN_DIR commit -m "chore(brain): manual sync $(date -u +%Y-%m-%dT%H:%M:%SZ) [skip ci]"`
3. `git -C $BRAIN_DIR pull --rebase origin main`
4. `git -C $BRAIN_DIR push origin main`
5. Report: "Synced. N files committed. Remote had X new commits." (use 0 if none in each case)
