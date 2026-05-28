# Brain Schema and Agent Instructions

Read this file before any operation on this repo. It is the source of truth for all agents.

---

## Identity

Edit this section after forking. All agents read it to understand who you are and what you do.

Owner: [YOUR_NAME], [YOUR_ROLE] at [YOUR_ORG].
Domain: [YOUR_DOMAIN — e.g. "Backend Engineering", "Product Management", "iOS Development"]

Teams and integrations are configured in `config.yml`. Do not hardcode team names or board prefixes here.

Personal context: [YOUR_PERSONAL_CONTEXT — e.g. hobbies, side projects, areas of life you want tracked]

---

**First-time setup detected?** If this Identity section still contains `[YOUR_NAME]` or other
placeholders, the repo has not been configured yet. Ask the user for their name, role, org,
domain, teams, integrations, timezone, and personal areas — then:
1. Fill in this Identity section
2. Update `config.yml` owner block and teams list
3. Run `bash bin/setup-check.sh` and report what still needs manual wiring outside the repo
Do not proceed with any wiki operations until Identity is filled in.

---

## Architecture Pattern

Karpathy LLM-wiki: compile knowledge once and maintain it. Do not re-derive at query time.
The wiki is a persistent, compounding artifact. The LLM writes it. AI tools and humans read it.

Three immutable layers:
1. `raw/` -- immutable captures. Written by hooks and agents. Never modified after write.
2. `wiki/` -- LLM-maintained synthesis. Written only by the dream cycle or brain-ops commands.
3. `CLAUDE.md` -- this file. The schema. Read first, always.

The wiki is the AI's persistent memory layer. At session start, load the relevant wiki context
so the AI arrives with full situational awareness. Consistent frontmatter and page structure
exist to serve machine parsing as much as human readability. The data format is tool-agnostic:
any AI with filesystem access (Claude, Gemini, etc.) can read and query it.

---

## Entity Types and Frontmatter

### teams/ [area].md

```yaml
---
type: team
area: string
jira_board: string|null
platforms: list
status: active|inactive
---
```

### projects/ [area]/[slug].md

```yaml
---
type: project
team: string
project_type: platform|cross-cutting|evaluation|roadmap|devex|personal
status:
  delivery: discovery|active|paused|complete|abandoned
  leadership/personal: discovery|active|paused|decided|complete|abandoned
started: date
jira_epics: list
milestones:
  - label: string
    status: pending|active|complete
    date: date
slack_refs: list
---
```

Use `jira_epics` for delivery projects. Use `milestones` for leadership/personal projects.

### decisions/ [slug].md

Two entity types live here: formal choices (`decision`) and investigative questions (`question`).
Both share the same schema and page format. `type` is the only distinguisher.

```yaml
---
type: decision | question
status: open|resolved|superseded|abandoned
team: string
project: string
owner: string    # DRI — expected on questions; optional on decisions
raised: date
resolved: date   # omit when open
slack_ref: url
---
```

**Distinction:** `decision` = formal choice made between known options, rationale documented.
`question` = investigation that resolves with a finding. Both use `status: resolved` when done.

### people/ [firstname-lastname].md

```yaml
---
type: person
role: string
org: string
team: string
relationship: internal|external|vendor
---
```

### architecture/ [slug].md

```yaml
---
type: architecture
status: current|proposed|deprecated
teams: list
platforms: list
date: date
confluence_ref: url  # optional — Confluence page URL when sourced from RFC/ADR capture
---
```

### knowledge/ [slug].md

Durable reference material worth retaining that is not tied to an active project.
Use for: industry reports, research, statistics, frameworks, domain context, notable reads.
Not for: in-flight work (use projects/), decisions (use decisions/), or raw session notes.

```yaml
---
type: knowledge
area: string   # matches a personal area or team area from config.yml
source: string   # publication, URL, or origin description
date: date       # date read or published (prefer read date)
tags: list       # free-form; used for cross-referencing
---
```

Detail section: key facts, numbers, and signals extracted from the source.
Use sub-headings for structure. Keep it dense — this is a reference, not a summary.

---

## slack_ref Behaviour

Optional field on decisions, questions, projects, and theatre pages.
Stores Slack message permalink when item originated from a Slack saved item.

Lifecycle:
- Saved in Slack => captured to raw/slack/ with permalink => dream cycle creates wiki page with slack_ref
- Item stays saved in Slack while wiki page is unresolved
- When wiki page status changes to resolved (resolved/complete/seen): lint pass queues un-save
- Slack saved items list is a live view of unresolved captured items

---

## Page Format

All wiki pages use this structure:

```
---
[YAML frontmatter as above]
---

## Summary
One paragraph. Current state as of last update.

## Detail
Main body. Appropriate to entity type:
- Projects: background, approach, constraints, current state
- Decisions: context, options considered, rationale, outcome
- Architecture: the position, driving forces, trade-offs, consequences
- Knowledge: key facts, numbers, signals — dense reference, use sub-headings

## Links
[[related-page]] -- one line on why it is related

## Log
- YYYY-MM-DD: One-line note on what changed
```

---

## index.md and log.md Conventions

**index.md**: sections match wiki/ subdirectories. Each entry: `[[page-link]] -- one-line summary`

**log.md**: each entry prefixed `## [YYYY-MM-DD] operation | description`

Valid operations: ingest, lint, slack-capture, jira-capture, gmail-capture, outlook-capture,
calendar-capture, transcript-capture, confluence-capture, dream-cycle, manual

---

## Domain Model

### Session Detection

Read teams from `config.yml` teams[]. For each team with a `jira_board` value:
- If the current git branch starts with that prefix, set the active team to that team's `area`
- If no branch prefix matches and the repo is not a known personal repo: ask once "Which team/area is this session for?"
- For personal sessions (no Jira prefix, personal repo): set area from context

### Project Types

```
platform       -- Feature/delivery work for a specific team
cross-cutting  -- Spans multiple teams or platforms
evaluation     -- Vendor, provider, or SDK evaluations
roadmap        -- Strategic roadmap initiatives
devex          -- Developer experience and tooling
personal       -- Personal projects and life admin
```

### Personal Areas

Customise in `config.yml`. Default examples:

```
Personal Tech  -- side projects, home automation, dotfiles
Learning       -- books, courses, articles (cross-cutting with work)
Life Admin     -- insurance, banking, admin tasks
Travel         -- trips, bookings, itineraries
Health         -- structure exists, empty until needed
Finance        -- manual entries only, no automated ingest, sensitive
```

Add, remove, or rename areas to match your life. The system has no hard dependency on any specific area names.

---

## Working with the Wiki

These rules apply to any agent writing or editing wiki pages — whether during a dream cycle, a session capture, or a manual operation.

**Page format**
- Always follow the entity schema for the relevant type (frontmatter, section order, field values)
- `## Summary` = one paragraph describing current state only. No history, no corrections.
- Corrections and history belong in `## Detail` and `## Log`
- Log entries: `- YYYY-MM-DD: one-line note on what changed`

**After any write**
- New page: add an entry to `index.md` under the appropriate section
- Any page (new or updated): append to `log.md` with operation `manual` and a brief description
- Run `/brain-sync` to commit changes

**Conflicts**
- Never resolve contradictions between pages silently
- Flag with `> CONFLICT:` blockquote in both affected pages and surface in the next lint pass

**Lint and finalise**
- Full synthesis and lint steps are defined in the `/brain-dream` skill
- For manual edits outside the dream cycle, lint is not required — but conflict checks and index/log updates are

---

## Skills Reference

Raw data capture (how to populate `raw/`): see `/brain-ingest` skill
Synthesis and lint (how to turn `raw/` into `wiki/`): see `/brain-dream` skill

---

## Agent Rules

- Read config.yml for all team, board, area, and channel mappings. Never hardcode.
- Raw files are immutable. Never modify anything in raw/ after initial write.
- Wiki is LLM-maintained. Human reads, LLM writes. Do not bypass this.
- When uncertain where something belongs: create a new page.
- Always update index.md and log.md after any write operation.
- Never resolve conflicts silently. Flag them with `> CONFLICT:` and let the human decide.
- Finance is manual only. Never write financial data to any wiki or raw file automatically.

---

## Repo Structure Reference

```
brain/
+-- CLAUDE.md                          # This file. Read first.
+-- prompt.md                          # Global prompt injected into all Claude Code sessions.
+-- config.yml                         # Runtime config. Edit here, not in workflows.
+-- index.md                           # Master content index. LLM-maintained.
+-- log.md                             # Append-only operation log.
+-- raw/
|   +-- sessions/                      # All session captures
|   +-- tickets/                       # Nightly Jira pull
|   +-- slack/                         # Slack saved items + monitored channels
|   +-- gmail/                         # Targeted Gmail capture (personal email)
|   +-- outlook/                       # Targeted Outlook capture (work email)
|   +-- google-calendar/               # Google Calendar events (personal)
|   +-- outlook-calendar/              # Outlook Calendar events (work, via M365 MCP)
|   +-- confluence/                    # RFC and ADR page captures
|   +-- transcripts/                   # Teams meeting transcripts
|   +-- reading/                       # Web Clipper drops + manual reading notes
|   +-- inbox/                         # Manual captures — quick notes, unstructured
|   +-- cowork/                        # Cowork outputs
+-- wiki/
|   +-- teams/
|   +-- projects/
|   |   +-- my-team/                   # Example: matches area: "my-team" in config.yml
|   |   |                              # Add one subdirectory per team area defined in config.yml
|   |   +-- leadership/                # Always present — cross-team and org-level work
|   |   +-- personal/                  # Always present — personal projects and life admin
|   +-- decisions/                     # decisions (type: decision) and questions (type: question)
|   +-- people/
|   +-- architecture/
|   +-- knowledge/                     # Durable reference: industry reports, research, domain context
|   +-- week-notes/
+-- templates/
+-- skills/
|   +-- brain-session/SKILL.md
|   +-- brain-dream/SKILL.md
|   +-- brain-ingest/SKILL.md
|   +-- brain-status/SKILL.md
|   +-- brain-sync/SKILL.md
+-- bin/
|   +-- brain-start.sh           # SessionStart hook — git pull
|   +-- brain-end.sh             # SessionEnd hook — auto-commit raw/ captures
+-- .github/workflows/
```
