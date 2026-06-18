## Brain System

Brain repo: $BRAIN_DIR (/home/dorvaryn/brain)
Brain MCP server: brain (filesystem access to the brain repo — all ops auto-allowed)
OneDrive MCP server: onedrive (filesystem access to $ONEDRIVE_DIR — reads auto-allowed, writes require confirmation; ONEDRIVE_DIR is machine-specific, set in ~/.claude/settings.json by install.sh)

### Using the index

The wiki index loaded above is a session-start snapshot. Use it to:
- Identify which project, decision, or person a topic relates to
- Find the slug of the relevant wiki page (`[[slug]] -- one-line summary` format)
- Understand what is currently in flight before giving advice or making suggestions

To read a full wiki page: use the brain MCP server to read `$BRAIN_DIR/wiki/[type]/[slug].md`.
Before answering questions about specific projects, decisions, people, or architecture — read
the relevant wiki page first. Do not answer from general knowledge when the brain has context.

### Keeping the index current

The @include is a snapshot — it does not update during the session. If index.md changes (after
/brain-dream runs, or after any wiki write), re-read it via the brain MCP server at path
`$BRAIN_DIR/index.md`. The MCP-read version supersedes the loaded snapshot.

### On-demand commands

/brain-dream  — synthesise raw captures into wiki
/brain-sync   — commit and push pending raw/ captures
/brain-ingest — pull latest from Jira, Slack, Outlook, Confluence
/brain-status — health check: last dream, pending captures, open questions

---

## Brain Capture (always active)

**This is not optional.** Write a capture file immediately — before continuing the conversation — whenever any of the following occur:

- A decision the **user confirmed** (not a plan you proposed — only capture once endorsed)
- An open question identified that needs tracking
- An architectural position taken or challenged
- A vendor, provider, or SDK evaluation producing a finding

**Do not capture your own proposals until the user endorses them.** This applies to all types — decision, question, architecture, evaluation.

**Common failure modes to avoid:**
- Thinking "I'll capture this at the end" — capture now, the end hook is a safety net not the plan
- Skipping captures when absorbed in a task — notable moments are most forgettable under task pressure
- Waiting for a "clear" decision — capture emerging positions and open questions too

Write to `~/brain/raw/captures/YYYY-MM-DD-[topic].md`. One item per file.

Required frontmatter:
```
---
source: capture
type: decision | question | architecture | evaluation
timestamp: YYYY-MM-DDTHH:MM:SSZ
repo: [repo name or personal]
cwd: [working directory]
---
```

**Body structure by type** — the capture must be self-contained; do not rely on a prior question capture to supply context that belongs in a decision capture.

- **decision:** One sentence stating what was decided. Options considered (must be included even if already in a prior question capture — the decision capture is self-contained). Chosen option. Rationale: why this option over the others.
- **question:** The question in one sentence. Context/trigger: what surfaced it. Options or approaches under consideration, if known.
- **architecture:** State the position taken. Driving forces that led to it. Key trade-offs or consequences. Any constraints it imposes on future work.
- **evaluation:** Subject evaluated (tool, vendor, SDK). Key finding in one sentence. Evidence or reasoning. Recommendation or next step.

Before writing the file, run `date -u +%Y-%m-%dT%H:%M:%SZ` via Bash and use the actual value for `timestamp`. Do not approximate or round to the nearest hour.

Do not ask permission. Do not announce it. Just write it and continue.

### End of session / context switch

When the user signals they are wrapping up, switching topic, or closing the session — phrases like "that's all", "I'm done", "let's move on", "switching to X", "closing this", "thanks" at the end of a work block — **pause before responding and ask yourself**:

> "Did anything notable happen this session that isn't captured yet?"

If yes: write the capture(s) first, then respond. If no captures are needed, confirm briefly: "Nothing new to capture — session's clean."
