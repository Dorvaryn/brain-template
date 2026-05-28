---
name: brain-dream
description: Run the brain dream cycle locally. Processes raw/ captures into wiki/, runs lint, commits result. Accepts optional --full flag to reprocess all raw files regardless of last run.
---

Read `$BRAIN_DIR/CLAUDE.md` and `$BRAIN_DIR/config.yml` before starting.

## 1. Determine scope

- **Default:** files in `raw/` added or modified in git since the last `dream-cycle` entry in `log.md`. Fall back to filesystem mtime if git is unavailable.
  - Newly added files: process normally.
  - Modified files (M): flag as "caution: previously ingested — check for new content vs. tooling artefact" but still process.
- **`--full`:** all files in `raw/` (excluding `.gitkeep`). Warn and wait for explicit confirmation before continuing.

Report scope: `Processing N files [since YYYY-MM-DD | full reprocess]`

---

## 2. For each file in scope — synthesis

Identify source type from path: `session | ticket | slack | gmail | outlook | outlook-calendar | google-calendar | confluence | reading | inbox | cowork | transcript`

### 2a. Extract from all source types
Extract: decisions, questions, architectural positions, projects referenced, people mentioned, epics, technical topics, travel plans, life admin items.
- Decisions → `wiki/decisions/[slug].md` with `type: decision`
- Questions → `wiki/decisions/[slug].md` with `type: question`

### 2b. Jira captures (`raw/tickets/`)
Map epic keys to teams via config.yml `teams[].jira_board`. Update project pages for referenced epics and tickets.

### 2c. Outlook email captures (`raw/outlook/`)
Route to area based on config.yml `outlook.capture_filters`. Extract architectural signals, vendor correspondence, decisions.

### 2d. Outlook calendar captures (`raw/outlook-calendar/`)
Route to area based on config.yml `outlook_calendar.calendars`.

**Timezone:** raw/outlook-calendar/ stores times as UTC ISO 8601 (e.g. `2026-05-21T09:00:00Z`). Convert to the timezone in config.yml `owner.timezone` when writing wiki pages.

**RSVP interpretation:**
- `TENTATIVE` = pending owner's priority review; do not infer attendance either way
- `ACCEPTED` = attending
- `DECLINED` = not attending; reason may be automatic (conflict, OOO) or deliberate — do not over-interpret
- Transcripts (`raw/transcripts/`) and session notes (`raw/sessions/`) are the ground truth for actual attendance; if a transcript exists for an event, the owner attended regardless of RSVP state

### 2e. Gmail captures (`raw/gmail/`)
Route to area based on config.yml `gmail.capture_filters`. Note: personal email = Gmail; work email = Outlook.

### 2f. Google Calendar captures (`raw/google-calendar/`)
Route to area based on config.yml `google_calendar.calendars`. Times are already in local time — no conversion needed. Note: personal calendar = Google Calendar; work calendar = Outlook.

### 2g. Confluence captures (`raw/confluence/`)
Route using config.yml `confluence.capture_pages` slug_prefix:
- `rfc` → find or create `wiki/architecture/rfc-NNN-slug.md`
- `adr` → find or create `wiki/architecture/adr-NNN-slug.md`

Extract: number and slug from page title, status from content body, author, teams, platforms affected.
Enrich any existing architecture page covering the same RFC/ADR — merge Confluence content into Detail and update Log; do not create a duplicate. Store Confluence page URL as `confluence_ref` in frontmatter.

### 2h. Inbox captures (`raw/inbox/`)
Route by frontmatter `type` field:
- `travel` → `wiki/projects/personal/`
- `life-admin` → `wiki/projects/personal/`
- `reading` → `wiki/knowledge/` (if substantive reference material worth retaining)
- `thought` / `capture` (unstructured) → extract decisions/questions/items, create pages as needed

No clear type: flag in lint summary for human review.

### 2i. Reading captures (`raw/reading/`)
Extract key signals into existing pages where a clear target exists. If the content is substantive standalone reference material (industry report, research paper, notable analysis), create `wiki/knowledge/[slug].md`.

### 2j. Slack captures (`raw/slack/`)
Store message permalink as `slack_ref` in frontmatter of any wiki page created or updated from a saved item.

### 2k. Transcript captures (`raw/transcripts/`)
Extract decisions, technical discussion outcomes, and action items. Update relevant project and architecture pages. Note attendees and date.

### 2l. Session captures (`raw/sessions/`)
Extract decisions, actions, and context. Update relevant project, people, and architecture pages.

### 2m. For each extracted item
Find or create the appropriate wiki page. Update content and append to the Log section.

---

## 3. Lint

Run after all files in scope have been processed.

1. **Contradictions** — scan for conflicting facts across pages; flag with `> CONFLICT:` blockquote in both pages. Never resolve silently.
2. **Orphan pages** — find wiki pages with no inbound wikilinks from index.md or other pages.
3. **Potentially resolved questions** — find `type: question, status: open` pages that may be answered by recent activity in the processed files.
4. **Stale items** — flag decisions/questions open >30 days; projects with `status.delivery: active` and no Log update in >90 days.
5. **Slack un-saves** — find resolved pages with `slack_ref` set (status: resolved/complete/seen/abandoned); list their permalinks under "Ready to un-save in Slack". Human action required.
6. Append lint summary to log.md.

---

## 4. Finalise

- Update `index.md` for all new pages
- Append dream-cycle entry to `log.md`
- Commit and push:
  ```
  git add wiki/ index.md log.md
  git commit -m "chore(brain): local dream cycle [--full] $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git push origin main
  ```
- Report: `Dream cycle complete. N files ingested. N wiki pages updated. Lint flags: [summary].`

---

## Rules

- Always read CLAUDE.md before writing any wiki page
- Raw files are immutable — never modify anything in raw/ after initial write
- Always ask for confirmation before `--full` reprocess
- Read config.yml for all team, board, area, and channel mappings — never hardcode
