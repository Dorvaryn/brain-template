---
name: brain-ingest
description: Run available capture sources and write to raw/ directories. In Claude Code with claude.ai MCPs connected, covers Jira, Slack, Outlook email, and Outlook calendar. In Gemini CLI, covers Gmail and Google Calendar via native Google tools. Run /brain-dream afterwards to synthesise into wiki.
---

Read `$BRAIN_DIR/CLAUDE.md` and `$BRAIN_DIR/config.yml` before starting.
Read `config.yml` owner.name — this is "the owner" in all queries below.
Today's date for filenames: use `date -u +%Y-%m-%d` via Bash.
Run timestamp for log entries: capture `date -u +%Y-%m-%dT%H:%MZ` via Bash at start and use it for all log.md entries written in "After all captures".

Run each capture in order. For each: write output to the appropriate raw/ file,
then report what was captured.

Skip any capture step whose integration is not configured in `config.yml` (empty section or section absent).

**On failure:** If a step fails or is unavailable, flag it clearly and retry it once
before moving on. Wait at least 5 seconds before the retry (use `sleep 5` via Bash).
If the retry also fails, report the failure with the error and continue — do not abort
the whole ingest. Mark the step as "FAILED after retry" in the final report.

---

## 1. Jira capture

Uses: Atlassian MCP
Reads: `config.yml` teams[].jira_board (skip teams where jira_board is null)
Lookback: `config.yml` jira.lookback_hours (default 24h)

Two tiers per board. Run both passes. Write all output to `raw/tickets/YYYY-MM-DD.md` (append if exists).

### Tier 1 — Personal involvement (full detail)
- Query issues updated in the last lookback_hours where the owner is assignee, reporter, or mentioned
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
Read `config.yml` jira.workflow to determine board type (kanban or scrum).

**Kanban boards:** Query all non-epic issues updated in the last lookback_hours,
excluding tickets already written in Tier 1. Also query epics with a status change in the last lookback_hours.

**Scrum boards:** Query active sprint issues updated in the last lookback_hours,
excluding tickets already written in Tier 1. Note the sprint name.

**Scope rules:**
- Include: In Progress, In Review, and equivalent active states
- Done tickets: omit individually — emit a count only: `Done this period: N`
- Backlog tickets: omit unless the board has no separate "active" column (triage boards)
- Epics: only those with a status change in the lookback window

Write as a summary block per board:

```
## Team summary: [board prefix] — [YYYY-MM-DD]
Workflow: [kanban|scrum]
Updated in last [N]h: [total count]
Active work:
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
Reads: `config.yml` slack (skip if section absent or empty)

### Canvases
- For each canvas in config.yml slack.canvases: read the full canvas content via `slack_read_canvas`
- Write to `raw/slack/YYYY-MM-DD.md` under a `## canvas |` heading:

```
## [HH:MM] canvas | [canvas name]
Source: [channel]
Area: [from config]
Content: [full canvas text]
```

### Saved items
- Fetch saved items since the last slack-capture log entry: find the most recent `slack-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] slack-capture | ...`), extract the date portion (`YYYY-MM-DD`), and use it as an `after:YYYY-MM-DD` filter in the search query (e.g. `is:saved after:2026-06-01`). The Slack search API accepts date only — time precision is not available here. If no prior slack-capture log entry exists, fetch all saved items.
- For each: fetch message content and thread context, note permalink
- Area: infer from channel name using config.yml channel list

### Monitored channels
- For each channel in config.yml slack.capture_channels:
  - priority high: fetch all threads active in last 24h
  - priority low: fetch only threads where the owner participated or was @mentioned, or >5 replies
  - priority mention-only: fetch only threads where the owner is directly @mentioned
- Fetch thread context for each

Write to `raw/slack/YYYY-MM-DD.md` (append if file exists for today):

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
Reads: `config.yml` outlook.capture_filters (skip if section absent or empty)

- Determine lookback threshold: find the most recent `outlook-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] outlook-capture | ...`) and extract the full ISO timestamp. Pass this to `outlook_email_search` as the received-after datetime filter — use the full timestamp, not just the date, to avoid re-fetching emails received earlier in the same day as the last ingest. If no prior outlook-capture log entry exists, fall back to 24h lookback.
- For each filter: search emails matching the query received since that threshold
- Skip any email that contains financial data, invoice details, or purchase order information
- **For any "vendor" or external-contact filter:** apply judgment — only capture direct correspondence
  (replies, proposals, follow-ups, introductions). Skip marketing emails, newsletters,
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
Reads: `config.yml` outlook_calendar (skip if section absent or empty)

**Timezone:** The M365 MCP returns times in UTC. Write all times as UTC ISO 8601
(e.g. `2026-05-21T09:00:00Z`) and add a file-level header: `Timezone: UTC (convert to
[config.yml owner.timezone] when writing wiki pages)`. Do not silently strip the timezone.

- For each calendar: fetch events for the next lookforward_days days and any events updated in the last 24h

**Three-tier event classification** (read suppress_titles and compact_recurring from config):

**Tier 1 — Skip entirely:** Events whose title matches any entry in `suppress_titles`.
Note total count skipped in the final report line.

**Tier 2 — Compact (one line):** Recurring events not in the suppress list. Write as:
`- [Title] — [HH:MMZ–HH:MMZ] — [area] [(TENTATIVE)]`
Only applies when `compact_recurring: true` in config.

**Tier 3 — Full format:** Any event that meets one or more of:
- Non-recurring (one-off meeting)
- Has external attendees (email domain not matching owner's org domain)
- Owner is the organiser
- Monthly or quarterly cadence

Full format:
```
## [calendar-name] Event Title
Area: [mapped from config]
Date/Time: ...
Location: ...
Organizer: [if not owner]
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
  - Slug: lowercase, hyphens, derived from event subject
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

Reads: `config.yml` gmail.capture_filters (skip if section absent or empty)
Lookback: since last gmail-capture log entry (default 24h)

Use whichever Google tool is available:
- Native Google/Gmail tools (available in Gemini CLI)
- Gmail MCP server (if configured)
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

Reads: `config.yml` google_calendar (skip if section absent or empty)

Use whichever Google tool is available:
- Native Google/Calendar tools (available in Gemini CLI)
- Google Calendar MCP server (if configured)
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
Reads: `config.yml` confluence.capture_pages (skip if section absent or empty)

- For each entry in capture_pages:
  - Use `searchConfluenceUsingCql` to find pages under `page_id` modified since the last
    `confluence-capture` log entry in `log.md`:
    `ancestor = "[page_id]" AND lastModified >= "YYYY-MM-DD"`
    (on first run — no prior entry — omit the `lastModified` clause to capture all pages)
  - Timestamp threshold: find the most recent `confluence-capture` line in `log.md` (format: `## [YYYY-MM-DDTHH:MMZ] confluence-capture | ...`) and extract the date portion (`YYYY-MM-DD`) for the CQL filter. CQL `lastModified` accepts date only.

**For each returned page — version-aware capture:**

1. Call `getConfluencePage` to get the current page including `version.number`
2. Grep the most recent `raw/confluence/*.md` file for `Page ID: [id]` to find the
   previously captured `Version:` field
3. **If version unchanged** (comment-only activity):
   - Do NOT re-capture the body
   - Call `getConfluencePageFooterComments` and `getConfluencePageInlineComments`
   - Write a compact entry with comment summaries only (see format below)
4. **If version changed** OR **no prior capture found**:
   - Write full body entry (see format below)
   - Truncate body at 3000 words if necessary; note truncation inline

**Full body format:**
```
## [slug_prefix-NNN] Title
Source: confluence/[slug_prefix]
Page ID: [page_id]
Version: [version.number]
URL: [full confluence URL for the page]
Last Modified: [date]
Author: [author display name]
Status: [draft|proposed|in-review|accepted|superseded|deprecated|unknown]

Content: [full page body rendered as plain text / markdown]
```

**Comment-only format:**
```
## [slug_prefix-NNN] Title — comment activity
Source: confluence/[slug_prefix]
Page ID: [page_id]
Version: [version.number] (unchanged — body not re-captured)
URL: [full confluence URL for the page]
Last Modified: [date]

### New comments since last capture:
- [Author] ([date]): [brief summary]
```

---

## After all captures

Write one log.md entry per source that ran (or was attempted), using the run timestamp captured at start. Append to `$BRAIN_DIR/log.md`:

```
## [YYYY-MM-DDTHH:MMZ] jira-capture | brief summary (e.g. "N issues/epics")
## [YYYY-MM-DDTHH:MMZ] slack-capture | brief summary (e.g. "N saved items + N threads")
## [YYYY-MM-DDTHH:MMZ] outlook-capture | brief summary (e.g. "N emails")
## [YYYY-MM-DDTHH:MMZ] calendar-capture | brief summary (e.g. "N full, N compact, N skipped")
## [YYYY-MM-DDTHH:MMZ] confluence-capture | brief summary (e.g. "N pages")
```

Omit any source that was skipped entirely (not just empty). Mark failed sources: `## [YYYY-MM-DDTHH:MMZ] jira-capture | FAILED after retry: [error]`

Report:
```
Ingest complete.
  Jira:             N issues/epics written to raw/tickets/YYYY-MM-DD.md
  Slack:            N saved items + N channel threads written to raw/slack/YYYY-MM-DD.md
  Outlook email:    N emails written to raw/outlook/YYYY-MM-DD.md
  Outlook calendar: N events written to raw/outlook-calendar/YYYY-MM-DD.md
  Transcripts:      N new transcripts written to raw/transcripts/ (N skipped)
  Gmail:            [N captured | skipped — not configured]
  Google Calendar:  [N events | skipped — not configured]
  Confluence:       [N pages | skipped — not configured]

Run /brain-sync to commit captures, then /brain-dream to synthesise into wiki.
```

Do not commit or push -- leave that to /brain-sync and /brain-dream.

**Do not auto write `raw/captures/` files during ingest.** The raw files written above (tickets, slack, outlook, confluence, etc.) are already the capture. Writing additional files to `raw/captures/` for signals found in ingest data creates duplicates that the dream cycle processes twice. Only write a `raw/captures/` file if something notable surfaces in the conversation itself — something the ingest pipeline would not otherwise record.
