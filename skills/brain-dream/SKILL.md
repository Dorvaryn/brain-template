---
name: brain-dream
description: Run the brain dream cycle locally. Processes raw/ captures into wiki/, runs lint, commits result. Accepts optional --full flag to reprocess all raw files regardless of last run.
---

## Invocation

Invoke the Workflow tool with:
- `scriptPath`: `$BRAIN_DIR/skills/brain-dream/dream-workflow.js`
- `args`: `{"brainDir": "$BRAIN_DIR", "full": false}` — set `full: true` if `--full` was passed (confirm with user first)

Do not execute the reference sections below directly. They are read by the synthesis and finalise subagents spawned by the Workflow.

---

## Reference: Scope rules (for Scope agent)

- **Default:** files in all `raw/` subdirectories added or modified in git since the last `dream-cycle` entry in `log.md`. Parse the ISO timestamp from that log entry (format: `## [YYYY-MM-DDTHH:MMZ] dream-cycle | ...`) and pass it to `git log --since="YYYY-MM-DDTHH:MMZ" --name-only`.
  - Newly added files: process normally.
  - Modified files (M): flag as "caution: previously ingested — check for new content vs. tooling artefact" but still process.
- **`--full`:** all files in `raw/` (excluding `.gitkeep`). Confirm with user before continuing.

---

## Reference: Synthesis rules (for Synthesis agents)

### 1. Determine scope

- **Default:** files in `raw/captures/`, `raw/inbox/`, and all other `raw/` subdirectories added or modified in git since the last `dream-cycle` entry in `log.md`. Parse the ISO timestamp from that log entry (format: `## [YYYY-MM-DDTHH:MMZ] dream-cycle | ...`) and pass it to `git log --since="YYYY-MM-DDTHH:MMZ" --name-only` for sub-day precision. Fall back to filesystem mtime if git is unavailable.
  - Newly added files: process normally.
  - Modified files (M): flag as "caution: previously ingested — check for new content vs. tooling artefact" but still process.
- **`--full`:** all files in `raw/` (excluding `.gitkeep`). Warn and wait for explicit confirmation before continuing.

Report scope: `Processing N files [since YYYY-MM-DDTHH:MMZ | full reprocess]`

---

### 2. For each file in scope — synthesis

Identify source type from path: `capture | ticket | slack | gmail | outlook | outlook-calendar | google-calendar | confluence | onedrive | reading | inbox | cowork | transcript`

### 2a. Extract from all source types
Extract: decisions, questions, architectural positions, projects referenced, people mentioned, epics, technical topics, theatre events, travel plans, life admin items.
- Decisions → `wiki/decisions/[slug].md` with `type: decision`
- Questions → `wiki/decisions/[slug].md` with `type: question`

### 2b. Jira captures (`raw/tickets/`)
Map epic keys to teams via config.yml `teams[].jira_board`. Update project pages for referenced epics and tickets.

### 2c. Outlook email captures (`raw/outlook/`)
Route to area based on config.yml `outlook.capture_filters`. Extract architectural signals, vendor correspondence, decisions.

**HIGH importance rule:** If an email is marked HIGH importance (flagged in the capture), it must produce at minimum a `wiki/knowledge/[slug].md` page, even when no explicit decision, question, or architectural signal is extractable. Operational frameworks, structural announcements, and org-wide launches all carry context that compounds over time. Do not silently discard HIGH importance emails because they lack an actionable item.

### 2d. Outlook calendar captures (`raw/outlook-calendar/`)
Route to area based on config.yml `outlook_calendar.calendars`.

**Timezone:** raw/outlook-calendar/ stores times as UTC ISO 8601 (e.g. `2026-05-21T09:00:00Z`). Convert to Europe/London when writing wiki pages (BST = UTC+1 in summer, GMT = UTC+0 in winter).

**RSVP interpretation:**
- `TENTATIVE` = pending Ben's priority review; do not infer attendance either way
- `ACCEPTED` = attending
- `DECLINED` = not attending; reason may be automatic (conflict, OOO) or deliberate — do not over-interpret
- Transcripts (`raw/transcripts/`) are the ground truth for actual attendance; if a transcript exists for an event, Ben attended regardless of RSVP state

**Outlook calendar settings (as of 2026-05-28):**
- Auto-decline for conflicts: OFF — conflicts arrive as Tentative; Ben reviews and responds manually
- Delete invitation from inbox after responding: ON — calendar is the source of truth, not inbox
- Show declined events on calendar: ON — declined events remain visible in calendar captures

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

### 2h. Theatre captures
Create or update `wiki/theatre/YYYY-slug.md`. Note any ATG Tickets/Artemis relevance (venue experience, ticketing flow observations).

### 2i. Inbox captures (`raw/inbox/`)
Route by frontmatter `type` field:
- `theatre` → `wiki/theatre/`
- `travel` → `wiki/projects/personal/`
- `life-admin` → `wiki/projects/personal/`
- `reading` → `wiki/knowledge/` (if substantive reference material worth retaining)
- `thought` / `capture` (unstructured) → extract decisions/questions/items, create pages as needed

No clear type: flag in lint summary for human review.

### 2j. Reading captures (`raw/reading/`)
Extract key signals into existing pages where a clear target exists. If the content is substantive standalone reference material (industry report, research paper, notable analysis), create `wiki/knowledge/[slug].md`.

### 2k. Slack captures (`raw/slack/`)
Raw Slack files contain three block types — handle each appropriately:
- `## saved-item |` → saved item; use `· saved YYYY-MM-DD` annotation
- `## dm |` → DM capture; use `· dm reference` annotation
- `## channel-thread |` → channel thread; use `· channel reference` annotation

When a wiki page is created or updated from a Slack reference, add an entry to the `## Sources` body section. Do NOT use frontmatter for Slack refs. Format:

```markdown
## Sources
- [#channel-name — brief description](url) · saved YYYY-MM-DD
- [Person Name DM — brief description](url)
- [Person A, Person B — group DM description](url)
- [#channel-name — brief description](url)
```

If the page already has a `## Sources` section, append the new line. If it doesn't, add the section between `## Links` and `## Log`. Use the message date as the `· saved` date. Description should include the channel/DM name and a brief summary of what the message was about.

When a saved item is un-saved, append `· unsaved YYYY-MM-DD` to the matching line. Do not remove the line or the URL.

### 2l. Transcript captures (`raw/transcripts/`)
Extract decisions, technical discussion outcomes, and action items. Update relevant project and architecture pages. Note attendees and date.

### 2m. OneDrive captures (`raw/onedrive/`)
Files extracted from the OneDrive sync by brain-ingest step 8. Each file contains extracted text from SharePoint documents (spotlight reports, modelling docs, product KPIs, decision docs, etc.).

Route by document name pattern and site area (from the capture header):
- Spotlight / Healthcheck reports → create or update `wiki/knowledge/[slug].md` with key findings, metrics, and signals. Use the report date in the slug (e.g. `knowledge/spotlight-report-subscription-2026-06.md`).
- Product Quick Numbers → update `wiki/knowledge/venue-rms-data-framework.md` with current KPI snapshot; note FY and data period.
- Modelling docs → update relevant project or architecture pages with the financial/commercial context.
- Decision docs (from `10 - Decisions/`) → create or update `wiki/decisions/[slug].md` with the decision context.
- Ways of Working docs → update `wiki/knowledge/venue-rms-data-framework.md` with operational framework changes.

Extract signals as with other source types: decisions, questions, architectural positions, project references.

### 2n. Inline captures (`raw/captures/`)
Single-item files written during sessions by always-active capture rules. Each file has frontmatter
(`source: capture`, `timestamp`, `repo`, `cwd`) and a body describing one decision, question, or
architectural position. Process directly — frontmatter reduces ambiguity. Route to the appropriate
wiki page as with session captures.

### 2o. For each extracted item
Find or create the appropriate wiki page. Update content and append to the Log section. Wire the page into the graph: add `[[slug]]` entries to its `## Links` section for any closely related pages — same project, decision area, team, person, or architectural area. At minimum, link to the page's natural parent (e.g. a decision links to its project page; an architecture page links to the teams it affects).

---

---

## Reference: Lint rules (for Finalise agent)

### 3. Lint

Run after all files in scope have been processed.

1. **Contradictions** — scan for conflicting facts across pages; flag with `> CONFLICT:` blockquote in both pages. Never resolve silently.
2. **Backlink repair** — for each page created or updated this run, check that closely related pages link back to it. Add any missing `[[slug]]` entries to those pages' `## Links` sections. This is the sequential complement to the outbound links added during synthesis — synthesis agents write their own page's outbound links; this pass adds the reverse links to pages that couldn't be safely edited in parallel. Report cases where no clear related page exists.
3. **Potentially resolved questions** — find `type: question, status: open` pages that may be answered by recent activity in the processed files.
4. **Stale items** — flag decisions/questions open >30 days; projects with `status.delivery: active` and no Log update in >90 days.
5. **Slack un-saves** — on pages with status resolved/complete/seen/abandoned, find any line in `## Sources` that contains `· saved` but does NOT contain `· unsaved`. List URLs under "Ready to un-save in Slack". Human action required.

---

### 4. Finalise

#### B. Generate hot.md
hot.md is the ≤8k session-start signal brief. Read the existing hot.md, then rebuild it:
- **Section 1 — Urgent / Deadline:** pages where any capture processed this cycle contains URGENT, or the page body references an explicit date within 14 days of the run timestamp, or `hot: true` in frontmatter. Never pruned.
- **Section 2 — Active This Week:** pages in "Pages created this run" or "Pages updated this run" (had signal this cycle), plus `hot: true` pages. Sort newest first.
- **Section 3 — Watching:** pages carried from the previous hot.md Watching/Active sections that are not in Urgent or Active This Week, and not now resolved/complete/abandoned. Sort newest first.
- Each entry ≤120 chars (slug + ` -- ` + summary). Trim summary to fit.
- Budget ≤8k: trim Watching oldest-first, then Active This Week from bottom. Never trim Urgent.
- Header: `# Brain Hot List\n_Updated: YYYY-MM-DDTHH:MMZ · Signal window: 30 days · Target: ≤8k_`

#### C. Log and commit
- Append to log.md: `## [YYYY-MM-DDTHH:MMZ] dream-cycle | N files → N new pages, N updated`
- Write hot.md, log.md.
- Commit and push:
  ```
  git add wiki/ hot.md log.md
  git commit -m "chore(brain): local dream cycle YYYY-MM-DDTHH:MMZ"
  git push origin main
  ```
- Return: newPages count, updatedPages count, lintFlags array (one string per flag), slackUnsaves array (Slack URLs ready to un-save).

---

---

## Reference: Agent rules (applies to all subagents)

- Always read CLAUDE.md before writing any wiki page
- Raw files are immutable — never modify anything in raw/ after initial write
- Always ask for confirmation before `--full` reprocess
- Read config.yml for all team, board, area, and channel mappings — never hardcode
