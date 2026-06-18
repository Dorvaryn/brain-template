---
name: brain-ingest
description: Run available capture sources and write to raw/ directories. In Claude Code with claude.ai MCPs connected, covers Jira, Slack, Outlook email, Outlook calendar, Confluence, and OneDrive sites configured in config.yml (via local OneDrive sync at $ONEDRIVE_DIR). In Gemini CLI, covers Gmail and Google Calendar via native Google tools. Run /brain-dream afterwards to synthesise into wiki.
---

## Invocation

Invoke the Workflow tool with:
- `scriptPath`: `$BRAIN_DIR/skills/brain-ingest/ingest-workflow.js`
- `args`: `{"brainDir": "$BRAIN_DIR"}`

Do not execute the sections below directly. They are read by the per-source subagents spawned by the Workflow.

---

## Reference: Per-source capture instructions (for source agents)

Read `$BRAIN_DIR/CLAUDE.md` and `$BRAIN_DIR/config.yml` before starting each capture.
Today's date for filenames: use `date -u +%Y-%m-%d` via Bash.
Run timestamp for log entries: capture `date -u +%Y-%m-%dT%H:%MZ` via Bash at start.

For each capture: write output to the appropriate raw/ file, then report what was captured.

**On failure:** If a step fails or is unavailable, flag it clearly and retry it once
before moving on. Wait at least 5 seconds before the retry (use `sleep 5` via Bash).
If the retry also fails, report the failure with the error and continue — do not abort
the whole ingest. Mark the step as "FAILED after retry" in the final report.

---

## 1. Jira capture

Uses: Atlassian MCP
Reads: `config.yml` teams[].jira_board (NUTS-, AA-, MPH-)
Lookback: find the most recent `jira-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] jira-capture | ...`) and use that timestamp as the lookback threshold. Fall back to `config.yml` jira.lookback_hours (default 24h) if no prior entry exists. This closes weekend/gap blind spots — a ticket that went Done on Friday will still be captured by Monday's ingest.

Two tiers per board. Run both passes. Write all output to `raw/tickets/YYYY-MM-DD.md` (append if exists).

### Tier 1 — Personal involvement (full detail)
- Query issues updated since the lookback threshold where Ben is assignee, reporter, or mentioned
- Also fetch all epics with status changes in that window (regardless of involvement)

```
## [TICKET-ID] Title
Team: [mapped from config]
Type: issue|epic
Status: ...
Updated: ...
Summary: ...
My involvement: assignee|reporter|mentioned|epic-watcher
```

### Tier 2 — Team summary (if `config.yml` jira.capture_team_summary is true)
Teams use Kanban (no sprints). Query all non-epic issues updated since the lookback threshold,
excluding tickets already written in Tier 1. No body text -- one line per ticket.
Also query epics with a status change since the lookback threshold (not all active epics).

**Fields to request:** `["summary", "status", "assignee"]` only — no description, no body.
This is critical for controlling response size on active boards like AA.

**Scope rules:**
- Include in query: In Progress, In Review, Selected for Development, In Design Review, Ready for Three Amigos, **and Done**
- Done tickets: include in the query and list individually in output (same one-line format as active tickets). Also emit a count: `Done this period: N`
- Backlog tickets: omit unless MPH board (where Backlog = active security debt awaiting triage)
- Epics: only those with a status change in the lookback window — ticket movement within
  in-flight epics is captured via the ticket query above; this line only tracks epic-level transitions

**Done count:** Count Done tickets from the results of this query (filter locally by `status == "Done"`). Do NOT run a separate API query for Done tickets.

Write as a summary block per board:

```
## Team summary: [board prefix] — [YYYY-MM-DD]
Workflow: Kanban
Updated in last [N]h: [total count]
Active work (In Progress / In Review / equivalent):
- [TICKET-ID] Title — [status] (assignee: [name])
- ...
Done this period: N
Epics with status change:
- [EPIC-ID] Title — [old status] → [new status]
- ...
```

---

## 2. Slack capture

Uses: Slack MCP
Reads: `config.yml` slack.saved_items and slack.capture_channels

### Canvases
- For each canvas in config.yml slack.canvases: call `slack_read_canvas` using `canvas_id` from config directly (no search needed)
- These are living documents — check every ingest for new agenda items, decisions, and actions
- **Truncation rule:** Canvas content accumulates unboundedly. After reading, extract and write only sections dated within the last 14 days. Discard all older agenda sections. If date headings are absent, include only the first 3000 characters.
- Write to `raw/slack/YYYY-MM-DD.md` under a `## canvas |` heading:

```
## [HH:MM] canvas | [canvas name]
Source: [channel]
Area: [from config]
Content: [current week + prior week sections only]
```

### Saved items
- Lookback date (for DMs and channel threads only, not saved items): find the most recent `slack-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] slack-capture | ...`), extract the date portion (`YYYY-MM-DD`), then **subtract 1 day** to get the `after:` parameter. Slack's `after:` filter is exclusive — `after:2026-06-08` returns messages from June 9+, not June 8 itself. Subtracting 1 day ensures the day of the last capture is included. Compute via Bash: `date -u -d "YYYY-MM-DD - 1 day" +%Y-%m-%d` (or `date -u -v-1d -j -f %Y-%m-%d YYYY-MM-DD +%Y-%m-%d` on macOS). If no prior entry exists, omit the date filter.
- Fetch saved items: search `is:saved` — **no date filter**. Volume is low (~20 items total) and the `after:` filter uses message send date, not save date, causing saved older messages to be silently missed.
- **Deduplication:** before writing each saved item, check if its permalink already appears in any `raw/slack/*.md` file. Skip items already captured. This replaces the date filter as the mechanism for avoiding re-ingestion.
- For each new item: fetch message content and thread context, note permalink
- Area: infer from channel name using config.yml channel list
- **PII rule:** Skip messages that contain people's private PII — home addresses, personal phone numbers, personal financial account details. Personal context (theatre, travel, life admin, personal tech) is within scope; the brain covers Ben's personal life as well as work.

### DMs
Only runs if `config.yml slack.capture_dms.enabled` is true.

- Search `after:YYYY-MM-DD` with `channel_types: im,mpim` (same lookback date as saved items above)
- This catches both 1:1 DMs and group DMs automatically — no need to know channel IDs in advance
- For each result: note participants, permalink, and message content
- Group messages from the same DM conversation together where possible
- Apply the same PII rule as saved items: skip messages containing people's private PII.
- Write each message as its own `## [HH:MM] dm |` block — the dream cycle will add it to the relevant wiki page's `## Sources` section.
- Write to `raw/slack/YYYY-MM-DD.md` (append):

```
## [HH:MM] dm | Brief description
Source: [participant name(s), comma-separated]
Channel-ID: [D... or G... — for slack_refs backfill]
Permalink: [url]
Participants: [full name list]
Content: [message content, include thread context if available]
```

### Monitored channels
- For each channel in config.yml capture_channels:
  - priority high: fetch all threads active in last 24h
  - priority low: fetch only threads where Ben participated or was @mentioned, or >5 replies
  - priority mention-only: fetch only threads where Ben is directly @mentioned (ignore reply count)
- Fetch thread context for each

- Write to `raw/slack/YYYY-MM-DD.md` (append if file exists for today):

```
## [HH:MM] saved-item | Brief description
Source: [channel]
Permalink: [url]
Participants: [names]
Content: [message and relevant thread]

## [HH:MM] channel-thread | Brief description
Source: [channel]
Area: [from config]
Permalink: [url]
Participants: [names]
Content: [thread summary]
```

---

## 3. Outlook email capture

Uses: Microsoft 365 MCP (outlook_email_search)
Reads: `config.yml` outlook.capture_filters

- Determine lookback threshold: find the most recent `outlook-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] outlook-capture | ...`) and extract the full ISO timestamp. Pass this to `outlook_email_search` as the received-after datetime filter — use the full timestamp, not just the date, to avoid re-fetching emails received earlier in the same day as the last ingest. If no prior outlook-capture log entry exists, fall back to 24h lookback.
- For each filter: search emails matching the query received since that threshold
- Skip any email that contains financial data, invoice details, or purchase order information
- **For the `vendor` filter specifically:** apply judgment — only capture direct correspondence
  (vendor replies, proposals, follow-ups, introductions). Skip marketing emails, newsletters,
  automated notifications, and system-generated messages even if they pass the query filter.
- Write to `raw/outlook/YYYY-MM-DD.md` (append if file exists for today):

```
## [filter-label] Subject
Area: [from config]
From: ...
Date: ...
Summary: [brief -- no financial details]
```

---

## 4. Outlook calendar capture

Uses: Microsoft 365 MCP (outlook_calendar_search)
Reads: `config.yml` outlook_calendar.calendars, outlook_calendar.lookforward_days,
       outlook_calendar.suppress_titles, outlook_calendar.compact_recurring

**Timezone:** The M365 MCP returns times in UTC. Write all times as UTC ISO 8601
(e.g. `2026-05-21T09:00:00Z`) and add a file-level header: `Timezone: UTC (convert to
Europe/London when writing wiki pages)`. Do not silently strip the timezone — raw files
must be unambiguous so the dream cycle can convert correctly.

- For each calendar: fetch events for the next lookforward_days days and any events
  updated in the last 24h

**Three-tier event classification** (read suppress_titles and compact_recurring from config):

**Tier 1 — Skip entirely:** Events whose title matches any entry in `suppress_titles`
(e.g. "Daily Stand-up", "Apps Stand-Up"). These are pure recurring noise — omit completely,
do not write to raw file. Note total count skipped in the final report line.

**Tier 2 — Compact (one line):** Recurring events not in the suppress list. Write as a
single line: `- [Title] — [HH:MMZ–HH:MMZ] — [area] [(TENTATIVE)]`
No attendees, no description, no location unless non-standard. Only applies when
`compact_recurring: true` in config.

**Tier 3 — Full format:** Apply to any event that meets one or more of:
- Non-recurring (one-off meeting)
- Has external attendees (email domain not atgentertainment.com)
- Ben is the organiser
- Monthly or quarterly cadence (Showcase, Global Company Call, etc.)
- Description or attendees changed since last capture
- Title contains keywords: Solution Architect, Leadership Team, Principal, Strategy, AMA

Full format:
```
## [calendar-name] Event Title
Area: [mapped from config]
Date/Time: ...
Location: ...
Organizer: [if not Ben]
Attendees: [full list]
Description: [if present]
```

Write all output to `raw/outlook-calendar/YYYY-MM-DD.md` (append if file exists for today).
End the file with: `Total events: [full] full, [compact] compact, [skipped] skipped`

---

## 4b. Teams meeting transcript capture

**M365 concurrency note:** The Microsoft 365 MCP enforces a concurrency limit. Step 4
and step 4b both use `outlook_calendar_search` — running them back-to-back will trigger
a `CommandConcurrencyLimitReached` (503) error. Before starting this step, run
`sleep 5` via Bash to allow the previous M365 call to clear.

Uses: Microsoft 365 MCP (outlook_calendar_search + read_resource)
Reads: `config.yml` outlook_calendar.capture_transcripts and outlook_calendar.transcript_lookback_days
Only runs if `capture_transcripts: true`.

- Search Outlook calendar for past events in the last `transcript_lookback_days` days that were Teams meetings
- For each event: read the full event via `read_resource` to get the `meetingTranscriptUrl` field
- Skip if `meetingTranscriptUrl` is absent (no transcript available)
- Skip if a file `raw/transcripts/YYYY-MM-DD-[slug].md` already exists for that event (already captured)
  - Slug: lowercase, hyphens, derived from event subject (e.g. "how-is-ai-going")
  - Check by listing `raw/transcripts/` for files matching the event date prefix
- For each new transcript: call `read_resource` with the `meetingTranscriptUrl` value verbatim
- Write to `raw/transcripts/YYYY-MM-DD-[slug].md` (one file per meeting):

```
## Transcript: [Event Subject]
Date: YYYY-MM-DDTHH:MM:SSZ
Attendees: [comma-separated names]
Area: [mapped from calendar config — match organiser or attendees to known teams]
MeetingTranscriptUrl: [verbatim meetingTranscriptUrl value — for re-fetch if needed]

[Full transcript content as returned by read_resource]
```

Report count of transcripts captured (new) and skipped (already exists or no transcript).

---

## 5. Gmail capture

Reads: `config.yml` gmail.capture_filters
Lookback: since last gmail-capture log entry (default 24h)

Use whichever Google tool is available:
- Native Google/Gmail tools (available in Gemini CLI)
- Gmail MCP server (available in CI with OAuth configured)
- If neither is available: report "Gmail capture skipped -- no Google tools available" and continue.

For each filter in config: search emails matching the query.
Skip any email containing financial data, invoice details, or purchase order information.

Write to `raw/gmail/YYYY-MM-DD.md` (append if exists):

```
## [filter-label] Subject
Area: [from config]
From: ...
Date: ...
Summary: [brief -- no financial details]
```

---

## 6. Google Calendar capture

Reads: `config.yml` google_calendar.calendars and google_calendar.lookforward_days
Note: personal calendar = Google Calendar; work calendar = Outlook (capture 4 above).

Use whichever Google tool is available:
- Native Google/Calendar tools (available in Gemini CLI)
- Google Calendar MCP server (available in CI with OAuth configured)
- If neither is available: report "Google Calendar capture skipped -- no Google tools available" and continue.

For each calendar: fetch events for the next lookforward_days days and any events updated in the last 24h.

Write to `raw/google-calendar/YYYY-MM-DD.md` (append if exists):

```
## [calendar-name] Event Title
Area: [mapped from config]
Date/Time: ...
Location: ...
Attendees: [if relevant]
Description: [if relevant]
```

---

## 7. Confluence capture

Uses: Atlassian MCP
Reads: `config.yml` confluence.capture_pages

- For each entry in capture_pages:
  - Use `searchConfluenceUsingCql` to find pages under `page_id` modified since the last
    `confluence-capture` log entry in `log.md`:
    `ancestor = "[page_id]" AND lastModified >= "YYYY-MM-DD"`
    (on first run — no prior entry — omit the `lastModified` clause to capture all pages)
  - Timestamp threshold: find the most recent `confluence-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] confluence-capture | ...`) and extract the date portion (`YYYY-MM-DD`) for the CQL filter. CQL `lastModified` accepts date only. Do not use `jira.lookback_hours`.

**For each returned page — version-aware capture (mandatory — do not skip):**

1. Call `getConfluencePage` to get the current page including `version.number`
2. Grep the most recent `raw/confluence/*.md` file for `Page ID: [id]` to find the
   previously captured `Version:` field
3. **If version unchanged** (comment-only activity):
   - Do NOT re-capture the body — this is the primary cost-saving gate
   - Call `getConfluencePageFooterComments` and `getConfluencePageInlineComments` to
     fetch new comments
   - Write a compact entry with comment summaries only (see format below)
4. **If version changed** OR **no prior capture found**:
   - Write full body entry (see format below)
   - Truncate body at 3000 words if necessary; note truncation inline

**Full body format** (version changed or first capture):
```
## [RFC-NNN] Title  or  [ADR-NNN] Title
Source: confluence/rfc  or  confluence/adr
Page ID: [page_id]
Version: [version.number]
URL: [full confluence URL for the page]
Last Modified: [date]
Author: [author display name]
Status: [extracted from page content — draft|proposed|in-review|accepted|superseded|deprecated|unknown]

Content: [full page body rendered as plain text / markdown]
```

**Comment-only format** (version unchanged):
```
## [RFC-NNN] Title — comment activity
Source: confluence/rfc  or  confluence/adr
Page ID: [page_id]
Version: [version.number] (unchanged — body not re-captured)
URL: [full confluence URL for the page]
Last Modified: [date]

### New comments since last capture:
- [Author] ([date]): [brief summary of comment content]
- [Author] ([date]): [brief summary]
```

If no comments are found despite `lastModified` changing (e.g. minor metadata update),
write the compact header with a note: `No new comments found — minor metadata change, skipped.`

---

## 8. OneDrive capture

Uses: onedrive filesystem MCP (mcp__onedrive__list_directory, mcp__onedrive__read_file) + Bash (for binary extraction)
Reads: `config.yml` onedrive.sites (per-site: capture_recursive, exclude_patterns, on_demand)
Requires: onedrive MCP registered and running (install.sh handles this; requires Claude Code restart after registration).

**Access method: local OneDrive sync only.** M365 MCP SharePoint tools are NOT used — they miss recently uploaded files (index lag) and cannot access files by path. Local sync is ground truth.

**Pre-flight check:** Verify the onedrive MCP is accessible:
- Use `mcp__onedrive__list_directory` on `$ONEDRIVE_DIR`
- If it fails: report "OneDrive capture skipped — onedrive MCP not available. Restart Claude Code after install.sh." and skip this step.

**Lookback:** Find the most recent `onedrive-capture` line in `log.md`. Use each file's mtime (via `mcp__onedrive__get_file_info`) to skip files unmodified since that timestamp. On first run, capture all files in scope.

**Traversal — per site, recursive with exclusions:**

For each site in `config.yml onedrive.sites`:
1. Walk `$ONEDRIVE_DIR/[site.path]` recursively using `mcp__onedrive__list_directory`
2. For each path component, check against `site.exclude_patterns` (glob match):
   - Skip any path matching `*/Historical/*`, `*[DEPRECATED]*`, `*[Deprecated]*`, `desktop.ini`
   - Add new exclusion patterns to config.yml when new noise categories emerge
3. For each file, check against `site.on_demand[]`:
   - If entry has no `filename_pattern`: skip any file whose path starts with `entry.path`
   - If entry has `filename_pattern`: skip only files where path starts with `entry.path` AND filename matches the glob (e.g. `*Roadmap Pipeline*.xlsx`)
   - For each matched (skipped) file: check its mtime against the last `onedrive-capture` timestamp. If modified since last capture, add to the ingest summary: "ℹ on_demand file modified: [entry.name] ([filename]) — read via mcp__onedrive__ when needed"
   - Skipped files are available for direct session reads from `$ONEDRIVE_DIR/[site.path]/[entry.path]`
4. For each remaining file: check mtime — skip if not modified since last `onedrive-capture`
5. Skip files already written to `raw/onedrive/YYYY-MM-DD.md` this run (dedup by filename)
6. Extract content based on file type:
   - `.docx`: Bash Python — extract `word/document.xml` text nodes from the ZIP
   - `.pptx`: Bash Python — extract `ppt/slides/slide*.xml` text nodes from the ZIP
   - `.pdf`: `mcp__onedrive__read_file` (text layer only; note if binary)
   - `.txt` / `.md`: `mcp__onedrive__read_text_file`
   - `.xlsx`: Bash Python — zipfile + sharedStrings + sheet XML extraction
   - `.rtf` / `.eml`: skip — not extractable; write metadata-only entry
7. Truncate extracted content at 3000 words; note truncation inline

Write to `raw/onedrive/YYYY-MM-DD.md` (append if file exists for today):

```
## [filename]
Source: onedrive/[area from config]
Local Path: $ONEDRIVE_DIR/[site.path]/[relative path]
Last Modified: [from file_info]

Content: [extracted text — truncated at 3000 words if needed]
```

If extraction fails or format unsupported:

```
## [filename] — metadata only
Source: onedrive/[area]
Local Path: $ONEDRIVE_DIR/[site.path]/[relative path]
Last Modified: [from file_info]
Note: [reason — unsupported format / extraction error]
```

Documents matched by `site.on_demand` are NOT ingested — read directly from `$ONEDRIVE_DIR/[site.path]` during sessions when needed.

**Config gap check (run after traversing each site):**
List the direct (first-level) subfolders of `$ONEDRIVE_DIR/[site.path]` using `mcp__onedrive__list_directory`. For each subfolder name:
- Covered by any `site.exclude_patterns` glob? → known, skip
- Is a top-level component of any `site.on_demand[].path`? → known, skip
- System file (`desktop.ini`, `.DS_Store`)? → skip
- Otherwise: flag in the ingest summary — "⚠ Unconfigured subfolder in [site.name]: [name] — review and add to on_demand (with optional filename_pattern) or exclude_patterns if needed"

Rationale: catches new major sections added to the framework before they silently flow into ingest. Deeper new content within existing sections is already captured automatically by recursive traversal. Skip silently if onedrive MCP unavailable.

---

## After all captures

Write one log.md entry per source that ran (or was attempted), using the run timestamp captured at start. Append to `$BRAIN_DIR/log.md`:

```
## [YYYY-MM-DDTHH:MMZ] jira-capture | brief summary (e.g. "NUTS: N, AA: N, MPH: N personal")
## [YYYY-MM-DDTHH:MMZ] slack-capture | brief summary (e.g. "N saved items + N threads")
## [YYYY-MM-DDTHH:MMZ] outlook-capture | brief summary (e.g. "N emails")
## [YYYY-MM-DDTHH:MMZ] calendar-capture | brief summary (e.g. "N full, N compact, N skipped")
## [YYYY-MM-DDTHH:MMZ] confluence-capture | brief summary (e.g. "N RFCs + N ADRs")
## [YYYY-MM-DDTHH:MMZ] onedrive-capture | brief summary (e.g. "N docs captured, N skipped (unsupported)")
```

Omit any source that was skipped entirely (not just empty). Mark failed sources: `## [YYYY-MM-DDTHH:MMZ] jira-capture | FAILED after retry: [error]`

Report:
```
Ingest complete.
  Jira:             N issues/epics written to raw/tickets/YYYY-MM-DD.md
  Slack:            N saved items + N DMs + N channel threads written to raw/slack/YYYY-MM-DD.md
  Outlook email:    N emails written to raw/outlook/YYYY-MM-DD.md
  Outlook calendar: N events written to raw/outlook-calendar/YYYY-MM-DD.md
  Transcripts:      N new transcripts written to raw/transcripts/ (N skipped — already captured or no transcript)
  Gmail:            skipped (OAuth not configured)
  Google Calendar:  skipped (OAuth not configured)
  Confluence:       N RFC pages + N ADR pages written to raw/confluence/YYYY-MM-DD.md
  OneDrive:         N docs written to raw/onedrive/YYYY-MM-DD.md (N skipped — unchanged/on_demand/unsupported) [skipped if onedrive MCP unavailable]
  on_demand modified: [list names if any changed since last capture, else "none"]
  Config gaps: [list unconfigured subfolders if any, else "none"]

Run /brain-sync to commit captures, then /brain-dream to synthesise into wiki.
```

Do not commit or push -- leave that to /brain-sync and /brain-dream.

**Do not auto write `raw/captures/` files during ingest.** The raw files written above (tickets, slack, outlook, confluence, etc.) are already the capture. Writing additional files to `raw/captures/` for signals found in ingest data creates duplicates that the dream cycle processes twice. Only write a `raw/captures/` file if something notable surfaces in the conversation itself — something the ingest pipeline would not otherwise record.
