---
name: brain-status
description: Quick brain health check. Reports last dream cycle, pending captures, open questions, and stale decisions. No writes.
---

Run these steps, then report:

1. Read last 10 entries from `$BRAIN_DIR/log.md` via the brain MCP server
2. Run `git status --porcelain raw/` in `$BRAIN_DIR` to count uncommitted raw/ files
3. Count decision files in `wiki/decisions/` with `status: open`
4. Count decision files in `wiki/decisions/` with `status: open` and date older than 30 days
5. Get last commit timestamp: `git log -1 --format="%ci %s"` in `$BRAIN_DIR`

Report:
```
Brain status:
Last dream cycle: [timestamp from log, or "never run"]
Pending captures: N files in raw/ not yet committed
Open questions:   N
Stale decisions:  N (open >30 days)
Last sync:        [last commit timestamp and message]
```
