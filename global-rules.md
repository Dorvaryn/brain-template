## Brain System

Brain repo: $BRAIN_DIR (/home/dorvaryn/brain)
Brain MCP server: brain (filesystem access to the brain repo — all ops auto-allowed)
OneDrive MCP server: onedrive (filesystem access to $ONEDRIVE_DIR — reads auto-allowed, writes require confirmation; ONEDRIVE_DIR is machine-specific, set in ~/.claude/settings.json by install.sh)

### Using the hot list

**`hot.md`** is loaded at session start. It is a signal-weighted brief of what is actively moving right now — urgent items, recent captures, in-flight work. Use it for immediate situational awareness.

To find wiki page slugs or discover domain context beyond what hot.md covers, use the `mcp__brain__*` query tools — see Brain query tools below. Do not answer from general knowledge when the brain has context. If in doubt, query first.

### Keeping hot.md current

hot.md is a session-start snapshot. If it changes after /brain-dream runs, re-read via brain MCP — the MCP-read version supersedes the loaded snapshot.

### Brain query tools

The brain MCP server exposes 8 wiki query tools alongside all standard filesystem tools. Use these to discover wiki pages on demand.

- `mcp__brain__list_wiki({type, status, team, platform, project_type})` — list pages with optional filters; returns slug + first-sentence summary for each. Primary tool for finding page slugs. Valid types: project, decision, question, architecture, team, person, knowledge, week-note (plus any custom types defined in CLAUDE.md).
- `mcp__brain__get_summaries({slugs})` — fetch full Summary sections and frontmatter for specific slugs. Use after list_wiki to read detail without loading the full page.
- `mcp__brain__search_frontmatter({field, value})` — case-insensitive substring search on any frontmatter field (owner, jira_epics, project, source, etc.).
- `mcp__brain__list_recent({days})` — recent log.md entries for the last N days; more reliable than hot.md for finding recently touched pages.
- `mcp__brain__find_links({slug})` — find all wiki pages containing a [[wikilink]] to a given slug; use for impact analysis before editing.
- `mcp__brain__get_open_questions({owner?})` — list open decision/question pages; optionally filter by owner.
- `mcp__brain__search_wiki_content({query, type?, context_lines?})` — full-text search across all wiki page bodies; returns slug + matched lines with context. Use when the topic is mentioned in page body but not frontmatter.
- `mcp__brain__get_outbound_links({slug})` — return all [[wikilinks]] from the ## Links section of a page; complements find_links for full graph traversal.

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
